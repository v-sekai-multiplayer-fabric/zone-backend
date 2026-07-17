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

  @plans :code.priv_dir(:taskweft) |> Path.join("plans")

  defp base(extra),
    do: Map.merge(%{"@type" => "domain:Problem", "name" => "t"}, extra)

  describe "validate/2 multigoal tasks" do
    test "accepts a {multigoal} task entry" do
      doc = base(%{"todo_list" => [%{"multigoal" => %{"pos" => %{"a" => "table", "b" => "a"}}}]})
      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts a call array and a multigoal task in the same list" do
      doc =
        base(%{
          "todo_list" => [["move_one", "a", "table"], %{"multigoal" => %{"pos" => %{"c" => "b"}}}]
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects an empty multigoal" do
      doc = base(%{"todo_list" => [%{"multigoal" => %{}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a multigoal var whose bindings are empty" do
      doc = base(%{"todo_list" => [%{"multigoal" => %{"pos" => %{}}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a multigoal var bound to a non-object" do
      doc = base(%{"todo_list" => [%{"multigoal" => %{"pos" => "table"}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a multigoal whose value is not an object" do
      doc = base(%{"todo_list" => [%{"multigoal" => "pos"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects an object task that is neither multigoal nor goal" do
      doc = base(%{"todo_list" => [%{"unknown_kind" => %{}}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end
  end

  describe "validate/2 goal tasks" do
    test "accepts a {goal} task entry" do
      doc = base(%{"todo_list" => [%{"goal" => [%{"pointer" => "/switch/x", "eq" => true}]}]})
      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts a call array and a goal task in the same list" do
      doc =
        base(%{
          "todo_list" => [
            ["move_one", "a", "table"],
            %{"goal" => [%{"pointer" => "/switch/x", "eq" => true}]}
          ]
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects an empty goal binding list" do
      doc = base(%{"todo_list" => [%{"goal" => []}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a goal binding missing eq" do
      doc = base(%{"todo_list" => [%{"goal" => [%{"pointer" => "/switch/x"}]}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a goal binding missing pointer" do
      doc = base(%{"todo_list" => [%{"goal" => [%{"eq" => true}]}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end

    test "rejects a goal whose value is not an array" do
      doc = base(%{"todo_list" => [%{"goal" => "not_a_list"}]})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/todo_list/0"
    end
  end

  describe "validate/2 capabilities (RECTGTN 'R'/'C')" do
    # A dedicated top-level "capabilities" key (ADR 0004) — structured/
    # relational graph data gets its own namespaced slot, matching glTF
    # Interactivity's own convention for extension data that isn't a
    # scalar/vector value socket. An action requirement is not a separate
    # validated shape: it's a hand-written {"eval": {"type": "rebac/check",
    # ...}} step, covered by the ordinary body_step schema.
    test "accepts a well-formed capabilities object" do
      doc = base(%{"capabilities" => %{"entities" => %{"drone_1" => ["fly"]}}})
      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts a domain with no capabilities key at all" do
      assert :ok = Loader.validate(base(%{}), %{})
    end

    test "accepts entities being omitted" do
      assert :ok = Loader.validate(base(%{"capabilities" => %{}}), %{})
    end

    test "rejects a non-object capabilities value" do
      doc = base(%{"capabilities" => "fly"})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/capabilities"
    end

    test "rejects a non-object entities group" do
      doc = base(%{"capabilities" => %{"entities" => ["fly"]}})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/capabilities/entities"
    end

    test "rejects a capability list containing a non-string" do
      doc = base(%{"capabilities" => %{"entities" => %{"drone_1" => [1]}}})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/capabilities/entities/drone_1"
    end

    test "accepts an explicit ReBAC graph" do
      doc =
        base(%{
          "capabilities" => %{
            "graph" => %{
              "edges" => [%{"subject" => "team", "object" => "fly", "rel" => "HAS_CAPABILITY"}],
              "definitions" => %{}
            }
          }
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects a malformed ReBAC graph edge" do
      doc =
        base(%{
          "capabilities" => %{
            "graph" => %{"edges" => [%{"subject" => "team", "object" => "fly"}]}
          }
        })

      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/capabilities/graph/edges"
    end
  end

  describe "validate/2 action duration (RECTGTN 'T')" do
    test "accepts a valid ISO 8601 duration" do
      doc =
        base(%{
          "actions" => %{
            "a_fly" => %{"duration" => "PT5M", "params" => [], "body" => []}
          }
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts an action with no duration field" do
      doc = base(%{"actions" => %{"a_fly" => %{"params" => [], "body" => []}}})
      assert :ok = Loader.validate(doc, %{})
    end

    test "rejects a non-string duration" do
      doc = base(%{"actions" => %{"a_fly" => %{"duration" => 5, "params" => [], "body" => []}}})
      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/actions/a_fly/duration"
    end

    test "rejects a malformed ISO 8601 duration string" do
      doc =
        base(%{
          "actions" => %{"a_fly" => %{"duration" => "5 minutes", "params" => [], "body" => []}}
        })

      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "action a_fly: invalid duration"
    end
  end

  describe "validate/2 @type" do
    test "accepts the new domain:Problem type" do
      assert :ok = Loader.validate(base(%{}), %{})
    end
  end

  describe "validate/2 domain:Definition requires at least one action or method" do
    defp def_base(extra), do: Map.merge(%{"@type" => "domain:Definition", "name" => "d"}, extra)

    test "rejects an empty document (no @type/name/actions at all)" do
      assert {:error, _msg} = Loader.validate(%{}, %{})
    end

    test "rejects a domain:Definition with neither actions nor methods" do
      assert {:error, msg} = Loader.validate(def_base(%{}), %{})
      assert msg =~ "must declare at least one action or method"
    end

    test "rejects a domain:Definition with an empty actions object and no methods" do
      assert {:error, msg} = Loader.validate(def_base(%{"actions" => %{}}), %{})
      assert msg =~ "must declare at least one action or method"
    end

    test "accepts a domain:Definition with at least one action" do
      doc = def_base(%{"actions" => %{"do_a" => %{"params" => [], "body" => []}}})
      assert :ok = Loader.validate(doc, %{})
    end

    test "accepts a domain:Definition with methods but no actions of its own" do
      doc =
        def_base(%{
          "methods" => %{
            "m1" => %{"params" => [], "alternatives" => [%{"name" => "only", "subtasks" => []}]}
          }
        })

      assert :ok = Loader.validate(doc, %{})
    end

    test "a domain:Problem is not required to declare actions" do
      assert :ok = Loader.validate(base(%{}), %{})
    end
  end

  describe "load_string end-to-end (context resolution + validate)" do
    test "a multigoal problem document round-trips" do
      json = ~s({
        "@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/", "domain": "khr:planning/domain/"},
        "@type": "domain:Problem",
        "name": "switch_multigoal",
        "variables": [{"name": "switch", "type": "bool", "init": {"x": false, "y": false}}],
        "todo_list": [{"multigoal": {"switch": {"x": true, "y": true}}}]
      })

      assert {:ok, _compact} = Loader.load_string(json)
    end

    test "a goal-binding problem document round-trips" do
      json = ~s({
        "@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/", "domain": "khr:planning/domain/"},
        "@type": "domain:Problem",
        "name": "switch_goal",
        "variables": [{"name": "switch", "type": "bool", "init": {"x": false}}],
        "todo_list": [{"goal": [{"pointer": "/switch/x", "eq": true}]}]
      })

      assert {:ok, _compact} = Loader.load_string(json)
    end
  end

  describe "load_string invalid JSON diagnostics" do
    test "returns the base invalid JSON message for malformed input" do
      assert {:error, msg} = Loader.load_string("not json")
      assert msg =~ "invalid JSON"
    end

    test "adds an actionable hint for escaped/double-encoded payloads" do
      assert {:error, msg} = Loader.load_string("\\{\"@type\":\"domain:Definition\"}")
      assert msg =~ "invalid JSON"
      assert msg =~ "escaped/double-encoded"
      assert msg =~ "raw JSON text"
    end

    test "adds an actionable hint when a resource URI is passed instead of JSON content" do
      assert {:error, msg} =
               Loader.load_string("taskweft://domains/entity_capabilities.jsonld")

      assert msg =~ "invalid JSON"
      assert msg =~ "looks like a URI"
      assert msg =~ "resources/read"
    end

    test "adds a line/column snippet hint for a generic syntax error" do
      # Stray "]" right after "actions" closes — no matching "[".
      json = ~s({"@type":"domain:Definition","name":"demo","actions":{}]})

      assert {:error, msg} = Loader.load_string(json)
      assert msg =~ "invalid JSON"
      assert msg =~ "at line 1, column"
      assert msg =~ "^"
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

  # A goal-method (TwGoalMethodFn) IS a TwMethodFn (tw_domain.hpp) — invoked
  # as (state, [key, desired]), mechanically identical to an ordinary method
  # call [goal_var, key, desired]. There's no separate "goals" key at all: a
  # goal-satisfying method is just an ordinary "methods" entry named after
  # the state var it targets, so a problem expresses its goal as an ordinary
  # "todo_list" entry (["pos", "a", "table"]) — merged via the
  # already-correct merge_tasks path.
  describe "goal-methods are directly callable as ordinary tasks" do
    setup do
      {:ok, domain: read_json(Path.join([@plans, "domains", "blocks_world.jsonld"]))}
    end

    test "two different goals produce two genuinely different plans", %{domain: domain} do
      plan_for = fn goal_task ->
        domain
        |> Map.put("todo_list", [goal_task])
        |> Jason.encode!()
        |> Taskweft.plan()
        |> then(fn {:ok, json} -> Jason.decode!(json) end)
      end

      a_to_table = plan_for.(["pos", "a", "table"])["plan"]
      c_to_a = plan_for.(["pos", "c", "a"])["plan"]

      refute a_to_table == c_to_a
      assert ["a_pickup", "c"] in c_to_a
      assert ["a_stack", "c", "a"] in c_to_a
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
    |> Map.put("todo_list", problem["todo_list"])
  end
end
