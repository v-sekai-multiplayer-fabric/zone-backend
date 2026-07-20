# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.Release do
  @moduledoc """
  Release-time helpers for the standalone `taskweft` binary (issue #53).

  `wrap/1` is the final `mix release` step. It packages the assembled
  release into a self-contained per-triplet binary with Burrito, but only
  when a zig cross-compiler is available (Burrito's backend) or the build
  explicitly opts in via `TASKWEFT_BURRITO=1`. Otherwise it returns the
  release untouched, so `mix release taskweft` still succeeds on a machine
  without the toolchain (the entrypoint wiring can be assembled and inspected
  locally; the shippable binaries are produced in CI where zig is installed).
  """

  require Logger

  @doc """
  Burrito wrap step, guarded on toolchain availability.
  """
  def wrap(release) do
    if wrap?() do
      Burrito.wrap(release)
    else
      Logger.info(
        "taskweft: skipping Burrito wrap (no zig toolchain / TASKWEFT_BURRITO unset) — " <>
          "assembled release only"
      )

      release
    end
  end

  defp wrap? do
    System.get_env("TASKWEFT_BURRITO") == "1" or zig_available?()
  end

  defp zig_available?, do: System.find_executable("zig") != nil
end
