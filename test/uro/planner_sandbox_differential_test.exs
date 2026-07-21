# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Planner.SandboxAdapterDifferentialTest do
  @moduledoc """
  Differential testing for RFD 0023 (Stage 5A): every domain here runs
  through both `Uro.Planner.TaskweftAdapter` (the native `tw_loader.hpp`
  + `tw_planner.hpp` NIF) and `Uro.Planner.SandboxAdapter` (compiled
  Scheme in the libriscv guest -- the whole HTN search AND domain
  evaluation, not just a search-only subset) and must agree, proving the
  port before any config-flip in production traffic. Every domain uses
  the CURRENT loader schema (variables/actions/methods/todo_list), not
  the stale `priv/domains/*.jsonld` schema (a separate, pre-existing bug
  per RFD 0023's Context section).
  """
  use ExUnit.Case, async: true

  alias Uro.Planner.SandboxAdapter
  alias Uro.Planner.TaskweftAdapter

  setup do
    elf_path = Path.join(:code.priv_dir(:uro), "planner.elf")

    start_supervised!(
      {WeftWarpBurrito.Program, elf: File.read!(elf_path), name: SandboxAdapter.Program}
    )

    :ok
  end

  defp run(adapter, domain_json) do
    {:ok, adapter.plan(domain_json)}
  rescue
    _ -> :no_plan
  end

  defp assert_agrees(domain_json) do
    native = run(TaskweftAdapter, domain_json)
    sandboxed = run(SandboxAdapter, domain_json)

    normalized_native = normalize(native)
    normalized_sandboxed = normalize(sandboxed)

    assert normalized_native == normalized_sandboxed,
           "adapters disagree: native=#{inspect(normalized_native)} " <>
             "sandbox=#{inspect(normalized_sandboxed)}"

    normalized_native
  end

  defp normalize(:no_plan), do: :no_plan
  defp normalize({:ok, json}), do: Jason.decode!(json)

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
    assert [["flee"], ["recover"]] = assert_agrees(@behave_domain)
  end

  test "compound task falls back when the checked alternative's guard fails" do
    domain = String.replace(@behave_domain, ~s("near": true), ~s("near": false))
    assert [["drift"]] = assert_agrees(domain)
  end

  test "goal with no registered method is a clean no-plan on both adapters" do
    domain = """
    {
      "variables": [{"name": "loc", "init": {"pos": "open"}}],
      "todo_list": [{"goal": [{"pointer": "/loc/pos", "eq": "shelter"}]}]
    }
    """

    assert :no_plan = assert_agrees(domain)
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

    assert [["recover"], ["flee"]] = assert_agrees(domain)
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

    assert [["bump"], ["bump"], ["bump"]] = assert_agrees(domain)
  end

  test "a long flat sequence of independent primitive actions costs no branching fuel" do
    calls = List.duplicate(~s(["drift"]), 50) |> Enum.join(", ")

    domain = """
    {
      "actions": {"drift": {"body": []}},
      "todo_list": [#{calls}]
    }
    """

    assert plan = assert_agrees(domain)
    assert length(plan) == 50
  end
end
