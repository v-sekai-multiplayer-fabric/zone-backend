# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.Iso8601Duration do
  @moduledoc """
  ISO 8601 duration parser, faithful Elixir port of `lean/Planner/Iso8601Duration.lean`.

  Conforms to ISO 8601-1:2019 §5.5.2.4: canonical order Y → Mo → D → T → H → Mi → S
  (each unit at most once), fractions allowed on at most one unit and
  only if no smaller unit follows, weeks must stand alone. UTC-elapsed
  normalisation (`Y = 365d`, `Mo = 30d`, `W = 7d`, `D = 86_400 s`);
  civil time is out of scope.

  This module exists so the Lean spec can be exercised with PropCheck
  against the Timex oracle and a strict spec recogniser. The C++ NIF
  port lives upstream in `taskweft-nif/standalone/tw_temporal.hpp` and
  must match this module's behaviour.
  """

  @type unit :: :y | :mo | :w | :d | :h | :mi | :s

  @type component :: %{unit: unit(), whole: non_neg_integer(), frac_milli: non_neg_integer()}

  @type error ::
          :empty
          | {:expected_p, String.t()}
          | :unexpected_end
          | {:invalid_number, String.t()}
          | {:date_after_t, unit()}
          | {:time_before_t, unit()}
          | :duplicate_t
          | :mixed_basic_extended
          | {:unexpected_token, String.t()}
          | {:non_canonical_order, unit()}
          | :fraction_not_on_last

  @units_date %{?Y => :y, ?M => :mo, ?W => :w, ?D => :d}
  @units_time %{?H => :h, ?M => :mi, ?S => :s}
  @cross_date_in_time %{?Y => :y, ?D => :d}
  @cross_time_in_date %{?H => :h, ?S => :s}

  @spec parse(String.t()) :: {:ok, [component()]} | {:error, error()}
  def parse(""), do: {:error, :empty}
  def parse("P"), do: {:ok, []}

  def parse(<<?P, rest::binary>>) do
    parse_components(rest, [], false, false, -1, false)
  end

  def parse(<<c::utf8, _::binary>>), do: {:error, {:expected_p, <<c::utf8>>}}

  @spec total_milliseconds([component()]) :: non_neg_integer()
  def total_milliseconds(components) do
    Enum.reduce(components, 0, fn c, acc ->
      base = c.whole * unit_milliseconds(c.unit)
      frac = c.frac_milli * div(unit_milliseconds(c.unit), 1000)
      acc + base + frac
    end)
  end

  @spec total_seconds([component()]) :: non_neg_integer()
  def total_seconds(components), do: div(total_milliseconds(components), 1000)

  defp unit_milliseconds(:y), do: 365 * 86_400 * 1000
  defp unit_milliseconds(:mo), do: 30 * 86_400 * 1000
  defp unit_milliseconds(:w), do: 7 * 86_400 * 1000
  defp unit_milliseconds(:d), do: 86_400 * 1000
  defp unit_milliseconds(:h), do: 3_600 * 1000
  defp unit_milliseconds(:mi), do: 60 * 1000
  defp unit_milliseconds(:s), do: 1000

  defp parse_components("", acc, _in_time, _saw_t, _last_rank, _frac_seen),
    do: {:ok, Enum.reverse(acc)}

  defp parse_components(_input, _acc, _in_time, _saw_t, _last_rank, true),
    do: {:error, :fraction_not_on_last}

  defp parse_components(<<?T, _rest::binary>>, _acc, _in_time, true, _last_rank, _frac),
    do: {:error, :duplicate_t}

  defp parse_components(<<?T>>, _acc, _in_time, _saw_t, _last_rank, _frac),
    do: {:error, :unexpected_end}

  defp parse_components(<<?T, rest::binary>>, acc, _in_time, false, _last_rank, _frac),
    do: parse_components(rest, acc, true, true, -1, false)

  defp parse_components(<<c::utf8, _::binary>> = input, acc, in_time, saw_t, last_rank, _frac)
       when c in ?0..?9 do
    case take_number(input) do
      {:error, _} = err ->
        err

      {:ok, _whole, _milli, raw, ""} ->
        {:error, {:invalid_number, raw}}

      {:ok, whole, milli, _raw, <<unit_c::utf8, rest::binary>>} ->
        cond do
          unit_c == ?W and (acc != [] or in_time) ->
            {:error, :mixed_basic_extended}

          Enum.any?(acc, &(&1.unit == :w)) ->
            {:error, :mixed_basic_extended}

          true ->
            classify_component(whole, milli, unit_c, rest, acc, in_time, saw_t, last_rank)
        end
    end
  end

  defp parse_components(<<c::utf8, _::binary>>, _acc, _in_time, _saw_t, _last_rank, _frac),
    do: {:error, {:unexpected_token, <<c::utf8>>}}

  defp classify_component(whole, milli, unit_c, rest, acc, in_time, saw_t, last_rank) do
    case lookup_unit(unit_c, in_time) do
      {:ok, unit} ->
        rank = unit_rank(unit)

        if rank <= last_rank do
          {:error, {:non_canonical_order, unit}}
        else
          comp = %{unit: unit, whole: whole, frac_milli: milli}
          parse_components(rest, [comp | acc], in_time, saw_t, rank, milli != 0)
        end

      {:cross, unit} ->
        if in_time do
          {:error, {:date_after_t, unit}}
        else
          {:error, {:time_before_t, unit}}
        end

      :unknown ->
        {:error, {:unexpected_token, <<unit_c::utf8>>}}
    end
  end

  defp unit_rank(:y), do: 0
  defp unit_rank(:mo), do: 1
  defp unit_rank(:d), do: 2
  defp unit_rank(:w), do: 99
  defp unit_rank(:h), do: 3
  defp unit_rank(:mi), do: 4
  defp unit_rank(:s), do: 5

  defp lookup_unit(c, false) do
    cond do
      Map.has_key?(@units_date, c) -> {:ok, Map.fetch!(@units_date, c)}
      Map.has_key?(@cross_time_in_date, c) -> {:cross, Map.fetch!(@cross_time_in_date, c)}
      true -> :unknown
    end
  end

  defp lookup_unit(c, true) do
    cond do
      Map.has_key?(@units_time, c) -> {:ok, Map.fetch!(@units_time, c)}
      Map.has_key?(@cross_date_in_time, c) -> {:cross, Map.fetch!(@cross_date_in_time, c)}
      true -> :unknown
    end
  end

  defp take_number(<<d::utf8, _::binary>> = input) when d in ?0..?9 do
    {whole, raw, after_int} = take_int(input, 0, "")

    case after_int do
      <<?., d2::utf8, _::binary>> = full when d2 in ?0..?9 ->
        <<?., frac::binary>> = full
        {milli, raw_with_frac, after_frac} = take_frac(frac, 0, 0, raw <> ".")
        {:ok, whole, milli, raw_with_frac, after_frac}

      <<?., _::binary>> ->
        {:error, {:invalid_number, raw <> "."}}

      _ ->
        {:ok, whole, 0, raw, after_int}
    end
  end

  defp take_number(_), do: {:error, :unexpected_end}

  defp take_int(<<d::utf8, rest::binary>>, acc, raw) when d in ?0..?9 do
    take_int(rest, acc * 10 + (d - ?0), raw <> <<d::utf8>>)
  end

  defp take_int(rest, acc, raw), do: {acc, raw, rest}

  defp take_frac(<<d::utf8, rest::binary>>, acc, n, raw) when d in ?0..?9 and n < 3 do
    take_frac(rest, acc * 10 + (d - ?0), n + 1, raw <> <<d::utf8>>)
  end

  defp take_frac(rest, acc, n, raw) do
    {acc * pow10(3 - n), raw, rest}
  end

  defp pow10(0), do: 1
  defp pow10(n), do: 10 * pow10(n - 1)
end
