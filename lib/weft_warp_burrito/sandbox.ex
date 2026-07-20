# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule WeftWarpBurrito.Sandbox do
  @moduledoc """
  One actor per sandboxed libriscv Machine. This is the real security
  and concurrency boundary, not just an API convenience:

    - **Sandboxing**: each actor owns exactly one Machine, and every
      call it makes is one of three fixed, named guest capabilities
      (`:loot_roll`, `:combat_replay`, `:progression_replay`) - never a
      caller-supplied symbol name. Adding a capability means adding
      guest code and a NIF case by hand, never exposing a generic
      eval/vmcall-by-name entry point (see the NIF source's header for
      the full rationale - the same rule this session's Godot Sandbox
      port work already established and is not reopened here).
    - **Gas**: every call takes an explicit fuel budget
      (`@default_fuel` unless overridden) that libriscv itself enforces
      via `simulate_with` - a call either completes within budget or
      the NIF returns `{:error, :gas_exhausted}`.
    - **Pause**: a GenServer processes one capability call at a time
      (its mailbox already serializes access to the single underlying
      Machine - two concurrent calls into the same Machine would race
      on its CPU registers/stack pointer, so this isn't just style, it's
      required for correctness) and is fully idle - inspectable,
      restartable by its supervisor, free to receive other messages -
      between calls. There is no guest-side coroutine/yield support, so
      this is pause *between* gas-metered calls, not mid-instruction
      suspend/resume; see the NIF source's header comment for what a
      real mid-execution pause would additionally require.
  """
  use GenServer

  @default_fuel 20_000_000

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc "LootCore.roll against the fixed reference table (loot-roll(42, ...) = 3, Lean4-verified)."
  def loot_roll(pid, fuel \\ @default_fuel) do
    GenServer.call(pid, {:call_capability, :loot_roll, fuel})
  end

  @doc "CombatCore.replay against the fixed golden vector -> {:ok, {tick, hp, alive}}."
  def combat_replay(pid, fuel \\ @default_fuel) do
    GenServer.call(pid, {:call_capability, :combat_replay, fuel})
  end

  @doc "ProgressionCore.replay against the fixed golden vector -> {:ok, {credits, affinity}}."
  def progression_replay(pid, fuel \\ @default_fuel) do
    GenServer.call(pid, {:call_capability, :progression_replay, fuel})
  end

  ## GenServer callbacks

  @impl true
  def init(:ok) do
    elf_path = Path.join(:code.priv_dir(:weft_warp_burrito), "weft_guest.elf")

    case WeftWarpBurrito.SandboxNif.new_sandbox_nif(elf_path) do
      {:ok, resource} -> {:ok, %{resource: resource}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:call_capability, capability, fuel}, _from, state) do
    result = WeftWarpBurrito.SandboxNif.call_capability_nif(state.resource, capability, fuel)
    {:reply, result, state}
  end
end
