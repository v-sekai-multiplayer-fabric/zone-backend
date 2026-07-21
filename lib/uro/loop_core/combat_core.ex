# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.LoopCore.CombatCore do
  @moduledoc """
  Hand-ported from `v-sekai-multiplayer-fabric/combat`'s Lean core (via
  `c_src/guest/content/combat.scm`'s own translation) into plain,
  idiomatic Elixir -- see `Uro.LoopCore.LootCore`'s moduledoc for why
  this runs as ordinary Elixir rather than through the RISC-V sandbox.
  Elixir's struct-update syntax (`%State{s | hp: 0}`) replaces
  `record-macros.scm`'s `record-with` macro natively -- no macro
  library needed.
  """

  @combo_min_gap 6
  @combo_max_gap 18
  @invuln_ticks 30
  @enemy_max_hp 100

  defmodule State do
    @moduledoc false
    defstruct tick: 0, combo: 0, last_attack: 0, hp: 0, spawn: 0, alive: false
  end

  @doc "The zero state combat-replay/a fresh instance starts from."
  def initial_state, do: %State{}

  defp damage_of(0), do: 10
  defp damage_of(1), do: 15
  defp damage_of(_), do: 25

  # CombatCore.resolveSwing
  defp resolve_swing(%State{alive: false} = s, stage), do: {s, [{:swing, stage}]}

  defp resolve_swing(%State{} = s, stage) when s.tick < s.spawn + @invuln_ticks,
    do: {s, [{:swing, stage}, :blocked]}

  defp resolve_swing(%State{} = s, stage) do
    dmg = damage_of(stage)

    if s.hp <= dmg do
      {%State{s | hp: 0, alive: false}, [{:swing, stage}, {:hit, dmg}, :death]}
    else
      {%State{s | hp: s.hp - dmg}, [{:swing, stage}, {:hit, dmg}]}
    end
  end

  # CombatCore.step
  @doc "combat-step(state, event) -- event :: :tick | :spawn | :attack."
  def step(%State{} = s, :tick) do
    s1 = %State{s | tick: s.tick + 1}

    if s1.combo > 0 and s1.tick > s1.last_attack + @combo_max_gap do
      {%State{s1 | combo: 0}, [:combo_drop]}
    else
      {s1, []}
    end
  end

  def step(%State{} = s, :spawn),
    do: {%State{s | alive: true, hp: @enemy_max_hp, spawn: s.tick}, []}

  def step(%State{combo: 0} = s, :attack),
    do: resolve_swing(%State{s | combo: 1, last_attack: s.tick}, 0)

  def step(%State{} = s, :attack) do
    gap = s.tick - s.last_attack

    if @combo_min_gap <= gap and gap <= @combo_max_gap do
      stage = s.combo
      next = if stage >= 2, do: 0, else: stage + 1
      resolve_swing(%State{s | combo: next, last_attack: s.tick}, stage)
    else
      {%State{s | combo: 0}, [:whiff]}
    end
  end

  def step(%State{} = s, _event), do: {s, []}

  @doc """
  combat-replay(events) -- golden vector: spawn, 30 ticks, one opener
  attack -> tick=30, hp=90, alive=true.
  """
  @spec replay([:tick | :spawn | :attack]) :: {State.t(), [term()]}
  def replay(events) do
    Enum.reduce(events, {initial_state(), []}, fn event, {state, log} ->
      {new_state, new_log} = step(state, event)
      {new_state, log ++ new_log}
    end)
  end
end
