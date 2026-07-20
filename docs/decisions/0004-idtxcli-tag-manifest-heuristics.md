---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: tagging, idtxcli
---

# 0004 idtxcli bake tag manifest — heuristics local to the CLI adapter, no new schema code

## Context

zone-backend's asset pipeline needs semantic tags (avatar type, rig
style, viseme support, etc.) for HRR-based similarity search
([[0006-uro-tagging-module]]). The original plan assumed new USD
schema-validation code was needed to extract them. Canonical record
lives in
`multiplayer-fabric-manuals/decisions/20260720-idtxcli-tag-manifest-heuristics.md`
(sibling `fabric-flow-adapters` repo); this is a same-day backfill so
zone-backend has a local pointer to where its tag inputs come from.

## Decision Outcome

Chosen: derive all tags from `idtx_core`'s already-parsed
`idtx_avatar_t` (skeleton bone names, blendshape names,
`idtx_material_is_mtoon`, spring chain count) via small heuristics
written directly in `fabric-flow-adapters/flow/adapters/cli/idtxcli.cpp`,
added as `--tags-source`/`--tags-out` on the existing `bake`
subcommand. No reach into `idtx_core/internal/` headers — that would
cross the hexagonal adapter/core boundary.

## Consequences

Good: zero new schema-plugin work, respects the port/adapter boundary.
Bad: `skeleton_style`/`avatar_type` are heuristic, not schema-exact —
acceptable for a recommendation tag, not for anything requiring
precision.

## Confirmation

`clang++ -std=c++17 -fsyntax-only -Wall -Wextra` against the real
`flow/ports/include`/`flow/core/include` headers: zero errors, zero
warnings, in `fabric-flow-adapters`. Full link (needs the OpenUSD
build, ~40 min) not yet run; not yet linked into any zone-backend bake
call.
