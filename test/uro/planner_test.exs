# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Uro.VSekai.EntityPlannerTest do
  use ExUnit.Case, async: true

  import Mox

  alias Uro.VSekai.EntityPlanner

  setup :verify_on_exit!

  setup do
    Application.put_env(:uro, :planner_adapter, Uro.PlannerMock)
    on_exit(fn -> Application.put_env(:uro, :planner_adapter, Uro.Planner.SandboxAdapter) end)
    :ok
  end

  describe "plan/2" do
    test "returns {:ok, plan} when the adapter returns a plan string" do
      Uro.PlannerMock
      |> expect(:plan, fn domain_json ->
        assert Jason.decode!(domain_json) |> Map.has_key?("state")
        ~s({"steps":["a_pickup"]})
      end)

      assert {:ok, ~s({"steps":["a_pickup"]})} =
               EntityPlanner.plan(~s({"state":{}}), %{"threat_nearby" => true})
    end

    test "passes the domain through unchanged when no state overrides are given" do
      Uro.PlannerMock
      |> expect(:plan, fn domain_json ->
        assert domain_json == ~s({"state":{}})
        ~s({"steps":[]})
      end)

      assert {:ok, ~s({"steps":[]})} = EntityPlanner.plan(~s({"state":{}}))
    end

    test "returns {:error, {:planner_error, _}} when the adapter doesn't return a binary" do
      Uro.PlannerMock |> expect(:plan, fn _domain_json -> {:error, :nif_not_loaded} end)

      assert {:error, {:planner_error, {:error, :nif_not_loaded}}} =
               EntityPlanner.plan(~s({"state":{}}))
    end
  end
end
