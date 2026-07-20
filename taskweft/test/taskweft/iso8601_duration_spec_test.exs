# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.Iso8601DurationSpecTest do
  @moduledoc """
  Three-way cross-validation between

    * `Taskweft.Iso8601Duration` — our Lean-spec'd parser
    * `Timex.Parse.Duration.Parsers.ISO8601Parser` — Timex's parser
    * `Taskweft.Iso8601DurationSpecOracle` — strict ISO 8601-1:2019

  This is a *findings catalogue*, not a passing-gate. Each entry asserts
  the verdict triplet on a known input. Adding a new disagreement
  requires adding a new test here — the act of cataloguing is the
  evidence that we've considered it.

  Headline findings, after the canonical-order + lowest-order-fraction
  fixes landed:

    * Our parser now matches the spec on canonical order — `P1D1M` is
      rejected. Timex remains loose here.
    * Our parser now matches the spec on fraction position — fractions
      are allowed on the lowest-order present component (`P1.5D`,
      `PT1.5H`). Timex is looser still: it accepts `PT1.5H30M` even
      though the spec rejects it.
    * `P` alone remains a documented quirk — we and Timex accept it
      as zero; the spec rejects (no body).

  The property at the bottom enforces the one remaining invariant
  worth gating on: every input our parser accepts is either spec-valid
  or in the documented exception set.
  """

  use ExUnit.Case, async: true
  use PropCheck

  alias Taskweft.Iso8601Duration
  alias Taskweft.Iso8601DurationSpecOracle, as: Spec
  alias Timex.Parse.Duration.Parsers.ISO8601Parser, as: TimexIso

  @numtests 1_000

  # Each tuple: {input, ours_accepts?, timex_accepts?, spec_accepts?}.
  # Order: spec-canonical first, then known divergences.
  @three_way_cases [
    # All three accept
    {"P1Y", true, true, true},
    {"P1M", true, true, true},
    {"P1D", true, true, true},
    {"P1W", true, true, true},
    {"PT1H", true, true, true},
    {"PT1M", true, true, true},
    {"PT1S", true, true, true},
    {"P1Y2M3D", true, true, true},
    {"PT4H5M6S", true, true, true},
    {"P1Y2M3DT4H5M6S", true, true, true},
    {"PT1.5S", true, true, true},

    # All three reject
    {"", false, false, false},
    {"PT", false, false, false},
    {"P1Y1W", false, false, false},
    {"X1D", false, false, false},

    # Spec-compliant fractions on lowest-order present component
    {"P1.5D", true, true, true},
    {"P1.5W", true, true, true},
    {"PT1.5H", true, true, true},
    {"PT1.5M", true, true, true},

    # Canonical order: ours rejects (matches spec); Timex still accepts
    {"P1D1M", false, true, false},

    # Timex looser than spec on fraction position; ours and spec reject
    {"PT1.5H30M", false, true, false},
    {"P1.5DT1H", false, true, false},
    {"PT1.5H1.5M", false, true, false},

    # All-zero fraction digits still count as "a fraction is present" —
    # a fraction of exactly zero on a non-last component is still a
    # fraction on a non-last component. Regression: our parser used to
    # gate the "fraction seen" flag on frac_milli != 0, so ".0" (whose
    # numeric value is zero) slipped past undetected.
    {"P0.0Y0M", false, true, false},

    # `P` alone — we and Timex accept (zero), spec rejects (no body)
    {"P", true, true, false}
  ]

  describe "three-way cross-validation catalogue" do
    for {input, ours_expected, timex_expected, spec_expected} <- @three_way_cases do
      test "#{input}" do
        ours = match?({:ok, _}, Iso8601Duration.parse(unquote(input)))
        timex = match?({:ok, _}, TimexIso.parse(unquote(input)))
        spec = Spec.valid?(unquote(input))

        assert {ours, timex, spec} ==
                 {unquote(ours_expected), unquote(timex_expected), unquote(spec_expected)}
      end
    end
  end

  describe "soft invariant: ours accepts ⇒ spec accepts ∨ documented exception" do
    @exceptions ~w(P)

    property "every accepted input is either spec-valid or a known exception",
             [:verbose, numtests: @numtests] do
      forall input <- duration_alphabet_with_dot_string() do
        case Iso8601Duration.parse(input) do
          {:ok, _} -> Spec.valid?(input) or input in @exceptions
          {:error, _} -> true
        end
      end
    end
  end

  defp duration_alphabet_with_dot_string do
    let chars <- list(oneof(Enum.map(~c"PTYMWDHS0123.", &range(&1, &1)))) do
      List.to_string(chars)
    end
  end
end
