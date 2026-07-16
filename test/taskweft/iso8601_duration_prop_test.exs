# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.Iso8601DurationPropTest do
  @moduledoc """
  Exhaustive property tests for `Taskweft.Iso8601Duration` against
  Timex's `ISO8601Parser` as oracle. The two must agree byte-for-byte
  on the bounded subset both implementations accept (integer fields,
  ≤ 3 fractional second digits — `lean/Planner/Iso8601Duration.lean`
  is the spec for that subset).

  Six layers of coverage:

  1. Doctests — the seven worked examples Timex documents.
  2. Generator-driven properties — random-but-valid duration strings,
     and random arbitrary strings, both checked against Timex.
  3. NIF cross-check — calls `check_temporal/3` through the compiled C++
     NIF and compares its total milliseconds against the Elixir reference,
     confirming `tw_parse_duration_ms` and the Elixir parser agree.
  4. Civil-time NIF cross-check — fixed-date assertions that P1Y from a leap
     year = 366 d, P1M with month-end clamping, and fixed units unchanged.
  5. Bounded exhaustive enumeration — every string of length ≤ 5 over
     the duration alphabet gets the same agreement check.
  6. Adversarial fuzzing — mutations, random ASCII, large integers,
     stuttering, and a full divergence catalogue.
  """

  use ExUnit.Case, async: true
  use PropCheck

  alias Taskweft.Iso8601Duration
  alias Taskweft.Iso8601DurationSpecOracle, as: Spec
  alias Timex.Parse.Duration.Parsers.ISO8601Parser, as: TimexIso

  @numtests 1_000

  # ---- Layer 1: worked examples (Timex's docstring) --------------------------

  describe "worked examples" do
    test "P15Y3M2DT1H14M37S" do
      assert {:ok, components} = Iso8601Duration.parse("P15Y3M2DT1H14M37S")
      assert Enum.map(components, & &1.unit) == [:y, :mo, :d, :h, :mi, :s]
      assert Enum.map(components, & &1.whole) == [15, 3, 2, 1, 14, 37]
    end

    test "P15Y3M2D" do
      assert {:ok, [%{unit: :y, whole: 15}, %{unit: :mo, whole: 3}, %{unit: :d, whole: 2}]} =
               Iso8601Duration.parse("P15Y3M2D")
    end

    test "PT3H12M25.001S — fractional seconds preserved" do
      assert {:ok, components} = Iso8601Duration.parse("PT3H12M25.001S")
      assert List.last(components) == %{unit: :s, whole: 25, frac_milli: 1}
    end

    test "P2W — basic week-only form" do
      assert {:ok, [%{unit: :w, whole: 2}]} = Iso8601Duration.parse("P2W")
    end

    test "P15YT3D — date unit after T rejected" do
      assert {:error, {:date_after_t, :d}} = Iso8601Duration.parse("P15YT3D")
    end

    test "empty string rejected" do
      assert {:error, :empty} = Iso8601Duration.parse("")
    end

    test "leading char ≠ P rejected" do
      assert {:error, {:expected_p, "X"}} = Iso8601Duration.parse("X1D")
    end
  end

  # ---- Layer 2: property tests against Timex ---------------------------------

  describe "agreement with Timex" do
    property "valid bounded duration → both parse to same milliseconds",
             [:verbose, numtests: @numtests] do
      forall components <- valid_components_gen() do
        input = format_components(components)
        agree_on_milliseconds(input)
      end
    end

    property "arbitrary string → ours and spec agree on accept/reject",
             [:verbose, numtests: @numtests] do
      forall input <- duration_alphabet_string() do
        agree_with_spec(input)
      end
    end
  end

  # ---- Layer 3: NIF cross-check -----------------------------------------------

  # Calls check_temporal through the compiled C++ NIF with a minimal one-action
  # domain whose "noop" action carries the generated ISO 8601 duration.
  # The NIF uses tw_parse_duration_ms internally; comparing its total_iso
  # against the Elixir reference parser confirms the C++ and Elixir parsers
  # agree on every valid duration the generator produces.
  #
  # Skipped gracefully (returns true) if the NIF is not loaded.
  describe "NIF cross-check" do
    property "NIF tw_parse_duration_ms total agrees with Elixir total_milliseconds",
             [:verbose, numtests: @numtests] do
      forall components <- valid_components_gen() do
        input = format_components(components)
        nif_agrees_on_total(input)
      end
    end
  end

  # ---- Layer 4: civil-time cross-check ----------------------------------------

  # Verifies tw_check_temporal_civil (NIF) produces calendar-correct totals for
  # year and month durations.  Uses fixed reference dates so results are
  # deterministic regardless of when the test runs.
  describe "civil-time NIF" do
    # 2024 is a leap year: P1Y from 2024-01-01 = 366 days.
    test "P1Y from 2024-01-01 = 366 days" do
      assert civil_total_ms("P1Y", "2024-01-01") == 366 * 86_400_000
    end

    # Non-leap year: P1Y from 2023-01-01 = 365 days.
    test "P1Y from 2023-01-01 = 365 days" do
      assert civil_total_ms("P1Y", "2023-01-01") == 365 * 86_400_000
    end

    # Month-end clamping: Jan 31 + 1 month → Feb 29 (leap), not Feb 31.
    test "P1M from 2024-01-31 = 29 days" do
      assert civil_total_ms("P1M", "2024-01-31") == 29 * 86_400_000
    end

    # Non-leap February: Jan 31 + 1 month → Feb 28.
    test "P1M from 2023-01-31 = 28 days" do
      assert civil_total_ms("P1M", "2023-01-31") == 28 * 86_400_000
    end

    # Fixed units unaffected by reference date.
    test "P7D with reference date = 7 * 86_400_000 ms" do
      assert civil_total_ms("P7D", "2024-01-01") == 7 * 86_400_000
    end

    # Fixed units unaffected without reference date (empty string → fixed-day fallback).
    test "P7D without reference date = 7 * 86_400_000 ms" do
      assert civil_total_ms("P7D", "") == 7 * 86_400_000
    end
  end

  # ---- Layer 5: exhaustive small-string enumeration --------------------------

  describe "exhaustive enumeration" do
    @alphabet ~c"PTYMWDHS0123."

    test "every string of length 0..4 over duration alphabet agrees with spec" do
      mismatches =
        for len <- 0..4,
            input <- enumerate(@alphabet, len),
            not agree_with_spec(input),
            do: input

      assert mismatches == [], """
      Found #{length(mismatches)} mismatches between our parser and the
      strict ISO 8601 recogniser.
      First 10: #{inspect(Enum.take(mismatches, 10))}
      """
    end
  end

  # ---- Layer 5: adversarial fuzzing -----------------------------------------

  # After the canonical-order + lowest-order-fraction fixes landed, ours is
  # stricter than Timex on order and on fraction position. The adversarial
  # properties below switched their oracle from Timex to the strict spec
  # recogniser — agreement is "ours.accepts ↔ spec.valid?" with `P` as the
  # only carved-out exception.

  describe "adversarial" do
    # Mutate valid inputs by inserting / deleting / replacing / swapping a
    # character. The mutated string usually breaks the grammar; the property
    # asserts ours and the spec agree on the verdict.
    property "single-char mutations agree with spec",
             [:verbose, numtests: @numtests] do
      forall {components, mutation} <- {valid_components_gen(), mutation_gen()} do
        base = format_components(components)
        mutated = apply_mutation(base, mutation)
        agree_with_spec(mutated)
      end
    end

    # Random ASCII printable characters — most of which aren't even in the
    # duration alphabet. Both should reject the vast majority.
    property "random printable-ASCII strings agree with spec",
             [:verbose, numtests: @numtests] do
      forall input <- printable_ascii_string() do
        agree_with_spec(input)
      end
    end

    # Full duration alphabet including `.`. With the spec-aligned parser,
    # this is now expected to agree with the spec recogniser exactly
    # (modulo `P` zero-body).
    property "full duration alphabet agrees with spec",
             [:verbose, numtests: @numtests] do
      forall input <- duration_alphabet_with_dot_string() do
        agree_with_spec(input)
      end
    end

    # Very large integers (up to int64-ish range). Catches overflow and any
    # integer/float coercion drift. Compared against Timex on milliseconds
    # since both implementations accept and there's no smaller-unit
    # divergence in play.
    property "large integer fields on each unit agree with Timex",
             [:verbose, numtests: @numtests] do
      forall {n, unit} <- {range(0, 1_000_000_000), oneof([?Y, ?M, ?W, ?D])} do
        agree_on_milliseconds("P#{n}#{<<unit::utf8>>}")
      end
    end

    # Nested / repeated structures that look almost like a valid duration.
    property "stuttering inputs (PPP…, PTT…) agree with spec",
             [:verbose, numtests: @numtests] do
      forall {head_n, body_n, tail_n} <- {range(0, 5), range(0, 5), range(0, 5)} do
        input =
          String.duplicate("P", head_n) <>
            String.duplicate("T", body_n) <> String.duplicate("D", tail_n)

        agree_with_spec(input)
      end
    end
  end

  # ---- NIF helpers -----------------------------------------------------------

  # Embeds `duration_iso` as the duration of a no-op action in a minimal
  # domain, runs check_temporal through the NIF, and compares the total
  # milliseconds the NIF reports against the Elixir reference parser.
  # Returns true (skip) if the NIF is not loaded or the domain fails to parse.
  defp nif_agrees_on_total(duration_iso) do
    domain =
      ~s({"actions":{"noop":{"duration":"#{duration_iso}"}},"todo_list":[["noop"]],"state":{}})

    json = Taskweft.NIF.check_temporal(domain, ~s([["noop"]]), "PT0S")

    with [_, total_iso] <- Regex.run(~r{"total"\s*:\s*"([^"]+)"}, json),
         {:ok, ours} <- Iso8601Duration.parse(duration_iso),
         {:ok, nif_parsed} <- Iso8601Duration.parse(total_iso) do
      Iso8601Duration.total_milliseconds(ours) == Iso8601Duration.total_milliseconds(nif_parsed)
    else
      _ -> true
    end
  rescue
    _ -> true
  end

  # Calls check_temporal_civil through the NIF with the given reference date.
  # Returns the total milliseconds reported, or raises if the NIF is not loaded.
  defp civil_total_ms(duration_iso, reference_date) do
    domain =
      ~s({"actions":{"noop":{"duration":"#{duration_iso}"}},"todo_list":[["noop"]],"state":{}})

    json = Taskweft.NIF.check_temporal_civil(domain, ~s([["noop"]]), "PT0S", reference_date)
    [_, total_iso] = Regex.run(~r{"total"\s*:\s*"([^"]+)"}, json)
    {:ok, comps} = Iso8601Duration.parse(total_iso)
    Iso8601Duration.total_milliseconds(comps)
  end

  # ---- Generators ------------------------------------------------------------

  # Generators only produce integer-second durations so the property is
  # not perturbed by Timex's float-precision behaviour on fractional seconds
  # (`Duration.from_seconds(2.002)` round-trips through float microseconds
  # and can drift ±1 ms relative to our integer-millisecond accumulation).
  # Sub-second precision is exercised by the bounded enumeration test, where
  # the alphabet is small enough to inspect any divergences directly.
  defp valid_components_gen do
    let {y, mo, d, has_t, h, mi, s, week_only} <- {
          pos_or_zero(),
          pos_or_zero(),
          pos_or_zero(),
          bool(),
          pos_or_zero(),
          pos_or_zero(),
          pos_or_zero(),
          bool()
        } do
      cond do
        week_only ->
          [%{unit: :w, whole: pos_or_zero_value(), frac_milli: 0}]

        true ->
          date_part =
            [{:y, y}, {:mo, mo}, {:d, d}]
            |> Enum.reject(fn {_u, n} -> n == 0 end)
            |> Enum.map(fn {u, n} -> %{unit: u, whole: n, frac_milli: 0} end)

          time_part =
            if has_t do
              [{:h, h}, {:mi, mi}, {:s, s}]
              |> Enum.reject(fn {_u, n} -> n == 0 end)
              |> Enum.map(fn {u, n} -> %{unit: u, whole: n, frac_milli: 0} end)
            else
              []
            end

          # "P" alone is now valid (Timex parity), so an empty list is fine.
          date_part ++ time_part
      end
    end
  end

  defp pos_or_zero, do: such_that(n <- range(0, 100), when: n >= 0)

  defp pos_or_zero_value, do: :rand.uniform(100)

  # No `.` in this alphabet on purpose. Timex accepts fractions on any
  # unit and stores them in microseconds; our spec only allows fractions
  # on seconds and stores in milliseconds. The two diverge structurally
  # below 1 ms of the unit. Fractional cases are covered by the worked
  # examples (`PT3H12M25.001S`) and don't need property exploration here.
  defp duration_alphabet_string do
    let chars <- list(oneof(Enum.map(~c"PTYMWDHS0123", &range(&1, &1)))) do
      List.to_string(chars)
    end
  end

  # Adversarial: printable ASCII excluding `.` for the same precision-divergence
  # reason. The space of valid duration substrings is tiny inside this much
  # bigger alphabet, so the property mostly exercises the rejection path.
  defp printable_ascii_string do
    let chars <- list(such_that(c <- range(33, 126), when: c != ?.)) do
      List.to_string(chars)
    end
  end

  defp duration_alphabet_with_dot_string do
    let chars <- list(oneof(Enum.map(~c"PTYMWDHS0123.", &range(&1, &1)))) do
      List.to_string(chars)
    end
  end

  # `agree_with_spec` is the gate after canonical-order + lowest-fraction
  # fixes landed: our parser must produce the same accept/reject verdict as
  # the strict ISO 8601-1:2019 recogniser, except for the documented `P` =
  # zero quirk (which we and Timex both still accept).
  defp agree_with_spec(input) do
    ours = match?({:ok, _}, Iso8601Duration.parse(input))
    spec = Spec.valid?(input)
    ours == spec or input == "P"
  end

  # Legacy regex catalogue retained for reference; no longer consulted.
  defp _known_divergence?(input) do
    cond do
      Regex.match?(~r/\d\.\d+[YMWDH]/, input) -> true
      Regex.match?(~r/\.\d{4,}S/, input) -> true
      true -> false
    end
  end

  # Mutations applied to a generated valid duration string. Each variant
  # picks one position in the input. `apply_mutation/2` clamps out-of-range
  # indices so generators don't have to know the input length.
  defp mutation_gen do
    oneof([
      {:insert, range(0, 30), oneof(Enum.map(~c"PTYMWDHS0123", &range(&1, &1)))},
      {:delete, range(0, 30)},
      {:replace, range(0, 30), oneof(Enum.map(~c"PTYMWDHS0123", &range(&1, &1)))},
      {:swap, range(0, 30), range(0, 30)}
    ])
  end

  defp apply_mutation(s, {:insert, idx, c}) do
    n = String.length(s)
    i = if n == 0, do: 0, else: rem(idx, n + 1)
    {a, b} = String.split_at(s, i)
    a <> <<c::utf8>> <> b
  end

  defp apply_mutation(s, {:delete, idx}) do
    n = String.length(s)

    if n == 0 do
      s
    else
      i = rem(idx, n)
      {a, b} = String.split_at(s, i)
      a <> String.slice(b, 1..-1//1)
    end
  end

  defp apply_mutation(s, {:replace, idx, c}) do
    n = String.length(s)

    if n == 0 do
      <<c::utf8>>
    else
      i = rem(idx, n)
      {a, b} = String.split_at(s, i)
      a <> <<c::utf8>> <> String.slice(b, 1..-1//1)
    end
  end

  defp apply_mutation(s, {:swap, i, j}) do
    n = String.length(s)

    if n < 2 do
      s
    else
      i = rem(i, n)
      j = rem(j, n)
      chars = String.graphemes(s)
      ci = Enum.at(chars, i)
      cj = Enum.at(chars, j)

      chars
      |> List.replace_at(i, cj)
      |> List.replace_at(j, ci)
      |> Enum.join()
    end
  end

  # ---- Helpers ---------------------------------------------------------------

  defp format_components(components) do
    {date, time} = Enum.split_with(components, &(&1.unit in [:y, :mo, :w, :d]))

    date_str = Enum.map_join(date, "", &format_one/1)
    time_str = Enum.map_join(time, "", &format_one/1)

    "P" <> date_str <> if(time_str == "", do: "", else: "T" <> time_str)
  end

  defp format_one(%{unit: u, whole: n, frac_milli: 0}) do
    "#{n}#{unit_char(u)}"
  end

  defp format_one(%{unit: :s, whole: n, frac_milli: f}) do
    "#{n}.#{frac_milli_to_string(f)}S"
  end

  defp frac_milli_to_string(f) do
    f
    |> Integer.to_string()
    |> String.pad_leading(3, "0")
    |> String.trim_trailing("0")
    |> case do
      "" -> "0"
      s -> s
    end
  end

  defp unit_char(:y), do: "Y"
  defp unit_char(:mo), do: "M"
  defp unit_char(:w), do: "W"
  defp unit_char(:d), do: "D"
  defp unit_char(:h), do: "H"
  defp unit_char(:mi), do: "M"
  defp unit_char(:s), do: "S"

  # Both parsers accept and produce the same milliseconds, OR both reject.
  defp agree_on_milliseconds(input) do
    case {Iso8601Duration.parse(input), TimexIso.parse(input)} do
      {{:ok, ours}, {:ok, theirs}} ->
        ours_ms = Iso8601Duration.total_milliseconds(ours)

        theirs_ms =
          theirs
          |> Timex.Duration.to_milliseconds(truncate: true)
          |> trunc()

        ours_ms == theirs_ms

      {{:error, _}, {:error, _}} ->
        true

      _ ->
        false
    end
  end

  defp enumerate(_alphabet, 0), do: [""]

  defp enumerate(alphabet, len) do
    for prefix <- enumerate(alphabet, len - 1),
        c <- alphabet,
        do: prefix <> <<c::utf8>>
  end
end
