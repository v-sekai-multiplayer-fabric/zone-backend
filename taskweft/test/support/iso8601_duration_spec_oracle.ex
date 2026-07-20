# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.Iso8601DurationSpecOracle do
  @moduledoc """
  Strict ISO 8601-1:2019 §5.5.2.4 duration recogniser. Used as a
  third-party oracle in cross-validation: our parser, Timex, and this
  module each give a yes/no, and the property test surfaces every
  three-way disagreement.

  The grammar implemented:

      duration   := "P" body
      body       := date_only | date "T" time | "T" time | weeks_only
      date       := [n "Y"] [n "M"] [n "D"]   (canonical order, each unit ≤1×)
      time       := [n "H"] [n "M"] [n "S"]   (canonical order, each unit ≤1×)
      weeks_only := n "W"
      n          := integer | integer "." digits | integer "," digits

  Spec rules enforced beyond the surface grammar:

    * `P` alone has no body and is rejected.
    * Fractions appear at most once in the entire duration, and must be
      on the lowest-order component actually present (so `PT1.5H30M`
      and `P1.5DT1H` are rejected; `PT1.5H` and `P1.5D` are accepted).
    * Weeks must stand alone — no other components, no `T`.

  Recognition only; arithmetic (Y → days, M → days, leap-second
  handling) is intentionally absent.
  """

  @type result :: :ok | {:error, atom()}

  @spec valid?(String.t()) :: boolean()
  def valid?(s), do: check(s) == :ok

  @spec check(String.t()) :: result()
  def check(""), do: {:error, :empty}
  def check("P"), do: {:error, :empty_body}
  def check(<<?P, rest::binary>>), do: check_body(rest)
  def check(_), do: {:error, :missing_p}

  defp check_body(<<?T, rest::binary>>) do
    case scan(rest, [?H, ?M, ?S]) do
      {:ok, [], _, _} -> {:error, :empty_time_section}
      {:ok, _, _, ""} -> :ok
      _ -> {:error, :trailing_or_malformed_time}
    end
  end

  defp check_body(rest) do
    case scan(rest, [?W]) do
      {:ok, [_], _frac, ""} ->
        :ok

      {:ok, [_], _frac, _trailing} ->
        {:error, :weeks_must_stand_alone}

      _ ->
        scan_date_then_optional_time(rest)
    end
  end

  defp scan_date_then_optional_time(rest) do
    case scan(rest, [?Y, ?M, ?D]) do
      {:ok, [], _frac, _} ->
        {:error, :empty_section}

      {:ok, _date_comps, date_frac, after_date} ->
        case after_date do
          "" ->
            :ok

          <<?T, time_rest::binary>> ->
            cond do
              date_frac ->
                {:error, :fraction_not_on_last}

              true ->
                case scan(time_rest, [?H, ?M, ?S]) do
                  {:ok, [], _frac, _} -> {:error, :empty_time_section}
                  {:ok, _, _frac, ""} -> :ok
                  _ -> {:error, :malformed_time}
                end
            end

          _ ->
            {:error, :unexpected_after_date}
        end

      err ->
        err
    end
  end

  # Walks `units` left-to-right, consuming optional `<number><unit>` pairs.
  # Returns {:ok, consumed_units, fraction_seen?, rest}. Enforces the
  # spec's "fraction allowed only on the last consumed component" rule
  # *within this section* by refusing to consume another component once
  # a fraction has been seen — the caller still has to check that no
  # additional section follows (e.g. fraction on date with `T` time after
  # is forbidden, handled by `scan_date_then_optional_time`).
  defp scan(input, units), do: do_scan(input, units, [], false)

  defp do_scan(rest, [], acc, frac), do: {:ok, Enum.reverse(acc), frac, rest}

  defp do_scan(rest, [_unit | _rest_units], acc, true) do
    case take_number(rest) do
      :no_digits -> {:ok, Enum.reverse(acc), true, rest}
      _ -> {:error, :fraction_not_on_last_in_section}
    end
  end

  defp do_scan(rest, [unit | rest_units], acc, false) do
    case take_number(rest) do
      :no_digits ->
        {:ok, Enum.reverse(acc), false, rest}

      {:error, _} = err ->
        err

      {:ok, _whole, has_frac, after_num} ->
        case after_num do
          <<^unit, after_unit::binary>> ->
            do_scan(after_unit, rest_units, [unit | acc], has_frac)

          <<other, _::binary>> ->
            if other in rest_units do
              do_scan(rest, rest_units, acc, false)
            else
              if acc == [] do
                {:error, :unexpected_unit}
              else
                {:ok, Enum.reverse(acc), false, rest}
              end
            end

          "" ->
            {:error, :missing_unit}
        end
    end
  end

  defp take_number(<<d, _::binary>> = input) when d in ?0..?9 do
    {whole, after_int} = read_digits(input, "")

    case after_int do
      <<sep, rest::binary>> when sep in [?., ?,] ->
        case read_digits(rest, "") do
          {"", _} -> {:error, :empty_fraction}
          {_, after_frac} -> {:ok, whole, true, after_frac}
        end

      _ ->
        {:ok, whole, false, after_int}
    end
  end

  defp take_number(_), do: :no_digits

  defp read_digits(<<d, rest::binary>>, acc) when d in ?0..?9,
    do: read_digits(rest, acc <> <<d>>)

  defp read_digits(rest, acc), do: {acc, rest}
end
