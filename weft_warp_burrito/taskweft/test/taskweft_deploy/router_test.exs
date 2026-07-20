# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule TaskweftDeploy.RouterTest do
  @moduledoc """
  Pins the CORS-preflight-vs-auth-gate boundary: an `OPTIONS /mcp` request
  (a CORS preflight, which browsers send without an Authorization header)
  must reach `ExMCP.HttpPlug`'s own `cors_enabled: true` handling instead of
  being rejected by `mcp_guard` -- a real bug found via live testing against
  the deployed server, where every preflight got a bare 401 with no
  `Access-Control-Allow-*` headers, silently breaking every browser-based
  MCP client at the CORS stage before the real request was ever sent.
  """

  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  @opts TaskweftDeploy.Router.init([])

  test "OPTIONS /mcp is public and gets CORS headers, not a 401" do
    conn =
      :options
      |> conn("/mcp", "")
      |> put_req_header("origin", "https://example.com")
      |> put_req_header("access-control-request-method", "POST")
      |> TaskweftDeploy.Router.call(@opts)

    refute conn.status == 401
    assert get_resp_header(conn, "access-control-allow-origin") != []
    assert get_resp_header(conn, "access-control-allow-methods") != []
  end

  test "GET /mcp without a bearer token is still gated (401)" do
    conn = :get |> conn("/mcp", "") |> TaskweftDeploy.Router.call(@opts)
    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") != []
  end

  test "POST /mcp without a bearer token is still gated (401)" do
    conn = :post |> conn("/mcp", "{}") |> TaskweftDeploy.Router.call(@opts)
    assert conn.status == 401
  end

  test "DELETE /mcp without a bearer token is still gated (401)" do
    conn = :delete |> conn("/mcp", "") |> TaskweftDeploy.Router.call(@opts)
    assert conn.status == 401
  end

  test "GET / and GET /health stay public" do
    assert (:get |> conn("/", "") |> TaskweftDeploy.Router.call(@opts)).status != 401
    assert (:get |> conn("/health", "") |> TaskweftDeploy.Router.call(@opts)).status == 200
  end
end
