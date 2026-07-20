# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Uro.VSekai.EntityPlanner do
  @moduledoc """
  Thin wrapper around `Uro.Planner.plan/1`.

  Takes a JSON-LD domain string and an optional state override map, returns
  the plan as a JSON string. The planner is domain-agnostic — it knows nothing
  about species, entities, or files. Callers supply the domain.

  ## Example

      domain = File.read!("priv/domains/jellyfish_common.jsonld")
      {:ok, plan} = EntityPlanner.plan(domain, %{"threat_nearby" => true})
  """

  @type state_override :: %{String.t() => term()}

  @spec plan(String.t(), state_override()) :: {:ok, String.t()} | {:error, term()}
  def plan(domain_json, state \\ %{}) when is_binary(domain_json) do
    input = apply_state(domain_json, state)

    case Uro.Planner.plan(input) do
      result when is_binary(result) -> {:ok, result}
      other -> {:error, {:planner_error, other}}
    end
  end

  defp apply_state(domain_json, overrides) when map_size(overrides) == 0, do: domain_json

  defp apply_state(domain_json, overrides) do
    domain = Jason.decode!(domain_json)
    Jason.encode!(put_in(domain, ["state"], Map.merge(domain["state"] || %{}, overrides)))
  end
end
