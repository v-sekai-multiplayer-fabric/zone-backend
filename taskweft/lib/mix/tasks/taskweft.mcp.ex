defmodule Mix.Tasks.Taskweft.Mcp do
  @moduledoc """
  Run the Taskweft MCP server over HTTP.

      mix taskweft.mcp                         # Streamable HTTP on 127.0.0.1:51737
      mix taskweft.mcp --port 51737            # custom port
      mix taskweft.mcp --host 0.0.0.0          # bind all interfaces

  Exposes the MCP Streamable HTTP transport: POST any path for JSON-RPC
  requests, GET with `Accept: text/event-stream` (or `/sse`, `/mcp/v1/sse`)
  for the streamed response channel.

  Wire this into an MCP client by adding to your MCP config:

      {
        "mcpServers": {
          "taskweft": { "type": "http", "url": "http://127.0.0.1:51737" }
        }
      }
  """

  use Mix.Task

  @shortdoc "Run the Taskweft MCP server (HTTP streaming)"

  @switches [port: :integer, host: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("app.start", [])

    port = opts[:port] || 51737
    host = opts[:host] || "127.0.0.1"

    {:ok, _server} =
      Taskweft.MCP.Server.start_link(
        transport: :http,
        port: port,
        host: host,
        sse_enabled: true
      )

    Mix.shell().info("Taskweft MCP listening on http://#{host}:#{port} (Streamable HTTP + SSE)")
    Process.sleep(:infinity)
  end
end
