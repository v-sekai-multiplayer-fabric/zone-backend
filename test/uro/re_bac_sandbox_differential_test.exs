# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.ReBAC.SandboxAdapterDifferentialTest do
  @moduledoc """
  Differential testing for RFD 0022 (Stage 4): every case here runs
  through both `Uro.ReBAC.TaskweftAdapter` (the native `tw_rebac.hpp`
  NIF) and `Uro.ReBAC.SandboxAdapter` (compiled Scheme in the libriscv
  guest) and must agree, proving the port before any config-flip in
  production traffic.
  """
  use ExUnit.Case, async: true

  alias Uro.ReBAC.SandboxAdapter
  alias Uro.ReBAC.TaskweftAdapter

  setup do
    elf_path = Path.join(:code.priv_dir(:uro), "rebac.elf")

    start_supervised!(
      {WeftWarpBurrito.Program, elf: File.read!(elf_path), name: SandboxAdapter.Program}
    )

    :ok
  end

  defp build(adapter, edges) do
    Enum.reduce(edges, adapter.new_graph(), fn {subj, obj, rel}, graph ->
      adapter.add_edge(graph, subj, obj, rel)
    end)
  end

  defp assert_agrees(edges, subj, rel, obj) do
    native = build(TaskweftAdapter, edges) |> TaskweftAdapter.check_rel(subj, rel, obj)
    sandboxed = build(SandboxAdapter, edges) |> SandboxAdapter.check_rel(subj, rel, obj)

    assert native == sandboxed,
           "adapters disagree for #{inspect({edges, subj, rel, obj})}: " <>
             "native=#{native} sandbox=#{sandboxed}"

    native
  end

  test "direct edge match" do
    edges = [{"alice", "zone1", "OWNS"}]
    assert assert_agrees(edges, "alice", "OWNS", "zone1")
    refute assert_agrees(edges, "bob", "OWNS", "zone1")
    refute assert_agrees(edges, "alice", "CAN_ENTER", "zone1")
  end

  test "transitive IS_MEMBER_OF inheritance" do
    edges = [
      {"alice", "avatar_uploaders", "IS_MEMBER_OF"},
      {"avatar_uploaders", "uploads", "HAS_CAPABILITY"}
    ]

    assert assert_agrees(edges, "alice", "HAS_CAPABILITY", "uploads")
    refute assert_agrees(edges, "bob", "HAS_CAPABILITY", "uploads")
  end

  test "two-deep membership chain" do
    edges = [
      {"alice", "group_a", "IS_MEMBER_OF"},
      {"group_a", "group_b", "IS_MEMBER_OF"},
      {"group_b", "zone1", "CAN_ENTER"}
    ]

    assert assert_agrees(edges, "alice", "CAN_ENTER", "zone1")
  end

  test "CONTROLS via DELEGATED_TO inversion" do
    edges = [{"zone1", "alice", "DELEGATED_TO"}]
    assert assert_agrees(edges, "alice", "CONTROLS", "zone1")
    refute assert_agrees([], "alice", "CONTROLS", "zone1")
  end

  test "empty graph is always false" do
    refute assert_agrees([], "alice", "OWNS", "zone1")
  end

  test "membership does not imply an unrelated relation" do
    edges = [{"alice", "group_a", "IS_MEMBER_OF"}]
    refute assert_agrees(edges, "alice", "OWNS", "zone1")
  end

  test "matches the real-world zone-entry graph shape from Uro.VSekai" do
    edges = [
      {"owner-1", "zone-1", "OWNS"},
      {"owner-1", "zone-1", "CAN_ENTER"}
    ]

    assert assert_agrees(edges, "owner-1", "CAN_ENTER", "zone-1")
    refute assert_agrees(edges, "stranger-2", "CAN_ENTER", "zone-1")
  end
end
