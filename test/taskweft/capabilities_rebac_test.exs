# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.CapabilitiesReBACTest do
  @moduledoc """
  Coverage for ADR 0004 (unify domain `capabilities` with the ReBAC
  relation-expression engine, taskweft#96): action capability guards are
  evaluated against a `TwReBAC::TwReBACGraph` (`tw_rebac.hpp`) rather than
  precomputed booleans, so a domain can express requirements the old flat
  `{"entities": ..., "actions": ...}` shape could not — transitive team
  membership, and composed relation expressions (union/intersection/...).
  """
  use ExUnit.Case, async: true

  defp domain(extra), do: Map.merge(%{"@type" => "domain:Definition", "name" => "t"}, extra)

  defp plans?(domain_json) do
    case Taskweft.plan(domain_json) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  describe "backward compatibility: flat entities/actions shape" do
    defp flat_domain(entity_caps) do
      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "entities" => %{"drone_1" => entity_caps},
          "actions" => %{"a_fly" => ["fly"]}
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "drone_1"]]
      })
      |> Jason.encode!()
    end

    test "an entity holding the required capability may act" do
      assert plans?(flat_domain(["fly"]))
    end

    test "an entity lacking the required capability may not act" do
      refute plans?(flat_domain(["swim"]))
    end
  end

  describe "explicit graph: transitive capability via team membership" do
    defp team_domain(agent_on_team?) do
      edges =
        if agent_on_team? do
          [%{"subject" => "alice", "object" => "flight_team", "rel" => "IS_MEMBER_OF"}]
        else
          []
        end

      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "graph" => %{
            "edges" =>
              edges ++
                [%{"subject" => "flight_team", "object" => "fly", "rel" => "HAS_CAPABILITY"}],
            "definitions" => %{}
          },
          "actions" => %{"a_fly" => ["fly"]}
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "alice"]]
      })
      |> Jason.encode!()
    end

    test "a member of a capability-holding team inherits the capability transitively" do
      assert plans?(team_domain(true))
    end

    test "a non-member does not inherit the team's capability" do
      refute plans?(team_domain(false))
    end
  end

  describe "full relation-expression action requirement" do
    defp union_domain(caps) do
      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "entities" => %{"drone_1" => caps},
          "actions" => %{
            "a_fly" => [
              %{
                "rel" => %{
                  "type" => "union",
                  "a" => %{"type" => "base", "rel" => "HAS_CAPABILITY"},
                  "b" => %{"type" => "base", "rel" => "HAS_CAPABILITY"}
                },
                "object" => "fly"
              }
            ]
          }
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "drone_1"]]
      })
      |> Jason.encode!()
    end

    test "a union expression over HAS_CAPABILITY still matches a direct edge" do
      assert plans?(union_domain(["fly"]))
    end

    test "a union expression still rejects an unrelated capability" do
      refute plans?(union_domain(["swim"]))
    end
  end

  describe "capability requirement composes with an ordinary eval guard" do
    # Capability requirements now compile into an {"eval": {"type":
    # "rebac/check", ...}} step prepended to the action's own body, instead
    # of a separate bespoke guard mechanism — so a capability-guarded action
    # can also carry an ordinary eval guard in its body, and BOTH must hold.
    # This is the thing Phase 1 (composition over special forms) actually
    # buys: one mechanism, not two independently-checked ones.
    defp composed_domain(caps, ready?) do
      domain(%{
        "variables" => [
          %{"name" => "done", "init" => %{"a" => false}},
          %{"name" => "ready", "init" => %{"drone_1" => ready?}}
        ],
        "capabilities" => %{
          "entities" => %{"drone_1" => caps},
          "actions" => %{"a_fly" => ["fly"]}
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [
              %{
                "eval" => %{
                  "type" => "math/eq",
                  "a" => %{"type" => "pointer/get", "pointer" => "/ready/{agent}"},
                  "b" => true
                }
              },
              %{"pointer/set" => "/done/a", "value" => true}
            ]
          }
        },
        "tasks" => [["a_fly", "drone_1"]]
      })
      |> Jason.encode!()
    end

    test "capability held and eval guard passes -> plans" do
      assert plans?(composed_domain(["fly"], true))
    end

    test "capability held but eval guard fails -> no plan" do
      refute plans?(composed_domain(["fly"], false))
    end

    test "capability missing even though eval guard passes -> no plan" do
      refute plans?(composed_domain(["swim"], true))
    end
  end
end
