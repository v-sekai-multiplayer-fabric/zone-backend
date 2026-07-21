---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: hrr, migration, repo-structure
---

# 0014 Vendor taskweft and weft-warp-burrito as full-history git subtrees

## Context

Both `taskweft` (`taskweft/taskweft` on GitHub — the real, current location;
`V-Sekai-fire/multiplayer-fabric-taskweft` redirects there) and
`weft-warp-burrito` (`weftspun/weft-warp-burrito`) were plain remote `github:`
Mix dependencies in `mix.exs` (see [[0010-generate-secrets-submodule-to-subtree]]
for the same pattern applied to a smaller repo, and
[[0013-slow-migration-taskweft-to-weft-warp-burrito]] for the migration plan
these two dependencies serve).

## Decision Outcome

Vendored both as full-history git subtrees at repo root (`taskweft/`,
`weft_warp_burrito/`, same technique as
[[0010-generate-secrets-submodule-to-subtree]]), and repointed `mix.exs` at
them via `path:` deps instead of `github:` deps — `taskweft` as a normal,
always-compiled path dependency (same treatment as `apps/uro_loop`);
`weft_warp_burrito` keeping its existing `CI=true`-gated
`only: :dev, runtime: false` treatment, since its own `mix.exs` still
requires `mingw32-make`/Elixir `~> 1.20`.

## Consequences

Good: both dependencies' source now lives directly in `zone-backend`,
editable in place, no separate checkout needed to read or patch either.
Bad: **substantial repo size growth** — `taskweft/` is 117MB,
`weft_warp_burrito/` is 10MB, `.git` grew to 89MB. `taskweft`'s own
dependency tree (via `oauth_mcp_bridge`) required `req ~> 0.6`, forcing an
unlock/upgrade of the previously-pinned `req 0.5.17` (satisfied only by
`burrito`'s looser `>= 0.5.0`) — a real, if minor, version-resolution
change rippling from vendoring, not just a mechanical move.

A `git subtree add` merge artifact: the two subtree-add commits corrupted
the root `mix.exs` via git's rename-detection matching it against the
vendored repos' own root `mix.exs` files during the non-squash merge —
silently reverting the CI-gating fix from
[[0003-hrr-pure-elixir-no-nif-no-lean]]'s branch of work and duplicating a
dependency entry. Caught by diffing against the pre-merge commit before
building on top of it. Worth remembering for any future subtree add of a
repo that also happens to have a same-named file at its root.

## Confirmation

`mix deps.get` resolves cleanly after `mix deps.unlock req` (taskweft's own
`oauth_mcp_bridge ~> req 0.6` requirement). `mix.exs` is `mix format`-clean.
`CI=true MIX_ENV=dev mix deps.compile` confirmed no `weft_warp_burrito`/
`burrito`/`mingw32-make` output — the CI exclusion still holds through the
path-dependency change. Full `mix compile`/`mix test` not run locally,
blocked by the pre-existing `bcrypt_elixir`/`nmake` gap; relying on CI.
