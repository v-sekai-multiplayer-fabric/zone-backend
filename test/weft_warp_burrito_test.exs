defmodule WeftWarpBurritoTest do
  use ExUnit.Case

  # Same golden vectors this was ported from: s7_riscv_loot_golden_test.cpp
  # / s7_riscv_combat_golden_test.cpp / s7_riscv_progression_golden_test.cpp,
  # each checked against a Lean4 reference.
  test "loot_roll matches the Lean4 reference" do
    {:ok, pid} = WeftWarpBurrito.Sandbox.start_link()
    assert {:ok, 3} = WeftWarpBurrito.Sandbox.loot_roll(pid)
  end

  test "combat_replay matches the Lean4 reference" do
    {:ok, pid} = WeftWarpBurrito.Sandbox.start_link()
    assert {:ok, {30, 90, 1}} = WeftWarpBurrito.Sandbox.combat_replay(pid)
  end

  test "progression_replay matches the Lean4 reference" do
    {:ok, pid} = WeftWarpBurrito.Sandbox.start_link()
    assert {:ok, {150, 16}} = WeftWarpBurrito.Sandbox.progression_replay(pid)
  end

  test "gas exhaustion is reported, not crashed" do
    {:ok, pid} = WeftWarpBurrito.Sandbox.start_link()
    assert {:error, :gas_exhausted} = WeftWarpBurrito.Sandbox.combat_replay(pid, 100)
  end

  test "each Sandbox actor is independent" do
    {:ok, pid1} = WeftWarpBurrito.Sandbox.start_link()
    {:ok, pid2} = WeftWarpBurrito.Sandbox.start_link()
    assert {:ok, 3} = WeftWarpBurrito.Sandbox.loot_roll(pid1)
    assert {:ok, 3} = WeftWarpBurrito.Sandbox.loot_roll(pid2)
  end
end
