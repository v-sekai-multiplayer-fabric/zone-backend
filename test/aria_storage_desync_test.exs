# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule AriaStorage.DesyncInteropTest do
  @moduledoc """
  Cross-verifies that aria_storage (Elixir) and desync (Go) produce
  casync-compatible output that each can read from the other.

  Tagged :desync — only runs when the desync binary is present in PATH.
  In CI: install desync and run `mix test --include desync`.
  In local dev: tests are skipped automatically unless desync is installed.
  """
  use ExUnit.Case, async: false

  @moduletag :desync

  # 512 KB produces ~8 chunks at the 64 KB average, exercising real multi-chunk paths.
  @test_size 512 * 1024

  setup_all do
    desync = System.find_executable("desync")
    desync = if is_binary(desync), do: desync, else: nil

    if desync do
      Application.ensure_all_started(:aria_storage)
    end

    {:ok, desync: desync}
  end

  setup %{desync: desync} do
    if is_nil(desync) do
      ExUnit.skip(
        "desync binary not found in PATH — install from https://github.com/folbricht/desync"
      )
    end

    tmp =
      Path.join(
        System.tmp_dir!(),
        "aria_desync_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "aria_storage make → desync extract round-trip", %{tmp: tmp, desync: desync} do
    input = Path.join(tmp, "source.bin")
    File.write!(input, :crypto.strong_rand_bytes(@test_size))
    original_sha = sha256(input)

    aria_out = Path.join(tmp, "aria_out")
    File.mkdir_p!(aria_out)

    Mix.Tasks.AriaStorage.Make.run([
      "--input",
      input,
      "--output",
      aria_out,
      "--name",
      "test"
    ])

    index = Path.join(aria_out, "test.caibx")
    store = Path.join(aria_out, "store")
    assert File.exists?(index), "aria_storage did not produce test.caibx"
    assert File.dir?(store), "aria_storage did not produce store/ directory"

    extracted = Path.join(tmp, "desync_extracted.bin")

    {output, rc} =
      System.cmd(desync, ["extract", "--store", store, index, extracted], stderr_to_stdout: true)

    assert rc == 0, "desync extract failed (exit #{rc}):\n#{output}"

    assert sha256(extracted) == original_sha,
           "desync-extracted content differs from original"
  end

  test "desync make → aria_storage decode round-trip", %{tmp: tmp, desync: desync} do
    input = Path.join(tmp, "source.bin")
    File.write!(input, :crypto.strong_rand_bytes(@test_size))
    original_sha = sha256(input)

    desync_out = Path.join(tmp, "desync_out")
    store = Path.join(desync_out, "store")
    index = Path.join(desync_out, "test.caibx")
    File.mkdir_p!(store)

    {output, rc} =
      System.cmd(desync, ["make", "--store", store, index, input], stderr_to_stdout: true)

    assert rc == 0, "desync make failed (exit #{rc}):\n#{output}"
    assert File.exists?(index), "desync did not produce index file"

    aria_out = Path.join(tmp, "aria_out")
    File.mkdir_p!(aria_out)

    {:ok, result} =
      AriaStorage.CasyncDecoder.decode_file(index,
        store_path: store,
        output_dir: aria_out,
        verify_integrity: true
      )

    assert result.assembly_result != nil,
           "aria_storage did not attempt assembly from desync-produced chunks"

    extracted = Path.join(aria_out, "test")
    assert File.exists?(extracted), "aria_storage did not write output file"

    assert sha256(extracted) == original_sha,
           "aria_storage-decoded content differs from original"
  end

  defp sha256(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
