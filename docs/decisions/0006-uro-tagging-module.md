---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: tagging
---

# 0006 Uro.Tagging as the asset-tagging entry point, calling Uro.Hrr directly

## Context

Asset recommendation needs a tag/derive-and-persist entry point that
sits between `Uro.SharedContent`'s upload/bake pipeline and the HRR
math itself (see [[0003-hrr-pure-elixir-no-nif-no-lean]]).

## Decision Outcome

Chosen: a single `Uro.Tagging` module exposing `tag_asset/2` (derive a
tag vector for a `SharedFile` and persist it) and `similar_assets/2`
(query nearest neighbors), calling `Uro.Hrr` directly with no
intermediate abstraction layer or behaviour.

## Consequences

Good: minimal indirection — one obvious call site for the baker
callback to wire into ([[0011-fly-redeploy-scope-uro-and-crdb-only]]'s
follow-on work item F, still open). Bad: couples `Uro.Tagging` to
`Uro.Hrr`'s current function signatures directly; swapping the HRR
implementation later means editing `Uro.Tagging`, not a config/adapter
change.

## Confirmation

`lib/uro/tagging.ex` parses clean under `elixir -e
Code.string_to_quoted!`. Not yet wired into
`Uro.SharedContent.spawn_baker/1`, and not yet exercised end-to-end
(blocked on the `bcrypt_elixir`/`mix compile` environment gap noted in
the HRR MADR).
