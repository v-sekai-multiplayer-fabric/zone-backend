# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Gyre.Domain do
  @moduledoc """
  The System.

  Builds a `Uro.Planner.ElixirAdapter` domain from a Spark's state and
  returns what it advises next. This is diegetic, not a UI affordance: the
  thing that digitised you and holds your debt is the same thing that
  helpfully suggests your next move.

  **The System is always helpful. Unfailingly. That is the joke.** It is
  never sarcastic, never withholding, never grim. It congratulates you on
  taking a contract that will cost 14% of your Frame. It is delighted to
  process a payment that leaves you with nothing. When your Frame is at
  8% and the only remaining option is to work anyway, it says so warmly,
  and it means it.

  The horror is never in the tone. It is in what the tone is applied to,
  and the player supplies that themselves. So `voice/2` below must stay
  cheerful in every branch -- a single dry or menacing line would break
  the bit and, worse, would do the player's thinking for them.

  The Gyre (rfd/0085) is already a planning problem: gig contracts against
  a debt clock, with preconditions on place, energy and credits. This maps
  it onto the loader schema the adapter expects -- `variables`, `actions`,
  `methods`, `todo_list`.

  Two constraints from the adapter shape this module. Values must be
  fixnums, booleans or atoms, because JSON strings are atomized, so places
  and contracts travel as bare names rather than structs. And `check`
  expressions are limited to `eq`/`lt`/`add`/`sub`/`not`/`and`/`or`/`get`,
  so every precondition below is written in those terms.

  Alternatives are ordered by preference, and the adapter returns the first
  whose `check` passes. That ordering is the recommendation.
  """

  alias Uro.Planner.ElixirAdapter

  @places %{
    "commons" => %{hub: true, exits: ["under_market", "decanting_floor"]},
    "under_market" => %{hub: true, exits: ["commons", "splicers_den"]},
    "decanting_floor" => %{hub: false, exits: ["commons"]},
    "splicers_den" => %{hub: false, exits: ["under_market"]}
  }

  @contracts %{
    "coolant" => %{site: "decanting_floor", pay: 180, wear: 6},
    "tanks" => %{site: "decanting_floor", pay: 240, wear: 9},
    "salvage" => %{site: "splicers_den", pay: 320, wear: 14},
    "courier" => %{site: "splicers_den", pay: 150, wear: 4}
  }

  @repair_cost 120

  @doc """
  Returns `{:ok, [%{command: c, says: line}, ...]}` — best first — or
  `{:error, reason}` when the state is unusable.

  The head of the list is what the palette ranks first, and `says` is how
  the System puts it.
  """
  @spec suggest(map()) :: {:ok, [%{command: String.t(), says: String.t()}]} | {:error, term()}
  def suggest(state) do
    with {:ok, s} <- normalize(state),
         {:ok, cmds} <- s |> build() |> Jason.encode!() |> ElixirAdapter.plan() |> decode_plan() do
      {:ok, Enum.map(cmds, &%{command: &1, says: voice(&1, s)})}
    end
  end

  @doc """
  How the System puts it. Cheerful in every branch, by design -- see the
  moduledoc. The parenthetical is where the cost goes, stated plainly and
  without comment, because the System sees nothing worth commenting on.
  """
  @spec voice(String.t(), map()) :: String.t()
  def voice("take " <> id, _s) do
    c = @contracts[id]
    "Great choice! #{c.pay} cr on completion. (Frame wear #{c.wear}%.)"
  end

  def voice("go " <> place, _s),
    do: "Off you go! #{title(place)} is expecting you. (Energy −1.)"

  def voice("work", %{contract: id, integrity: i}) when is_binary(id) do
    c = @contracts[id]

    if i - c.wear <= 0 do
      "You're so close! This will complete the contract. " <>
        "(Frame integrity #{i}%. Decant and re-Frame fee 1,200 cr.)"
    else
      "Nice work! Keep it up. (Frame integrity #{i}% → #{i - c.wear}%.)"
    end
  end

  def voice("deliver", %{contract: id}) when is_binary(id),
    do: "Contract complete — well done! (+#{@contracts[id].pay} cr credited.)"

  def voice("repair", _s),
    do: "Let's get you patched up! (−#{@repair_cost} cr. Frame integrity +25%.)"

  def voice("pay", %{credits: c}),
    do: "Wonderful! Every credit helps. (−#{c} cr from your balance.)"

  def voice("rest", _s),
    do: "Take a moment for yourself! (Energy +1. Debt continues to accrue.)"

  def voice(_other, _s), do: "Happy to help!"

  defp title(place), do: place |> String.replace("_", " ") |> String.capitalize()

  defp normalize(%{} = s) do
    place = to_string(s["place"] || s[:place] || "commons")

    if Map.has_key?(@places, place) do
      {:ok,
       %{
         place: place,
         contract: nilify(s["contract"] || s[:contract]),
         credits: int(s["credits"] || s[:credits], 0),
         integrity: int(s["integrity"] || s[:integrity], 100),
         energy: int(s["energy"] || s[:energy], 10)
       }}
    else
      {:error, {:unknown_place, place}}
    end
  end

  defp normalize(_), do: {:error, :bad_state}

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(v), do: if(Map.has_key?(@contracts, to_string(v)), do: to_string(v), else: nil)

  defp int(v, _d) when is_integer(v), do: v
  defp int(_, d), do: d

  @doc false
  def build(s) do
    %{
      "variables" => [
        %{
          "name" => "spark",
          "init" => %{
            "place" => s.place,
            "contract" => s.contract || "none",
            "at_hub" => @places[s.place].hub,
            "has_contract" => s.contract != nil,
            "at_site" => at_site?(s),
            "credits" => s.credits,
            "integrity" => s.integrity,
            "energy" => s.energy
          }
        }
      ],
      "actions" => actions(s),
      "methods" => %{"next" => %{"alternatives" => alternatives(s)}},
      "todo_list" => [["next"]]
    }
  end

  defp at_site?(%{contract: nil}), do: false
  defp at_site?(%{contract: c, place: p}), do: @contracts[c].site == p

  # Each action marks itself done, so the planner returns exactly one step
  # rather than looping. The palette wants a recommendation, not a
  # full schedule.
  defp actions(_s) do
    base = %{
      "work" => set("/spark/has_contract", false),
      "deliver" => set("/spark/has_contract", false),
      "repair" => set("/spark/integrity", 100),
      "pay" => set("/spark/credits", 0),
      "rest" => set("/spark/energy", 10)
    }

    takes =
      for {id, _} <- @contracts, into: %{} do
        {"take_" <> id, set("/spark/has_contract", true)}
      end

    goes =
      for {id, _} <- @places, into: %{} do
        {"go_" <> id, set("/spark/place", id)}
      end

    base |> Map.merge(takes) |> Map.merge(goes)
  end

  defp set(pointer, value), do: %{"body" => [%{"pointer/set" => pointer, "value" => value}]}

  # Preference order, best first. The adapter takes the first alternative
  # whose check passes, so this ordering *is* the recommendation.
  defp alternatives(s) do
    List.flatten([
      deliver_alt(s),
      work_alt(s),
      travel_alts(s),
      # Repair before taking new work: entering a contract damaged is how
      # you pay the 1,200 cr decant.
      repair_alt(s),
      # Credits sitting idle do nothing while the debt accrues each turn.
      pay_alt(s),
      take_alts(s),
      [%{"subtasks" => [["rest"]]}]
    ])
  end

  # Carrying a finished contract to a hub pays, so it outranks everything.
  defp deliver_alt(%{contract: nil}), do: []

  defp deliver_alt(s) do
    if @places[s.place].hub, do: [alt([get("/spark/has_contract")], "deliver")], else: []
  end

  defp work_alt(%{contract: nil}), do: []

  defp work_alt(s) do
    cond do
      not at_site?(s) ->
        []

      s.energy < 2 ->
        []

      # No integrity guard. The System's goal is the contract, and it will
      # cheerfully recommend working a Frame that this very action ends --
      # quoting the 1,200 cr decant fee in the same breath, as a courtesy.
      # Guarding here would make voice/2's dying-Frame branch unreachable
      # and would quietly do the player's thinking for them.
      true ->
        [alt([get("/spark/has_contract")], "work")]
    end
  end

  # Holding a contract elsewhere: move toward its site.
  defp travel_alts(%{contract: nil}), do: []

  defp travel_alts(s) do
    if at_site?(s) or s.energy < 1 do
      []
    else
      site = @contracts[s.contract].site
      step = if site in @places[s.place].exits, do: site, else: hd(@places[s.place].exits)
      [alt([get("/spark/has_contract")], "go_" <> step)]
    end
  end

  # No contract: take the best-paying one, at a hub.
  defp take_alts(s) do
    if s.contract == nil and @places[s.place].hub do
      @contracts
      |> Enum.sort_by(fn {_, c} -> -c.pay end)
      |> Enum.map(fn {id, _} -> alt([not_(get("/spark/has_contract"))], "take_" <> id) end)
    else
      []
    end
  end

  defp repair_alt(s) do
    if @places[s.place].hub and s.credits >= @repair_cost and s.integrity < 60 and
         s.contract == nil,
       do: [%{"subtasks" => [["repair"]]}],
       else: []
  end

  defp pay_alt(s), do: if(s.credits >= 300, do: [%{"subtasks" => [["pay"]]}], else: [])

  defp alt(check, task), do: %{"check" => check, "subtasks" => [[task]]}
  defp get(pointer), do: %{"eval" => %{"type" => "get", "pointer" => pointer}}
  defp not_(inner), do: %{"eval" => %{"type" => "not", "a" => inner["eval"]}}

  # The adapter returns JSON: a list of [action, args...] pairs.
  defp decode_plan(json) do
    case Jason.decode(json) do
      {:ok, steps} when is_list(steps) -> {:ok, Enum.map(steps, &command/1)}
      {:ok, other} -> {:error, {:unexpected_plan, other}}
      {:error, e} -> {:error, e}
    end
  end

  defp command([name | _]), do: to_command(to_string(name))
  defp command(name), do: to_command(to_string(name))

  defp to_command("take_" <> id), do: "take " <> id
  defp to_command("go_" <> id), do: "go " <> id
  defp to_command(other), do: other
end
