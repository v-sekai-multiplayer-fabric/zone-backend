# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.JSONLD.LoaderTest do
  @moduledoc """
  Validation coverage for the goal (RECTGTN 'T') and multigoal ('N') task
  kinds. The bundled problem suite exercised only `TwCall` tasks, so a drift in
  the MCP-facing JSON-LD shape for goals/multigoals would not have surfaced
  (taskweft #52). These tests pin the shapes `Loader.validate/2` accepts and,
  through the NIF, assert the multigoal fixture plans soundly.
  """
  use ExUnit.Case, async: true

  alias Taskweft.JSONLD.Loader

  defp base(extra),
    do: Map.merge(%{"@type" => "domain:Problem", "name" => "t"}, extra)

  describe "validate/2 goal bindings (array form)" do
    test "accepts a domain:Problem with a goals binding array" do
      doc =
        base(%{
          "variables" => [%{"name" => "pos", "init" => %{"a" => "b"}}],
          "goals" => [%{"pointer" => "/pos/a", "eq" => "table"}]
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts the domain-style goals object (goal methods)" do
      doc =
        base(%{
          "@type" => "domain:Definition",
          "goals" => %{
            "pos" => %{"params" => ["block", "dest"], "alternatives" => [%{"name" => "m"}]}
          }
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects a goal binding missing eq" do
      doc = base(%{"goals" => [%{"pointer" => "/pos/a"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ ~s(goals[0])
      assert msg =~ "eq"
    end

    test "rejects a goal binding missing pointer" do
      doc = base(%{"goals" => [%{"eq" => "table"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "pointer"
    end

    test "rejects a non-string pointer" do
      doc = base(%{"goals" => [%{"pointer" => 5, "eq" => "table"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "pointer"
    end

    test "rejects a non-object binding" do
      doc = base(%{"goals" => ["/pos/a"]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "expected object"
    end
  end

  describe "validate/2 multigoal tasks" do
    test "accepts a {multigoal} task entry" do
      doc = base(%{"tasks" => [%{"multigoal" => %{"pos" => %{"a" => "table", "b" => "a"}}}]})
      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts a call array and a multigoal task in the same list" do
      doc =
        base(%{
          "tasks" => [["move_one", "a", "table"], %{"multigoal" => %{"pos" => %{"c" => "b"}}}]
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects an empty multigoal" do
      doc = base(%{"tasks" => [%{"multigoal" => %{}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "at least one variable"
    end

    test "rejects a multigoal var whose bindings are empty" do
      doc = base(%{"tasks" => [%{"multigoal" => %{"pos" => %{}}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "at least one key"
    end

    test "rejects a multigoal var bound to a non-object" do
      doc = base(%{"tasks" => [%{"multigoal" => %{"pos" => "table"}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "key→desired"
    end

    test "rejects a multigoal whose value is not an object" do
      doc = base(%{"tasks" => [%{"multigoal" => "pos"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ ~s("multigoal" must be an object)
    end

    test "rejects an object task that is not a multigoal" do
      doc = base(%{"tasks" => [%{"goal" => %{}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "multigoal"
    end
  end

  describe "validate/2 @type" do
    test "accepts the new domain:Problem type" do
      assert :ok = Loader.validate(base(%{}), %{})
    end
  end

  describe "load_string end-to-end (context resolution + validate)" do
    test "a multigoal problem document round-trips" do
      json = ~s({
        "@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/", "domain": "khr:planning/domain/"},
        "@type": "domain:Problem",
        "name": "switch_multigoal",
        "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
        "tasks": [{"multigoal": {"switch": {"x": true, "y": true}}}]
      })

      assert {:ok, _compact} = Loader.load_string(json)
    end

    test "a goal-binding problem document round-trips" do
      json = ~s({
        "@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/", "domain": "khr:planning/domain/"},
        "@type": "domain:Problem",
        "name": "switch_goal",
        "variables": [{"name": "switch", "init": {"x": false}}],
        "goals": [{"pointer": "/switch/x", "eq": true}]
      })

      assert {:ok, _compact} = Loader.load_string(json)
    end
  end

  # A self-contained multigoal domain in the `check`/`set` action shape the
  # pinned NIF executes, so this test does not depend on the bundled fixtures
  # (whose domains have since migrated to the newer `pointer/set` node shape
  # that the pinned NIF cannot run). It drives the RECTGTN 'N' branch:
  # TwMultiGoal splits into one TwGoal per binding, each dispatched to the
  # `switch` goal method. The bundled taskweft-plans fixture covers the harder
  # blocks_world backjump; this proves the shape plans and replays soundly.
  #
  # Exercises the compiled NIF: green in CI (which builds taskweft_nif from
  # source). A stale bundled DLL returns "no_plan", as the existing CLI
  # planner tests already do.
  @multigoal_domain ~s({
    "@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/", "domain": "khr:planning/domain/"},
    "@type": "domain:Definition",
    "name": "switches_multigoal",
    "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
    "actions": {
      "flip_on": {"params": ["s"], "body": [
        {"check": "/switch/{s}", "eq": false},
        {"set": "/switch/{s}", "value": true}
      ]}
    },
    "goals": {
      "switch": {"params": ["s", "val"], "alternatives": [
        {"name": "turn_on", "subtasks": [["flip_on", "{s}"]]}
      ]}
    },
    "tasks": [{"multigoal": {"switch": {"x": true, "y": true}}}]
  })

  describe "multigoal plans soundly through the NIF" do
    test "replan reports every step completed and no failure" do
      plan_json = Taskweft.NIF.plan(@multigoal_domain)
      steps = Jason.decode!(plan_json)
      assert length(steps) == 2

      assert {:ok, out} = Taskweft.replan(@multigoal_domain, plan_json, -1)
      env = Jason.decode!(out)
      assert env["fail_step"] == -1
      assert env["completed_steps"] == length(steps)
    end
  end
end
