# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule TaskweftDeploy.Application do
  @moduledoc """
  Boots the hosted Taskweft MCP server: a Cowboy endpoint running
  `TaskweftDeploy.Router`, which bridges MCP-client OAuth to GitHub login (via
  `oauth_mcp_bridge`) and gates MCP requests behind a macaroon access token.
  No database, no volume — all OAuth state is a stateless macaroon, so
  scale-to-zero restarts lose nothing.

  Runtime env:

    * `PORT` — listen port (default 8080; Fly maps 443/TLS → this).
    * `TASKWEFT_TOKEN_SECRET` — macaroon root key (**required in prod**; a stable
      value so tokens survive restarts). A random key is used if unset (dev only).
    * `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` — the GitHub OAuth app.
    * `TASKWEFT_MCP_GH_ALLOW` — whitelist (comma list; bare = login, `@name`/`org:name` = org). Default `fire`.
    * `PUBLIC_BASE_URL` — external URL (issuer); derived from Fly's forwarded headers if unset.
  """

  use Application
  require Logger

  alias OAuthMCPBridge.Whitelist

  @impl true
  def start(_type, _args) do
    :persistent_term.put({:oauth_mcp_bridge, :token_secret}, token_secret())
    :persistent_term.put({:oauth_mcp_bridge, :auth}, Whitelist.parse(env("TASKWEFT_MCP_GH_ALLOW", "fire")))

    :persistent_term.put(
      {:oauth_mcp_bridge, :github},
      %{client_id: env("GITHUB_CLIENT_ID", ""), client_secret: env("GITHUB_CLIENT_SECRET", "")}
    )

    :persistent_term.put({:oauth_mcp_bridge, :service}, %{
      name: "Taskweft MCP",
      documentation_url: "https://github.com/taskweft/deploy"
    })

    :persistent_term.put({:oauth_mcp_bridge, :page}, %{
      title: "taskweft",
      tagline:
        "Hosted HTN planner MCP server — plan / replan over JSON-LD domains, gated by GitHub sign-in (OAuth 2.1).",
      server_name: "taskweft",
      links: [
        {"taskweft/deploy", "https://github.com/taskweft/deploy"},
        {"taskweft/taskweft", "https://github.com/taskweft/taskweft"}
      ]
    })

    case env("PUBLIC_BASE_URL", nil) do
      url when is_binary(url) and url != "" -> :persistent_term.put({:oauth_mcp_bridge, :base_url}, url)
      _ -> :ok
    end

    port = String.to_integer(env("PORT", "8080"))
    Logger.info("taskweft MCP (OAuth/GitHub) listening on 0.0.0.0:#{port}")

    children = [
      {Plug.Cowboy,
       scheme: :http, plug: TaskweftDeploy.Router, options: [port: port, ip: {0, 0, 0, 0}]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TaskweftDeploy.Supervisor)
  end

  defp token_secret do
    case env("TASKWEFT_TOKEN_SECRET", nil) do
      s when is_binary(s) and byte_size(s) >= 16 ->
        s

      _ ->
        Logger.warning("TASKWEFT_TOKEN_SECRET unset/short — using an ephemeral dev key (tokens won't survive restart)")
        :crypto.strong_rand_bytes(32)
    end
  end

  defp env(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      v -> v
    end
  end
end
