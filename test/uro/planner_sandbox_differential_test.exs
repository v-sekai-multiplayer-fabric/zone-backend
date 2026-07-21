# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Planner.SandboxAdapterDifferentialTest do
  @moduledoc """
  Regression suite for `Uro.Planner.SandboxAdapter` (compiled Scheme in
  the libriscv guest, RFD 0023 -- Stage 5A: the whole HTN search AND
  domain evaluation, not just a search-only subset).

  These cases originally ran through both `Uro.Planner.TaskweftAdapter`
  (the native `tw_loader.hpp` + `tw_planner.hpp` NIF) and
  `Uro.Planner.SandboxAdapter`, asserting agreement, to prove the port
  before the RFD 0038 config-flip that made the sandbox adapter the
  only one. The native adapter is now retired, so each case just pins
  the plan that comparison already proved correct. Every domain uses
  the CURRENT loader schema (variables/actions/methods/todo_list), not
  the stale `priv/domains/*.jsonld` schema (a separate, pre-existing bug
  per RFD 0023's Context section).
  """
  use ExUnit.Case, async: true

  alias Uro.Planner.SandboxAdapter

  # SandboxAdapter.Program is booted globally by Uro.Application, since
  # RFD 0038 made Uro.Planner.SandboxAdapter the default :planner_adapter --
  # no per-test start_supervised! needed (and starting a second one under
  # the same name would collide with the already-running one).

  defp run(domain_json) do
    {:ok, SandboxAdapter.plan(domain_json)}
  rescue
    _ -> :no_plan
  end

  defp plan_for(domain_json) do
    case run(domain_json) do
      :no_plan -> :no_plan
      {:ok, json} -> Jason.decode!(json)
    end
  end

  @behave_domain """
  {
    "variables": [
      {"name": "threat", "init": {"near": true}},
      {"name": "loc", "init": {"pos": "open"}}
    ],
    "actions": {
      "flee": {"body": [{"pointer/set": "/loc/pos", "value": "shelter"}]},
      "recover": {"body": [{"pointer/set": "/threat/near", "value": false}]},
      "drift": {"body": []}
    },
    "methods": {
      "behave": {
        "alternatives": [
          {"check": [{"eval": {"type": "get", "pointer": "/threat/near"}}],
           "subtasks": [["flee"], ["recover"]]},
          {"subtasks": [["drift"]]}
        ]
      }
    },
    "todo_list": [["behave"]]
  }
  """

  test "compound task picks the checked alternative when threat is near" do
    assert [["flee"], ["recover"]] = plan_for(@behave_domain)
  end

  test "compound task falls back when the checked alternative's guard fails" do
    domain = String.replace(@behave_domain, ~s("near": true), ~s("near": false))
    assert [["drift"]] = plan_for(domain)
  end

  test "goal with no registered method is a clean no-plan" do
    domain = """
    {
      "variables": [{"name": "loc", "init": {"pos": "open"}}],
      "todo_list": [{"goal": [{"pointer": "/loc/pos", "eq": "shelter"}]}]
    }
    """

    assert :no_plan = plan_for(domain)
  end

  test "multigoal backtracks over both unmet bindings" do
    domain = """
    {
      "variables": [
        {"name": "threat", "init": {"near": true}},
        {"name": "loc", "init": {"pos": "open"}}
      ],
      "actions": {
        "flee": {"body": [{"pointer/set": "/loc/pos", "value": "shelter"}]},
        "recover": {"body": [{"pointer/set": "/threat/near", "value": false}]}
      },
      "methods": {
        "threat": {"alternatives": [{"subtasks": [["recover"]]}]},
        "loc": {"alternatives": [{"subtasks": [["flee"]]}]}
      },
      "todo_list": [
        {"multigoal": {"threat": {"near": false}, "loc": {"pos": "shelter"}}}
      ]
    }
    """

    assert [["recover"], ["flee"]] = plan_for(domain)
  end

  test "a goal whose method under-satisfies it forces a retry (splice-order proof)" do
    domain = """
    {
      "variables": [{"name": "counter", "init": {"val": 0}}],
      "actions": {
        "bump": {
          "params": ["cur"],
          "bind": [{"name": "cur", "pointer": "/counter/val"}],
          "body": [
            {"pointer/set": "/counter/val",
             "value": {"type": "add", "a": "{cur}", "b": 1}}
          ]
        }
      },
      "methods": {
        "counter": {"alternatives": [{"subtasks": [["bump"]]}]}
      },
      "todo_list": [{"goal": [{"pointer": "/counter/val", "eq": 3}]}]
    }
    """

    assert [["bump"], ["bump"], ["bump"]] = plan_for(domain)
  end

  test "a long flat sequence of independent primitive actions costs no branching fuel" do
    calls = List.duplicate(~s(["drift"]), 50) |> Enum.join(", ")

    domain = """
    {
      "actions": {"drift": {"body": []}},
      "todo_list": [#{calls}]
    }
    """

    assert plan = plan_for(domain)
    assert length(plan) == 50
  end
end
