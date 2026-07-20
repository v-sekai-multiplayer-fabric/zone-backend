<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# Hosted MCP server (deploy/)

Hosted **Taskweft MCP server**: `https://taskweft-mcp.fly.dev`, the
`taskweft_deploy` release target of this repo's own `mix.exs` (source:
`lib/taskweft_deploy/`). Wraps `Taskweft.MCP.Server` behind an OAuth 2.1 →
GitHub login bridge (GitHub isn't itself an MCP-compliant authorization
server, so this app is the bridge) via `oauth_mcp_bridge`. Every OAuth
artifact is a self-owned, stateless macaroon — no DB or volume; nothing is
lost on a scale-to-zero restart.

This `deploy/` directory holds only the container build recipe
(`Containerfile`) and a local-test quadlet unit (`taskweft-mcp.container`) —
not a separate Mix project. `fly.toml` (repo root) builds `deploy/Containerfile`
against the whole repo as its context.

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

CI (`.github/workflows/fly-deploy.yml`) deploys on push to `main` touching
`lib/**`, `mix.exs`, `mix.lock`, `deploy/**`, or `fly.toml`, via the
`FLY_API_TOKEN` repo secret. Manual: `fly deploy` from the repo root.

Fly app secrets (never in git): `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET`
(callback `https://taskweft-mcp.fly.dev/oauth/callback`) and
`TASKWEFT_TOKEN_SECRET` (the macaroon root key — keep it stable; rotating it
invalidates every outstanding token).

## Local test

From the repo root:

```sh
podman build -t taskweft-mcp -f deploy/Containerfile .
podman run --rm -p 8080:8080 -e TASKWEFT_TOKEN_SECRET=devkey... taskweft-mcp
curl -s localhost:8080/health                                                # ok
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/                      # 200 (landing page)
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/mcp -d '{}'   # 401
```

A full sign-in round-trip needs a real GitHub OAuth App — GitHub is the
identity provider, so there's no local stand-in for that leg.

`deploy/taskweft-mcp.container` is a Podman Quadlet unit for testing under
WSL/systemd instead: `cp deploy/taskweft-mcp.container ~/.config/containers/systemd/`
then `systemctl --user daemon-reload && systemctl --user start taskweft-mcp`.
