# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule TaskweftDeploy.Router do
  @moduledoc """
  HTTP surface for the hosted MCP server:

    * `GET /` — unauthenticated minimal landing page (not the MCP endpoint).
    * `GET /health` — unauthenticated liveness (Fly checks).
    * `GET /.well-known/oauth-protected-resource` and
      `GET /.well-known/oauth-authorization-server` — OAuth discovery (RFC 9728 / 8414).
    * `POST /oauth/register` — dynamic client registration (RFC 7591).
    * `GET  /oauth/authorize` — start the flow; redirects to GitHub login.
    * `GET  /oauth/callback` — GitHub redirect; issues our authorization code.
    * `POST /oauth/token` — exchange code (+ PKCE) for a macaroon access token.
    * `/mcp` (any sub-path) — the actual MCP endpoint (`ExMCP.HttpPlug`), gated
      by `mcp_guard`, which requires a valid macaroon bearer and answers 401
      with a `WWW-Authenticate` pointing at the resource metadata so clients
      discover the flow.

  We never run `Plug.Parsers`, so `ExMCP.HttpPlug` still sees the raw MCP body;
  OAuth bodies are read explicitly.
  """

  use Plug.Router

  alias OAuthMCPBridge.{BaseURL, Guard, LandingPlug, OAuth}

  plug(Plug.Logger)
  plug(:match)
  plug(:mcp_guard)
  plug(:dispatch)

  # taskweft's own resolved version, not a separately hand-bumped constant —
  # a hardcoded duplicate went stale the first time taskweft was bumped
  # without a matching edit here. `Application.spec(:taskweft, :vsn)` doesn't
  # work here (returns nil): this module compiles as *part of* the :taskweft
  # app now (folded in from a formerly-separate deploy/ Mix project, where it
  # was a genuine cross-app path-dependency read against an already-compiled
  # :taskweft) -- reading your own app's .app spec while still compiling it
  # is self-referential and empty. `Mix.Project.config()/0` has no such
  # ordering problem (same pattern `Taskweft.CLI` already uses for its own
  # `@version`): it just reads mix.exs's own project config directly.
  @taskweft_version Mix.Project.config()[:version]

  # Baked into the image at build time (Containerfile ARG GIT_SHA), not read
  # from a runtime env var — so it can never drift from what was actually
  # compiled into this image.
  @git_sha System.get_env("GIT_SHA", "unknown")

  @mcp_init [
    handler: Taskweft.MCP.Server,
    server_info: %{name: "taskweft", version: @taskweft_version},
    tools: [],
    sse_enabled: true,
    cors_enabled: true,
    # ex_mcp's own default is `allowed_origins: []` -- deny-all, so
    # cors_response_origin/2 never sets Access-Control-Allow-Origin for a
    # genuinely cross-origin request even with cors_enabled: true. Origin
    # restriction defends against ambient-credential (cookie) flows; this
    # endpoint's actual auth boundary is an explicit macaroon Bearer token
    # (OAuthMCPBridge.Guard.require_bearer), which a malicious page can't
    # forge just by making a cross-origin request, so restricting Origin on
    # top adds no real security here -- only breaks legitimate browser-based
    # MCP clients.
    allowed_origins: :any,
    validate_origin: false
  ]

  get "/" do
    LandingPlug.call(conn, [])
  end

  get "/health" do
    send_json(conn, 200, %{
      "status" => "ok",
      "version" => @taskweft_version,
      "git_sha" => @git_sha
    })
  end

  get "/.well-known/oauth-protected-resource" do
    send_json(conn, 200, OAuth.protected_resource_metadata(BaseURL.get(conn)))
  end

  get "/.well-known/oauth-authorization-server" do
    send_json(conn, 200, OAuth.authorization_server_metadata(BaseURL.get(conn)))
  end

  post "/oauth/register" do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, req} <- Jason.decode(body),
         {:ok, registration} <- OAuth.register_client(req) do
      send_json(conn, 201, registration)
    else
      {:error, reason} ->
        send_json(conn, 400, %{"error" => "invalid_client_metadata", "detail" => inspect(reason)})

      _ ->
        send_json(conn, 400, %{"error" => "invalid_client_metadata"})
    end
  end

  get "/oauth/authorize" do
    conn = fetch_query_params(conn)

    case OAuth.authorize(BaseURL.get(conn), conn.query_params) do
      {:ok, github_url} -> redirect(conn, github_url)
      {:error, _} -> send_json(conn, 400, %{"error" => "invalid_request"})
    end
  end

  get "/oauth/callback" do
    conn = fetch_query_params(conn)

    case OAuth.callback(BaseURL.get(conn), conn.query_params) do
      {:ok, client_redirect} -> redirect(conn, client_redirect)
      {:error, _} -> send_json(conn, 400, %{"error" => "invalid_request"})
    end
  end

  post "/oauth/token" do
    with {:ok, body, conn} <- read_body(conn),
         params = URI.decode_query(body),
         {:ok, token_response} <- OAuth.token(BaseURL.get(conn), params) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_json(200, token_response)
    else
      {:error, oauth_error} -> send_json(conn, 400, %{"error" => to_string(oauth_error)})
      _ -> send_json(conn, 400, %{"error" => "invalid_request"})
    end
  end

  # The real MCP endpoint. ExMCP.HttpPlug routes POST (JSON-RPC) on any path
  # under this mount and GET /sse; mcp_guard has already enforced a valid
  # macaroon bearer. Plug.Router's forward strips the "/mcp" prefix before
  # handing off, so ExMCP.HttpPlug sees paths exactly as it did when mounted
  # at "/" (e.g. a request to /mcp/sse arrives there as path_info ["sse"]).
  forward("/mcp", to: ExMCP.HttpPlug, init_opts: @mcp_init)

  match _ do
    send_resp(conn, 404, "not found")
  end

  # ── auth gate for the MCP endpoint ──────────────────────────────────────────

  defp mcp_guard(conn, _opts) do
    if public_path?(conn), do: conn, else: Guard.require_bearer(conn)
  end

  # CORS preflight (OPTIONS) requests never carry an Authorization header --
  # that's how browsers issue them, before they know whether the real
  # request is even allowed. Gating OPTIONS behind require_bearer means
  # every preflight gets a bare 401 with no Access-Control-Allow-* headers,
  # so the browser blocks the real request at the CORS stage before it's
  # ever sent -- ExMCP.HttpPlug's own cors_enabled: true (@mcp_init) never
  # gets a chance to answer, since mcp_guard runs before forward("/mcp", ...)
  # in the pipeline. The actual GET/POST/DELETE to /mcp still requires a
  # bearer token; only the preflight itself is public.
  defp public_path?(conn) do
    p = conn.request_path

    conn.method == "OPTIONS" or p == "/" or p == "/health" or
      String.starts_with?(p, "/.well-known/") or String.starts_with?(p, "/oauth/")
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp send_json(conn, status, map) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(map))
  end

  defp redirect(conn, url) do
    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end
end
