# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.ReBAC.SandboxAdapterDifferentialTest do
  @moduledoc """
  Regression suite for `Uro.ReBAC.SandboxAdapter` (compiled Scheme in
  the libriscv guest, RFD 0022 -- Stage 4 of the sandbox roadmap).

  These cases originally ran through both `Uro.ReBAC.TaskweftAdapter`
  (the native `tw_rebac.hpp` NIF) and `Uro.ReBAC.SandboxAdapter`,
  asserting agreement, to prove the port before the RFD 0038 config-flip
  that made the sandbox adapter the only one. The native adapter is now
  retired, so each case just pins the value that comparison already
  proved correct.
  """
  use ExUnit.Case, async: true

  alias Uro.ReBAC.SandboxAdapter

  # SandboxAdapter.Program is booted globally by Uro.Application, since
  # RFD 0038 made Uro.ReBAC.SandboxAdapter the default :rebac_adapter --
  # no per-test start_supervised! needed (and starting a second one under
  # the same name would collide with the already-running one).

  defp build(edges) do
    Enum.reduce(edges, SandboxAdapter.new_graph(), fn {subj, obj, rel}, graph ->
      SandboxAdapter.add_edge(graph, subj, obj, rel)
    end)
  end

  defp check(edges, subj, rel, obj), do: build(edges) |> SandboxAdapter.check_rel(subj, rel, obj)

  test "direct edge match" do
    edges = [{"alice", "zone1", "OWNS"}]
    assert check(edges, "alice", "OWNS", "zone1")
    refute check(edges, "bob", "OWNS", "zone1")
    refute check(edges, "alice", "CAN_ENTER", "zone1")
  end

  test "transitive IS_MEMBER_OF inheritance" do
    edges = [
      {"alice", "avatar_uploaders", "IS_MEMBER_OF"},
      {"avatar_uploaders", "uploads", "HAS_CAPABILITY"}
    ]

    assert check(edges, "alice", "HAS_CAPABILITY", "uploads")
    refute check(edges, "bob", "HAS_CAPABILITY", "uploads")
  end

  test "two-deep membership chain" do
    edges = [
      {"alice", "group_a", "IS_MEMBER_OF"},
      {"group_a", "group_b", "IS_MEMBER_OF"},
      {"group_b", "zone1", "CAN_ENTER"}
    ]

    assert check(edges, "alice", "CAN_ENTER", "zone1")
  end

  test "CONTROLS via DELEGATED_TO inversion" do
    edges = [{"zone1", "alice", "DELEGATED_TO"}]
    assert check(edges, "alice", "CONTROLS", "zone1")
    refute check([], "alice", "CONTROLS", "zone1")
  end

  test "empty graph is always false" do
    refute check([], "alice", "OWNS", "zone1")
  end

  test "membership does not imply an unrelated relation" do
    edges = [{"alice", "group_a", "IS_MEMBER_OF"}]
    refute check(edges, "alice", "OWNS", "zone1")
  end

  test "matches the real-world zone-entry graph shape from Uro.VSekai" do
    edges = [
      {"owner-1", "zone-1", "OWNS"},
      {"owner-1", "zone-1", "CAN_ENTER"}
    ]

    assert check(edges, "owner-1", "CAN_ENTER", "zone-1")
    refute check(edges, "stranger-2", "CAN_ENTER", "zone-1")
  end
end
