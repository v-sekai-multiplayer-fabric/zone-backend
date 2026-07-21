---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: hrr, migration, repo-structure
---

# 0015 Extract Taskweft.ReBAC and WeftWarpBurrito.Sandbox into lib/

## Context

`Uro.ReBAC.TaskweftAdapter`/`Uro.Planner.TaskweftAdapter` (see
[[0006-uro-tagging-module]]) call `Taskweft.ReBAC`/`Taskweft.NIF`, which
turned out not to live in the `taskweft/` subtree vendored per
[[0014-vendor-taskweft-and-weft-warp-burrito-as-subtrees]] — they live in
two small, separate upstream repos, `taskweft/rebac` (7KB, pure Elixir) and
`taskweft/nif` (238KB, C++ NIF). Everything else in `taskweft/` (CLI, MCP
server, OAuth deploy router, JSON-LD loader, a 115MB vendored glTF spec) is
unrelated to what this repo actually calls.

## Decision Outcome

Vendored `taskweft_rebac`/`taskweft_nif` as fresh top-level subtrees, then:

- Moved `Taskweft.ReBAC` (71 lines, pure Elixir) into `lib/taskweft/rebac.ex`.
- Moved `WeftWarpBurrito.Sandbox` (73 lines, plain `GenServer`, no native
  loading) into `lib/weft_warp_burrito/sandbox.ex`.
  `WeftWarpBurrito.SandboxNif` (the `@on_load` module bound to
  `:code.priv_dir(:weft_warp_burrito)`) stays in the `weft_warp_burrito`
  dependency — a NIF loader can't move to a different app without also
  moving its native build step.
- `mix.exs`: `{:taskweft, path: "taskweft"}` → `{:taskweft_nif, path: "taskweft_nif"}`
  (always-compiled, like `apps/uro_loop` — no CI gating needed:
  `taskweft_nif`'s own `mix.exs` requires only `elixir: "~> 1.17"` and falls
  back to plain `make` on non-Windows, unlike `weft_warp_burrito`'s hardcoded
  `mingw32-make`/`elixir ~> 1.20`).
- Deleted `taskweft/` and `taskweft_rebac/` (fully absorbed) once nothing
  referenced them.

## Consequences

Good: `Uro.ReBAC.TaskweftAdapter`/`Uro.Planner.TaskweftAdapter`'s actual
implementation now lives directly in this repo, editable in place, with no
unused CLI/MCP/OAuth/glTF-spec bulk along for the ride.

Bad: `taskweft_rebac`'s moved file exposes a richer API than
`Uro.Ports.ReBAC` declares (`check/5`, `expand/4`, `parse_relation_edges/2`,
none currently called) — dead code from this repo's point of view, kept
verbatim rather than trimmed to avoid touching logic during a pure move.

## Confirmation

`elixir -e Code.string_to_quoted!` and `mix format --check-formatted` pass
on both moved files and `mix.exs`. `mix deps.get` resolves cleanly (bumped
`elixir_make` 0.9.0 → 0.10.0 to satisfy both `taskweft_nif`'s `~> 0.9` and
`weft_warp_burrito`'s `~> 0.8`). `CI=true MIX_ENV=dev mix deps.compile`
confirms `weft_warp_burrito` is still skipped entirely. `taskweft_nif`'s own
build not exercised locally — blocked by the pre-existing, unrelated
`bcrypt_elixir`/`nmake` gap that stops the compile chain first
alphabetically; relying on CI.
