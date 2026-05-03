defmodule Mix.Tasks.Taskweft.Mcp do
  @moduledoc """
  Run the Taskweft MCP server over stdio.

      mix taskweft.mcp

  Wire into Claude Code by adding to your MCP config:

      {
        "mcpServers": {
          "taskweft": {
            "command": "mix",
            "args": ["taskweft.mcp"],
            "cwd": "/home/ernest.lee/multiplayer-fabric-taskweft"
          }
        }
      }
  """

  use Mix.Task

  @shortdoc "Run the Taskweft MCP server over stdio"

  @impl Mix.Task
  def run(_args) do
    ExMCP.Internal.StdioLoggerConfig.configure()
    Mix.Task.run("app.start", [])

    {:ok, _server} = Taskweft.MCP.Server.start_link(transport: :stdio)

    Process.sleep(:infinity)
  end
end
