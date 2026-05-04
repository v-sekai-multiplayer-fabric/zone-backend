# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.Iso8601Duration do
  @moduledoc """
  ISO 8601 duration parser, faithful Elixir port of `lean/Planner/Iso8601Duration.lean`.

  Mirrors `Timex.Parse.Duration.Parsers.ISO8601Parser` byte-for-byte:
  same grammar, same error tags, same UTC-elapsed normalisation
  (`Y = 365d`, `Mo = 30d`, `W = 7d`, `D = 86_400 s`). Civil time is
  out of scope on purpose.

  This module exists so the Lean spec can be exercised with PropCheck
  against the Timex oracle. The eventual C++ NIF port lives upstream
  in `taskweft-nif/standalone/tw_temporal.hpp`.
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

  @units_date %{?Y => :y, ?M => :mo, ?W => :w, ?D => :d}
  @units_time %{?H => :h, ?M => :mi, ?S => :s}
  @cross_date_in_time %{?Y => :y, ?D => :d}
  @cross_time_in_date %{?H => :h, ?S => :s}

  @spec parse(String.t()) :: {:ok, [component()]} | {:error, error()}
  def parse(""), do: {:error, :empty}
  def parse("P"), do: {:ok, []}

  def parse(<<?P, rest::binary>>) do
    with {:ok, components} <- parse_components(rest, [], false, false),
         :ok <- check_basic_form(components) do
      {:ok, components}
    end
  end

  def parse(<<c::utf8, _::binary>>), do: {:error, {:expected_p, <<c::utf8>>}}

  @spec total_milliseconds([component()]) :: non_neg_integer()
  def total_milliseconds(components) do
    Enum.reduce(components, 0, fn c, acc ->
      acc + c.whole * unit_milliseconds(c.unit) + c.frac_milli
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

  defp parse_components("", acc, _in_time, _saw_t), do: {:ok, Enum.reverse(acc)}

  defp parse_components(<<?T, _rest::binary>>, _acc, _in_time, true),
    do: {:error, :duplicate_t}

  defp parse_components(<<?T>>, _acc, _in_time, _saw_t),
    do: {:error, :unexpected_end}

  defp parse_components(<<?T, rest::binary>>, acc, _in_time, false),
    do: parse_components(rest, acc, true, true)

  defp parse_components(<<c::utf8, _::binary>> = input, acc, in_time, saw_t)
       when c in ?0..?9 do
    case take_number(input) do
      {:error, _} = err ->
        err

      {:ok, _whole, _milli, raw, ""} ->
        {:error, {:invalid_number, raw}}

      {:ok, whole, milli, raw, <<unit_c::utf8, rest::binary>>} ->
        cond do
          unit_c == ?W and (acc != [] or in_time) ->
            {:error, :mixed_basic_extended}

          true ->
            classify_component(whole, milli, raw, unit_c, rest, acc, in_time, saw_t)
        end
    end
  end

  defp parse_components(<<c::utf8, _::binary>>, _acc, _in_time, _saw_t),
    do: {:error, {:unexpected_token, <<c::utf8>>}}

  defp classify_component(whole, milli, raw, unit_c, rest, acc, in_time, saw_t) do
    case lookup_unit(unit_c, in_time) do
      {:ok, unit} ->
        if unit != :s and milli != 0 do
          {:error, {:invalid_number, raw}}
        else
          comp = %{unit: unit, whole: whole, frac_milli: milli}
          parse_components(rest, [comp | acc], in_time, saw_t)
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
      <<?., frac::binary>> ->
        {milli, raw_with_frac, after_frac} = take_frac(frac, 0, 0, raw <> ".")
        {:ok, whole, milli, raw_with_frac, after_frac}

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

  defp check_basic_form(components) do
    has_w = Enum.any?(components, &(&1.unit == :w))

    cond do
      has_w and length(components) > 1 -> {:error, :mixed_basic_extended}
      true -> :ok
    end
  end
end
