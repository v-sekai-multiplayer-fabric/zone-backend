# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.ReBAC.SandboxAdapter do
  @moduledoc """
  ReBAC adapter that checks relations by running compiled Scheme
  (`c_src/s7/fixtures/rebac.scm`, RFD 0022 -- Stage 4 of the sandbox
  roadmap) inside the libriscv guest, instead of the native
  `Taskweft.ReBAC` NIF. Ported from `standalone/tw_rebac.hpp`'s
  `check_base`: direct edge match, transitive IS_MEMBER_OF, and
  CONTROLS-via-DELEGATED_TO inversion.

  The graph never touches guest memory -- it stays a host-owned Elixir
  list of `[subj, obj, rel]` lists (GuestValue handles, RFD 0021), and
  the guest walks it one cons cell at a time through the trampoline.
  `@rel_consts` covers the vocabulary the algorithm itself needs to
  recognize (IS_MEMBER_OF / CONTROLS / DELEGATED_TO); the subset has no
  string literals, so these are passed in as a boxed list rather than
  embedded in the guest program.

  Requires `Uro.ReBAC.SandboxAdapter.Program` to be running (started by
  `Uro.Application` when `:rebac_adapter` is configured to this
  module -- see the config-flip in RFD 0022).
  """
  @behaviour Uro.Ports.ReBAC

  alias WeftWarpBurrito.Program

  @rel_consts ["IS_MEMBER_OF", "CONTROLS", "DELEGATED_TO"]

  @impl true
  def new_graph, do: []

  @impl true
  def add_edge(graph, subj, obj, rel), do: [[subj, obj, rel] | graph]

  @impl true
  def check_rel(graph, subj, rel, obj) do
    case Program.call(program(), "check-rel", [graph, subj, rel, obj, @rel_consts]) do
      {:ok, result} when is_boolean(result) -> result
      {:error, reason} -> raise "Uro.ReBAC.SandboxAdapter.check_rel failed: #{inspect(reason)}"
    end
  end

  defp program do
    case Process.whereis(__MODULE__.Program) do
      pid when is_pid(pid) ->
        pid

      nil ->
        raise "Uro.ReBAC.SandboxAdapter.Program is not running -- " <>
                "start it (see Uro.Application) before selecting this adapter"
    end
  end
end
