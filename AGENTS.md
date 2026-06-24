# AGENTS.md — multiplayer-fabric-zone-backend

Uro — Phoenix/Elixir backend for zone registration, asset management, and
authentication. Deployed on Fly.io as `multiplayer-fabric-uro`.

## Fly.io deployment

| URL | Notes |
|-----|-------|
| `https://multiplayer-fabric-uro.fly.dev` | Fly default hostname |
| `https://hub.chibifire.com` | Public alias (Cloudflare proxied) |
| `https://hubaf2f.chibifire.com` | Machine-specific alias (MAC suffix af2f) |
| `https://bake.chibifire.com` | Baker posts results here (same app) |

**App name:** `multiplayer-fabric-uro` — `flyctl` commands use `--app multiplayer-fabric-uro`.

### Required Fly secrets

| Secret | Purpose |
|--------|---------|
| `DATABASE_URL` | `postgresql://gateway_writer@multiplayer-fabric-crdb.internal:26257/uro?sslmode=verify-full` |
| `MIGRATION_DATABASE_URL` | `postgresql://gateway_admin@...` (DDL-capable) |
| `CRDB_CA_CRT` | CA cert content (written to disk by scripts/fly-start.sh) |
| `CRDB_CLIENT_WRITER_CRT` | gateway_writer client cert |
| `CRDB_CLIENT_WRITER_KEY` | gateway_writer client key |
| `CRDB_CLIENT_ADMIN_CRT` | gateway_admin client cert (for migrations) |
| `CRDB_CLIENT_ADMIN_KEY` | gateway_admin client key |
| `PHOENIX_KEY_BASE` | 64-byte secret key base |
| `JOKEN_SIGNER` | JWT signing key |
| `SIGNUP_API_KEY` | Client signup API key |
| `LOOP_API_KEY` | Loop-server profile commit API key (`POST /api/v1/loop/commit`) |

### Database role separation (ReBAC)

- `Uro.Repo.Migration` — connects as **gateway_admin** (DDL privilege: CREATE, ALTER, DROP)
- `Uro.Repo` — connects as **gateway_writer** (DML only: SELECT, INSERT, UPDATE, DELETE)

Migrations run at startup via `scripts/fly-start.sh` with the admin repo.
The app serves requests via the writer repo.

### Startup script

`scripts/fly-start.sh`:
1. Writes cert content from Fly secrets (`CRDB_CA_CRT` etc.) to `/tmp/crdb_certs/`
2. Sets `CRDB_CA_CERT`, `CRDB_CLIENT_CERT`, `CRDB_CLIENT_KEY`, `CRDB_ADMIN_CERT`, `CRDB_ADMIN_KEY`
3. Runs `mix ecto.migrate --repo Uro.Repo.Migration` (as gateway_admin)
4. Starts `phx.server` (as gateway_writer)

### Deploy

```bash
gh workflow run deploy.yml --repo V-Sekai-fire/multiplayer-fabric-zone-backend
```

### Known quirks

- `Helpers.get_env/2` uses `@compile_phase?` baked at build time — env vars for
  non-nil defaults must be set as Fly secrets, not inferred from the example values.
- `socket_options: [:inet6]` is required — Fly `.internal` DNS returns IPv6 only.
- `prepare: :unnamed` avoids statement-cache exhaustion on single-node CockroachDB.

---

Guidance for AI coding agents working in this submodule.

## Commit message style

Sentence case, imperative verb, no Conventional Commits prefix, under 72
characters. See the root `AGENTS.md` for examples.

## Test commands

```sh
mix test                           # unit tests
mix test --only prod               # integration tests (requires live stack)
mix credo --min-priority high      # linting
mix format --check-formatted       # formatting
```

Integration tests require a running stack (`docker compose up -d` in
`multiplayer-fabric-hosting/`) and these env vars:

```sh
DATABASE_URL=postgresql://root@localhost:26257/vsekai?sslmode=disable
AWS_S3_BUCKET=uro-uploads
AWS_S3_ENDPOINT=http://localhost:7070
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
```

