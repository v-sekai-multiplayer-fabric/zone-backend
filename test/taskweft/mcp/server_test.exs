# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Taskweft.MCP.Server

  @blocks_world_domain Path.join([__DIR__, "../../../priv/plans/domains/blocks_world.jsonld"])

  describe "handle_tool_call/3" do
    test "plan returns JSON-encoded plan steps" do
      domain = File.read!(@blocks_world_domain)

      assert {:ok, %{content: [%{"type" => "text", "text" => text}]}, %{}} =
               Server.handle_tool_call("plan", %{"domain_json" => domain}, %{})

      assert {:ok, steps} = Jason.decode(text)
      assert is_list(steps)
    end

    test "replan honors fail_step" do
      domain = File.read!(@blocks_world_domain)

      {:ok, %{content: [%{"text" => plan_json}]}, _} =
        Server.handle_tool_call("plan", %{"domain_json" => domain}, %{})

      assert {:ok, %{content: [%{"text" => replan_text}]}, %{}} =
               Server.handle_tool_call(
                 "replan",
                 %{"domain_json" => domain, "plan_json" => plan_json, "fail_step" => 1},
                 %{}
               )

      assert {:ok, %{"fail_step" => 1}} = Jason.decode(replan_text)
    end

    test "simulate runs a plan to completion with no failure probabilities" do
      domain = File.read!(@blocks_world_domain)

      {:ok, %{content: [%{"text" => plan_json}]}, _} =
        Server.handle_tool_call("plan", %{"domain_json" => domain}, %{})

      assert {:ok, %{content: [%{"text" => trace_text}]}, %{}} =
               Server.handle_tool_call(
                 "simulate",
                 %{
                   "domain_json" => domain,
                   "plan_json" => plan_json,
                   "probs_json" => "{}",
                   "seed" => 0
                 },
                 %{}
               )

      assert {:ok, trace} = Jason.decode(trace_text)
      assert is_integer(trace["completed"])
    end

    test "unknown tool returns error" do
      assert {:error, "unknown tool: nope", %{}} = Server.handle_tool_call("nope", %{}, %{})
    end
  end

  describe "handle_resource_read/3" do
    test "domains URI returns JSON-LD content with mimeType" do
      uri = "taskweft://domains/blocks_world.jsonld"

      assert {:ok, [content], %{}} = Server.handle_resource_read(uri, uri, %{})
      assert content.uri == uri
      assert content.mimeType == "application/ld+json"
      assert {:ok, _} = Jason.decode(content.text)
    end

    test "problems URI returns JSON-LD content" do
      uri = "taskweft://problems/blocks_world_1a.jsonld"

      assert {:ok, [%{mimeType: "application/ld+json"}], %{}} =
               Server.handle_resource_read(uri, uri, %{})
    end

    test "rejects non-jsonld files" do
      uri = "taskweft://domains/something.txt"

      assert {:error, "not a .jsonld file: something.txt", %{}} =
               Server.handle_resource_read(uri, uri, %{})
    end

    test "rejects path traversal" do
      uri = "taskweft://domains/../etc/passwd.jsonld"
      assert {:error, "illegal name: " <> _, %{}} = Server.handle_resource_read(uri, uri, %{})
    end

    test "missing files return not_found" do
      uri = "taskweft://domains/nonexistent.jsonld"

      assert {:error, "not found: nonexistent.jsonld", %{}} =
               Server.handle_resource_read(uri, uri, %{})
    end

    test "unknown URI scheme returns error" do
      assert {:error, "unknown resource: foo://bar", %{}} =
               Server.handle_resource_read("foo://bar", "foo://bar", %{})
    end
  end

  describe "handle_prompt_get/3" do
    test "work_queue returns the stored skill content" do
      assert {:ok, %{messages: [%{"role" => "user", "content" => text}]}, %{}} =
               Server.handle_prompt_get("work_queue", %{}, %{})

      assert text =~ "work_queue.jsonld"
      assert text =~ "phase"
    end

    test "plan_problem interpolates domain and problem args" do
      assert {:ok, %{messages: [%{"content" => text}]}, %{}} =
               Server.handle_prompt_get(
                 "plan_problem",
                 %{"domain" => "blocks_world.jsonld", "problem" => "blocks_world_3.jsonld"},
                 %{}
               )

      assert text =~ "blocks_world.jsonld"
      assert text =~ "blocks_world_3.jsonld"
    end

    test "unknown prompt returns error" do
      assert {:error, "unknown prompt: nope", %{}} = Server.handle_prompt_get("nope", %{}, %{})
    end
  end

  # The stdio transport (ExMCP.Server.StdioServer) only natively dispatches
  # initialize/tools/resources/list. Everything else falls through to
  # `handle_request/3` on the handler module, which we override to bridge to
  # our DSL handlers. Without this bridge, `resources/read` and `prompts/*`
  # silently drop and the MCP client times out.
  describe "handle_request/3 — stdio transport bridge" do
    test "resources/read forwards to handle_resource_read" do
      assert {:reply, %{"contents" => [content]}, %{}} =
               Server.handle_request(
                 "resources/read",
                 %{"uri" => "taskweft://domains/blocks_world.jsonld"},
                 %{}
               )

      assert content.uri == "taskweft://domains/blocks_world.jsonld"
      assert content.mimeType == "application/ld+json"
    end

    test "resources/read on unknown URI returns error tuple (not noreply)" do
      assert {:error, _, %{}} =
               Server.handle_request("resources/read", %{"uri" => "foo://bar"}, %{})
    end

    test "prompts/list returns 4 prompts" do
      assert {:reply, %{"prompts" => prompts}, %{}} =
               Server.handle_request("prompts/list", %{}, %{})

      names = Enum.map(prompts, & &1["name"]) |> Enum.sort()
      assert names == ["plan_problem", "replan_after_failure", "simulate_plan", "work_queue"]
    end

    test "prompts/get forwards to handle_prompt_get" do
      assert {:reply, %{messages: _}, %{}} =
               Server.handle_request("prompts/get", %{"name" => "work_queue"}, %{})
    end

    test "unknown method falls through to noreply (lets StdioServer return method-not-found)" do
      assert {:noreply, %{}} = Server.handle_request("unknown/method", %{}, %{})
    end
  end
end
