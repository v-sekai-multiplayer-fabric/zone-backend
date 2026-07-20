---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: committed
discussion: N/A — committed directly to main, no PR review
labels: hrr, lean
---

# 0001 Real HRR as a new Lean4 module in openusd-fabric, without the shared r128 library

## Context

Asset recommendation needed a tagging scheme that works with very
little data per asset. `weft-warp-loop`'s only existing "HRR"
(`taskweft-hrr.shrub`) is fake: bind/unbind are plain +/-, not
convolution/correlation, so it has superposition but not binding's
dissimilarity property. Canonical record lives in
`multiplayer-fabric-manuals/decisions/20260720-real-hrr-lean-module-no-shared-r128.md`
(sibling org repo); this is a same-day backfill so zone-backend has a
local pointer to the decision chain that led to
[[0003-hrr-pure-elixir-no-nif-no-lean]].

## Decision Outcome

Chosen (at the time): a real HRR/VSA module (circular-convolution
bind, correlation unbind, additive bundle, cosine-sim cleanup) in
`openusd-fabric/lean/Fabric/HRR.lean`, using `Int`-scaled fixed-point,
not the org's r128 library — confirmed not to exist as an importable
Lean package anywhere yet. Building r128 first was rejected as
out-of-scope scope creep.

## Consequences

Good: real binding semantics, deterministic, no floats, no new
external dependency, and the module is real and independently
verified. Bad: **superseded for zone-backend's purposes** — see
[[0003-hrr-pure-elixir-no-nif-no-lean]] for the final call to not use this
module (or any NIF) from this repo. `Fabric.HRR.lean` still stands as
a correct, verified artifact in `openusd-fabric`, just off this app's
critical path.

## Confirmation

5 Plausible property tests pass in `openusd-fabric`. Measured at
hrrDim=512: round-trip cosine-sim 0.675, bind-orthogonality
-0.06/-0.03, bundling capacity 129 atoms.
