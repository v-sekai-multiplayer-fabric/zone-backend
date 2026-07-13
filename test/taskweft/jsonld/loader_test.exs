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

  @plans :code.priv_dir(:taskweft_plans) |> Path.join("plans")

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

  describe "bundled fixtures round-trip through the loader" do
    test "blocks_world_goal problem file validates" do
      path = Path.join([@plans, "problems", "blocks_world_goal.jsonld"])
      assert {:ok, _json} = Loader.load_file(path)
    end

    test "blocks_world_multigoal problem file validates" do
      path = Path.join([@plans, "problems", "blocks_world_multigoal.jsonld"])
      assert {:ok, _json} = Loader.load_file(path)
    end
  end

  # Drives the RECTGTN 'N' branch through the compiled NIF against the bundled
  # blocks_world_multigoal fixture: TwMultiGoal splits into one TwGoal per pos
  # binding and backjumps over which to satisfy first. Merges domain + problem
  # the way TwLoader::load_file_pair does. Exercises the compiled NIF (green in
  # CI, which builds taskweft_nif from source; a stale bundled DLL returns
  # "no_plan", as the existing CLI planner tests do).
  describe "multigoal plans soundly through the NIF" do
    setup do
      domain = read_json(Path.join([@plans, "domains", "blocks_world.jsonld"]))
      problem = read_json(Path.join([@plans, "problems", "blocks_world_multigoal.jsonld"]))
      {:ok, merged: Jason.encode!(merge(domain, problem))}
    end

    test "replan reports every step completed and no failure", %{merged: merged} do
      plan_json = Taskweft.NIF.plan(merged)
      steps = Jason.decode!(plan_json)
      assert steps != []

      assert {:ok, out} = Taskweft.replan(merged, plan_json, -1)
      env = Jason.decode!(out)
      assert env["fail_step"] == -1
      assert env["completed_steps"] == length(steps)
    end
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  # Mirror TwLoader::load_file_pair for this case: the problem's state
  # variables override the domain's by name and its non-empty task list
  # replaces the domain's. Actions, methods, and goal methods come from the
  # domain unchanged.
  defp merge(domain, problem) do
    dom_vars = List.wrap(domain["variables"])
    prob_vars = List.wrap(problem["variables"])
    overridden = MapSet.new(prob_vars, & &1["name"])
    kept = Enum.reject(dom_vars, &MapSet.member?(overridden, &1["name"]))

    domain
    |> Map.put("variables", kept ++ prob_vars)
    |> Map.put("tasks", problem["tasks"])
  end
end
