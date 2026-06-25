# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Standalone casync interop check.
# Run with: mix run --no-start priv/interop/casync_check.exs
#
# Does NOT start the Uro application — no database required.
# Verifies two round-trips:
#   1. aria_storage make  → desync extract   (Elixir chunks readable by Go)
#   2. desync make        → aria_storage decode (Go chunks readable by Elixir)

defmodule CasyncCheck do
  def fail(msg) do
    IO.puts("FAIL: #{msg}")
    System.halt(1)
  end

  def sha256(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  def run do
    Application.ensure_all_started(:aria_storage)

    desync =
      case System.find_executable("desync") do
        nil -> fail("desync binary not found in PATH")
        path -> path
      end

    test_size = 512 * 1024
    tmp = Path.join(System.tmp_dir!(), "casync_interop_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    input = Path.join(tmp, "source.bin")
    File.write!(input, :crypto.strong_rand_bytes(test_size))
    original_sha = sha256(input)

    IO.puts("Input size:    #{test_size} bytes")
    IO.puts("Input SHA-256: #{original_sha}")

    run_round_trip_1(tmp, input, original_sha, desync)
    run_round_trip_2(tmp, input, original_sha, desync)

    File.rm_rf!(tmp)
    IO.puts("\nAll casync interop checks passed.")
  end

  # ── Round-trip 1: aria_storage make → desync extract ───────────────────────

  defp run_round_trip_1(tmp, input, original_sha, desync) do
    IO.puts("\n[1/2] aria_storage make → desync extract")

    aria_out = Path.join(tmp, "aria_out")
    File.mkdir_p!(aria_out)

    Mix.Tasks.AriaStorage.Make.run(["--input", input, "--output", aria_out, "--name", "test"])

    index = Path.join(aria_out, "test.caibx")
    store = Path.join(aria_out, "store")

    unless File.exists?(index), do: fail("aria_storage did not produce test.caibx")
    unless File.dir?(store), do: fail("aria_storage did not produce store/")

    chunks = Path.wildcard(Path.join(store, "**/*.cacnk"))
    IO.puts("  aria_storage produced #{length(chunks)} chunk(s)")

    extracted = Path.join(tmp, "desync_extracted.bin")

    {output, rc} =
      System.cmd(desync, ["extract", "--store", store, index, extracted], stderr_to_stdout: true)

    unless rc == 0, do: fail("desync extract exited #{rc}\n#{output}")

    extracted_sha = sha256(extracted)

    unless extracted_sha == original_sha,
      do: fail("desync-extracted SHA-256 #{extracted_sha} != original #{original_sha}")

    IO.puts("  PASS — #{File.stat!(extracted).size} bytes, SHA-256 matches")
  end

  # ── Round-trip 2: desync make → aria_storage decode ────────────────────────

  defp run_round_trip_2(tmp, input, original_sha, desync) do
    IO.puts("\n[2/2] desync make → aria_storage decode")

    desync_out = Path.join(tmp, "desync_out")
    d_store = Path.join(desync_out, "store")
    d_index = Path.join(desync_out, "test.caibx")
    File.mkdir_p!(d_store)

    {output, rc} =
      System.cmd(desync, ["make", "--store", d_store, d_index, input], stderr_to_stdout: true)

    unless rc == 0, do: fail("desync make exited #{rc}\n#{output}")

    d_chunks = Path.wildcard(Path.join(d_store, "**/*.cacnk"))
    IO.puts("  desync produced #{length(d_chunks)} chunk(s)")

    aria_out = Path.join(tmp, "aria_out2")
    File.mkdir_p!(aria_out)

    case AriaStorage.CasyncDecoder.decode_file(d_index,
           store_path: d_store,
           output_dir: aria_out,
           verify_integrity: true
         ) do
      {:ok, result} ->
        extracted = Path.join(aria_out, "test")
        unless File.exists?(extracted), do: fail("aria_storage did not write output file")

        extracted_sha = sha256(extracted)

        unless extracted_sha == original_sha,
          do: fail("aria_storage-decoded SHA-256 #{extracted_sha} != original #{original_sha}")

        IO.puts("  PASS — #{File.stat!(extracted).size} bytes, SHA-256 matches")
        IO.puts("  integrity_verified=#{result.integrity_verified}")

      {:error, reason} ->
        fail("AriaStorage.CasyncDecoder.decode_file/2 error: #{inspect(reason)}")
    end
  end
end

CasyncCheck.run()
