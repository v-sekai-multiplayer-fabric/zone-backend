<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# taskweft/deploy

Hosted **Taskweft MCP server**: `https://taskweft-mcp.fly.dev`. Wraps
`{:taskweft, github: "taskweft/taskweft"}` behind an OAuth 2.1 → GitHub login
bridge (GitHub isn't itself an MCP-compliant authorization server, so this app
is the bridge). Every OAuth artifact is a self-owned, stateless macaroon
(`lib/taskweft_deploy/macaroon.ex`) — no DB or volume; nothing is lost on a
scale-to-zero restart.

## Connect

`https://taskweft-mcp.fly.dev/` is a static landing page, not the MCP
endpoint — that's `/mcp`:

```json
{ "mcpServers": { "taskweft": { "type": "http", "url": "https://taskweft-mcp.fly.dev/mcp" } } }
```

No header needed — the client discovers and drives the OAuth flow (GitHub
sign-in) itself. Access is gated by `TASKWEFT_MCP_GH_ALLOW` (Fly env): a
comma list of GitHub logins and/or `@org` public memberships. Requested scope
is `read:user,user:email` only — never `read:org`.

## Deploy

CI (`.github/workflows/deploy.yml`) deploys on push to `main` via the
`FLY_API_TOKEN` repo secret. Manual: `fly deploy`.

Fly app secrets (never in git): `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET`
(callback `https://taskweft-mcp.fly.dev/oauth/callback`) and
`TASKWEFT_TOKEN_SECRET` (the macaroon root key — keep it stable; rotating it
invalidates every outstanding token).

## Local test

```sh
podman build -t taskweft-mcp -f Containerfile .
podman run --rm -p 8080:8080 -e TASKWEFT_TOKEN_SECRET=devkey... taskweft-mcp
curl -s localhost:8080/health                                                # ok
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/                      # 200 (landing page)
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/mcp -d '{}'   # 401
```

A full sign-in round-trip needs a real GitHub OAuth App — GitHub is the
identity provider, so there's no local stand-in for that leg.
