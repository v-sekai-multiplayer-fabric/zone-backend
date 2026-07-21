# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.LoopCore.ProgressionCore do
  @moduledoc """
  Hand-ported from `v-sekai-multiplayer-fabric/progression`'s Lean core
  (via `c_src/guest/content/progression.scm`'s own translation) into
  plain, idiomatic Elixir -- see `Uro.LoopCore.LootCore`'s moduledoc for
  why this runs as ordinary Elixir rather than through the RISC-V
  sandbox. `items` is a list of `{item, count}` pairs, matching the
  Scheme source's association-list shape (kept rather than switched to
  a map, so the translation stays line-for-line checkable against the
  Lean-verified original).
  """

  defmodule Profile do
    @moduledoc false
    defstruct credits: 200, affinity: 15, items: [], arts: []
  end

  @doc "The starting profile progression-replay/a fresh instance uses."
  def initial_profile, do: %Profile{}

  defp art_cost(1), do: 100
  defp art_cost(2), do: 250
  defp art_cost(_), do: 500

  defp art_affinity_req(1), do: 10
  defp art_affinity_req(2), do: 25
  defp art_affinity_req(_), do: 40

  # ProgressionCore.countOf
  defp count_of(%Profile{items: items}, item) do
    case List.keyfind(items, item, 0) do
      {_item, count} -> count
      nil -> 0
    end
  end

  # ProgressionCore.addItem
  defp add_item(%Profile{items: items} = p, item, d) do
    if List.keyfind(items, item, 0) do
      new_items =
        Enum.map(items, fn {i, count} -> if i == item, do: {i, count + d}, else: {i, count} end)

      %Profile{p | items: new_items}
    else
      %Profile{p | items: items ++ [{item, d}]}
    end
  end

  # ProgressionCore.removeItem
  defp remove_item(%Profile{items: items} = p, item) do
    new_items =
      items
      |> Enum.map(fn {i, count} -> if i == item, do: {i, count - 1}, else: {i, count} end)
      |> Enum.filter(fn {_i, count} -> count > 0 end)

    %Profile{p | items: new_items}
  end

  # ProgressionCore.step -- events: {:grant, item}, {:sell, item, price},
  # {:buy_art, art}, or the bare atom :train.
  @doc "progression-step(profile, event)."
  def step(%Profile{} = p, {:grant, item}), do: {add_item(p, item, 1), [{:granted, item}]}

  def step(%Profile{} = p, {:sell, item, price}) do
    if count_of(p, item) == 0 do
      {p, [{:refused_no_item, item}]}
    else
      p2 = %Profile{p | credits: p.credits + price}
      {remove_item(p2, item), [{:sold, item, price}]}
    end
  end

  def step(%Profile{} = p, {:buy_art, art}) do
    cond do
      art in p.arts ->
        {p, [{:refused_dup, art}]}

      p.affinity < art_affinity_req(art) ->
        {p, [{:refused_gate, art}]}

      p.credits < art_cost(art) ->
        {p, [{:refused_poor, art}]}

      true ->
        {%Profile{p | credits: p.credits - art_cost(art), arts: p.arts ++ [art]},
         [{:learned, art}]}
    end
  end

  def step(%Profile{} = p, :train) do
    a = p.affinity + 1
    {%Profile{p | affinity: a}, [{:trained, a}]}
  end

  def step(%Profile{} = p, _event), do: {p, []}

  @doc """
  progression-replay(events) -- golden vector: grant(1), grant(1),
  sell(1,50), train, buyArt(1) -> credits=150, affinity=16.
  """
  @spec replay([term()]) :: {Profile.t(), [term()]}
  def replay(events) do
    Enum.reduce(events, {initial_profile(), []}, fn event, {profile, log} ->
      {new_profile, new_log} = step(profile, event)
      {new_profile, log ++ new_log}
    end)
  end
end
