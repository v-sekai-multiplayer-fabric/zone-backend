# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.GyreDomainTest do
  @moduledoc """
  The System's advice, through the real `Uro.Planner.ElixirAdapter`.

  These pin behaviour, not implementation: each case asserts the command a
  creditor would give, so a change in the preference order fails here
  rather than silently changing what the game tells you to do.
  """
  use ExUnit.Case, async: true

  alias Uro.Gyre.Domain

  defp advice(state) do
    {:ok, [%{command: c} | _]} = Domain.suggest(state)
    c
  end

  defp says(state) do
    {:ok, [%{says: v} | _]} = Domain.suggest(state)
    v
  end

  defp spark(overrides) do
    Map.merge(
      %{
        "place" => "commons",
        "contract" => nil,
        "credits" => 60,
        "integrity" => 100,
        "energy" => 10
      },
      overrides
    )
  end

  test "with nothing in hand, it sends you to the best-paying contract" do
    assert "take salvage" = advice(spark(%{}))
  end

  test "carrying a finished contract at a hub, it wants the delivery" do
    assert "deliver" = advice(spark(%{"place" => "under_market", "contract" => "salvage"}))
  end

  test "on the contract's site, it wants the work" do
    assert "work" = advice(spark(%{"place" => "splicers_den", "contract" => "salvage"}))
  end

  # From a field site with the contract's work elsewhere, the System routes
  # you. Decanting Floor exits only to the Commons, so that is the first
  # step toward Splicer's Den, not a direct hop.
  test "in a field with the contract elsewhere, it routes you a step at a time" do
    st = spark(%{"place" => "decanting_floor", "contract" => "salvage", "credits" => 0})
    assert "go commons" = advice(st)
    assert says(st) =~ "Commons"
  end

  # The System is always helpful, so it never withholds the option that
  # completes the contract -- even the one that ends the Frame doing it.
  test "on site with a dying Frame, it still recommends the work" do
    st = spark(%{"place" => "splicers_den", "contract" => "salvage", "integrity" => 12})
    assert "work" = advice(st)
    assert says(st) =~ "You're so close!"
    assert says(st) =~ "1,200 cr"
  end

  test "the voice stays cheerful even when the news is bad" do
    st = spark(%{"place" => "splicers_den", "contract" => "salvage", "integrity" => 12})
    line = says(st)
    refute line =~ ~r/warning|danger|careful|risk|caution/i
    assert line =~ ~r/^You're so close!/
  end

  test "damaged and liquid at a hub, it repairs before taking new work" do
    assert "repair" =
             advice(spark(%{"place" => "under_market", "integrity" => 20, "credits" => 300}))
  end

  # Idle credits earn it nothing while the debt accrues, so it collects.
  test "liquid with no contract, it collects rather than sending you out" do
    assert "pay" = advice(spark(%{"credits" => 900}))
  end

  test "an unknown place is refused rather than guessed" do
    assert {:error, {:unknown_place, "nowhere"}} = Domain.suggest(spark(%{"place" => "nowhere"}))
  end
end