(Zone-console client env vars — `URO_BASE_URL`, `URO_EMAIL`, `ZONE_CERT_HASH_B64`,
etc. — belong in `multiplayer-fabric-zone-console/AGENTS.md`.)

## Red-green-refactor

1. **RED** — write a failing test with a specific, load-bearing error message.
   Briefly break the assertion to confirm the failure is not vacuous.
2. **GREEN** — write the minimum code to pass the test. No extra abstractions.
3. **REFACTOR** — clean up with tests still green. One commit per cycle.

The TDD arc must be legible in `git log`.

## Elixir conventions

- Use PropCheck generators rather than mocks.
- Functions return `{:ok, value}` / `{:error, reason}` at every boundary.
  `raise` is for programmer errors (wrong type, missing config at boot),
  never for runtime conditions.
- Migrations are forward-only. Once merged to main, never alter a migration.
  Every migration must include a `down/0`. Generate with:
  ```sh
  mix ecto.gen.migration <name>
  ```
  Then add the SPDX header manually (the generator does not add it and the
  pre-commit hook will reject the file without it — see SPDX requirement below).

## SPDX requirement

Every new first-party `.ex` or `.exs` file must contain both of these lines
in the first 2 KB:

```elixir
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
```

This is enforced by `scripts/check_spdx.py` via the pre-commit hook. Files
missing either line will block the commit. Generated files (`mix ecto.gen.migration`,
`mix phx.gen.*`) need the header added manually before staging.

## Asset implementation cycles

| Cycle | Feature | Status |
|-------|---------|--------|
| 1 | `UroClient.login/3` | done |
| 2 | `UroClient.upload_asset/3` — chunk → VersityGW → uro manifest | done |
| 3 | `UroClient.get_manifest/2` | done |
| 4 | `CMD_INSTANCE_ASSET` wire encoding (100-byte packet) | done |
| 5 | `instance` console command — sends packet to zone server | done |
| 6 | Asset baker — Docker `editor=yes`, casync `.caidx` output | done |
| 7 | Zone orchestrator — Docker `editor=no` zone server lifecycle, port pool UDP 7443–7542 | planned |
| 8 | Godot zone handler — authority zone runs instance pipeline | planned |
| 9 | Round-trip smoke test — upload → instance → entity list on prod | planned |
| 10 | Two-user co-presence — second client connects, observes entity from first client | planned |
| 11 | Multi-platform verification — macOS + Linux + Windows, AccessKit | planned |

## PoC runbook (cycles 9–10)

Prerequisites: stack running (`docker compose up -d`), two terminals,
`zone_console` binary built (`mix escript.build` in
`multiplayer-fabric-zone-console/`).

**Terminal 1 — User A:**

```sh
> login
Username/email: user-a@example.com
Password: ****
Logged in as user-a

> upload path/to/avatar.tscn
Uploaded avatar.tscn as <ASSET_ID>

> bake-status <ASSET_ID>
Baking... (polling every 2 s)
Baked. baked_url = http://versitygw:7070/uro-uploads/<ASSET_ID>.caidx

> join 0
Joined zone 0 at zone-700a.chibifire.com:7443

> instance <ASSET_ID> 0.0 1.0 0.0
Instance request sent

> entities
[zone 0]  id=42  pos=(0.00, 1.00, 0.00)  type=scene  asset=<ASSET_ID>
```

Entity appears → cycle 9 proved.

**Terminal 2 — User B:**

```sh
> login
Username/email: user-b@example.com
Password: ****
Logged in as user-b

> join 0
Joined zone 0 at zone-700a.chibifire.com:7443

> entities
[zone 0]  id=42  pos=(0.00, 1.00, 0.00)  type=scene  asset=<ASSET_ID>
```

Same entity visible to User B → cycle 10 proved. Minimal V-Sekai PoC complete.

**Monitoring:**

```sh
docker logs <baker-container-id>

docker exec multiplayer-fabric-hosting-crdb-1 \
  /cockroach/cockroach sql --insecure \
  -e "SELECT id, baked_url IS NOT NULL FROM vsekai.shared_files \
      ORDER BY inserted_at DESC LIMIT 5;"

nc -u -w2 zone-700a.chibifire.com 7443 && echo "UDP open"
```
