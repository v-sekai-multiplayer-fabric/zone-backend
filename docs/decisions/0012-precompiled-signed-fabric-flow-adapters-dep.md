---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: ideation
discussion: N/A — no PR yet, idea only
labels: hrr, tagging, idtxcli
---

# 0012 Fetch fabric-flow-adapters as a precompiled, signature-verified Mix dependency

## Context

`idtxcli` (in `v-sekai-multiplayer-fabric/fabric-flow-adapters`, a C++/SCons
GDExtension project, default branch `main-fabric`) currently has no
Elixir-facing package and **no published GitHub releases** — nothing
built and signed to depend on yet. Today's plan (see
[[0004-idtxcli-tag-manifest-heuristics]]) is to shell out to it from
inside the baker Docker container. The idea floated this session: skip
the Docker shell-out and have `zone-backend` depend on it directly as
a Mix dependency that downloads a precompiled, signature-verified
native build — the same shape as `rustler_precompiled` — rather than
building `fabric-flow-adapters` from source (~40 min OpenUSD build) on
every deploy.

## Decision Outcome

Not yet decided — this is a placeholder capturing the direction, not
an actioned choice. Blocking prerequisites before it can become a real
decision: (1) `fabric-flow-adapters` needs to actually publish signed
release artifacts (it has none today), and (2) something needs to own
the NIF/FFI boundary — `fine` was named as the binding layer of choice
elsewhere this session (see [[0002-reject-taskweft-nif-for-hrr]]'s
mention of a "fine-based NIF"), but no `fine`-based wrapper exists in
either repo yet.

## Consequences

Good (if pursued): no ~40 min OpenUSD SCons build in the deploy path,
no Docker-shell-out latency/plumbing for tag extraction. Bad: adds a
supply-chain dependency on binary artifact signing/verification
infra that doesn't exist yet in this org; `Uro.Tagging` currently
depends on none of this (see [[0006-uro-tagging-module]]), so this
would be new coupling, not a fix to something broken today.

## Confirmation

Not started. `fabric-flow-adapters` has zero releases
(`gh api repos/v-sekai-multiplayer-fabric/fabric-flow-adapters/releases`
returns an empty list) and no `mix.exs`/Elixir package of any kind.
Revisit once a release-and-signing pipeline exists on that repo.
