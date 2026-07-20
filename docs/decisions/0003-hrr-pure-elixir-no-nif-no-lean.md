---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: hrr
---

# 0003 HRR tagging implemented as pure Elixir, no NIF, no Lean, no s7

## Context

HRR (circular-convolution bind/unbind, additive bundle, cosine-sim
cleanup) needed a home in `zone-backend` for `Uro.Tagging`. This went
through several homes this session: a new Lean4 module in
`openusd-fabric` (see [[0001-real-hrr-lean-module-no-shared-r128]]),
then a proposal to call `taskweft`'s existing `Taskweft.NIF` HRR
directly (rejected, see [[0002-reject-taskweft-nif-for-hrr]]), then
a proposal to migrate the algorithm into `weft-warp-loop`'s s7 stack.

## Decision Outcome

Chosen: **pure Elixir**, no cross-language boundary at all —
`lib/uro/hrr.ex` implements the same algorithm (circular convolution
bind, correlation unbind, additive bundle, cosine similarity) directly,
with plain floats instead of `Fabric.HRR.lean`'s fixed-point `Int`
scaling. No NIF to build/link, no Lean, no s7 port. `Fabric.HRR.lean`
remains a real, independently-verified artifact but is no longer on
`zone-backend`'s critical path.

## Consequences

Good: zero build/link complexity for this repo, no new native
dependency, easiest to test and iterate on. Bad: float nondeterminism
(acceptable for a recommendation feature, not for anything requiring
bit-exact reproducibility); leaves two parallel, non-code-shared HRR
implementations (Lean and Elixir) to keep conceptually in sync if the
algorithm ever changes.

## Confirmation

`lib/uro/hrr.ex` parses clean under `elixir -e Code.string_to_quoted!`.
Full `mix compile` blocked by an unrelated pre-existing gap
(`bcrypt_elixir` needs `nmake`/MSVC, not installed on this machine) —
not caused by this change. End-to-end verification against
`Uro.Tagging` not yet run.
