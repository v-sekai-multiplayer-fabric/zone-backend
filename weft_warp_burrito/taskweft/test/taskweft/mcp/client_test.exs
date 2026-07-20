# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias Taskweft.MCP.Client

  describe "module surface" do
    test "exports the four public functions" do
      Code.ensure_loaded!(Client)
      exports = Client.__info__(:functions)

      for {name, arity} <- [
            {:connect, 1},
            {:connect, 2},
            {:disconnect, 1},
            {:list_tools, 1},
            {:list_tools, 2},
            {:call_tool, 3},
            {:call_tool, 4},
            {:connect_configured, 0}
          ] do
        assert {name, arity} in exports, "expected #{name}/#{arity} to be exported"
      end
    end
  end

  describe "connect_configured/0" do
    setup do
      original = Application.get_env(:taskweft, :mcp_peers)
      on_exit(fn -> restore(:taskweft, :mcp_peers, original) end)
      :ok
    end

    test "with no peer config, returns an empty map" do
      Application.delete_env(:taskweft, :mcp_peers)
      assert Client.connect_configured() == %{}
    end
  end

  defp restore(_app, _key, nil), do: :ok
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  # Integration test against the official reference MCP server. Deterministic,
  # no LLM, no API key — `@modelcontextprotocol/server-everything` is
  # purpose-built as a client test target. Skipped unless `npx` is on PATH
  # and the test is explicitly included.
  describe "integration: @modelcontextprotocol/server-everything" do
    @tag :integration
    test "round-trips list_tools then call_tool against the reference server" do
      if System.find_executable("npx") == nil do
        :skipped
      else
        spec =
          {:stdio, command: ["npx", "-y", "@modelcontextprotocol/server-everything"]}

        case Client.connect(spec, timeout: 30_000) do
          {:ok, client} ->
            {:ok, tools} = Client.list_tools(client)
            assert is_list(tools) and length(tools) > 0

            # `echo` is one of server-everything's standard tools and is
            # purely deterministic.
            tool_names =
              Enum.map(tools, fn t ->
                Map.get(t, :name) || Map.get(t, "name")
              end)

            assert "echo" in tool_names

            {:ok, content} = Client.call_tool(client, "echo", %{"message" => "hi"})
            text = content |> List.first() |> (&(Map.get(&1, "text") || Map.get(&1, :text))).()
            assert is_binary(text) and String.contains?(text, "hi")

            Client.disconnect(client)

          {:error, reason} ->
            flunk("Could not connect to server-everything: #{inspect(reason)}")
        end
      end
    end
  end
end
