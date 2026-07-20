# KHR_interactivity Tier 1 node catalog: decompose-first, and a b-selector convention for multi-output nodes

- Status: accepted
- Date: 2026-07-14
- Deciders: K. S. Ernest (iFire) Lee
- PRs: taskweft-nif #8, #9 · taskweft #83

## Context and Problem Statement

`taskweft_nif` implements 68 of the ~130 KHR_interactivity node types (see
`thirdparty/gltf_interactivity/02_node_types.md`) as `eval`-node value
computations in `tw_loader.hpp`'s `kNodeTypes()` table, per ADR 0001's node
shape. The remaining catalog splits into two tiers:

- **Tier 1** (~26 nodes): pure value computation, additive to the existing
  `eval_node()`/`kNodeTypes()` machinery, no execution-model change.
- **Tier 2** (~22 nodes): `flow/*`, `event/*`, `animation/*`, and
  `pointer/interpolate`/`variable/interpolate` — needs a new flow-graph
  execution engine (tracked separately; see the forthcoming Tier 2 ADR).

This ADR covers two recurring design questions that came up implementing
Tier 1's first two milestones and will recur through the rest of it:

1. Should every node get a bespoke C++ implementation, or should compound
   nodes reuse existing simpler primitives where the spec permits it?
2. `kNodeTypes()`'s calling convention passes exactly one `TwValue` in and
   one out (`fn(a,b,c,d) -> TwValue`). Several remaining nodes need more than
   4 named inputs, a non-value configuration field, or more than one logical
   output (e.g. `math/matDecompose` producing translation/rotation/scale).
   What's the consistent shape for those?

## Decision Drivers

- Reuse already-tested primitives instead of duplicating logic (explicit
  project guidance, referencing the `plausible-witness-dag` "decompose and
  verify the decomposition" pattern used elsewhere in this repo).
- Keep new node additions mechanical and low-risk — most of Tier 1 should be
  drop-in table entries, not one-off structural special cases.
- Don't add a new "returns a dict"/multi-value convention if an existing
  pattern already covers it.

## Decision Outcome

**1. Decompose before implementing a new primitive.** Before adding a new
opcode, check whether the node is *defined by the spec itself* in terms of
already-implemented operations, and if so inline that formula directly rather
than introducing new algebra:

- `math/smoothStep` — spec defines it via `math/min` + `math/saturate`;
  implemented as one table entry inlining that formula (matches how
  `quatMul` etc. already inline their own component math rather than
  recursively dispatching into the table).
- `math/extract2x2/3x3/4x4` — matrices are flat row-major `TwValue::Array`s
  (no new vector/matrix type was introduced — `ARRAY` already stands in for
  float2/3/4/quat/matrix via runtime `.size()` checks), so these are
  byte-identical to the existing `extract2/3/4` lambda, just registered
  under more table keys.
- Only genuinely irreducible operations (real trigonometry, base arithmetic,
  true linear/quaternion algebra) get new from-scratch implementations.

Before writing the C++ for a node with non-obvious numeric properties
(`smoothStep`'s range, `rotate2D`'s length-preservation), write a Lean
reference model first and witness-certify the invariants via
`plausible-witness-dag` (see `lean/KHRTier1Witness.lean`), *then* implement
the C++ and cross-check against it. Not required for mechanical
decompositions with no numeric subtlety (e.g. the `combine`/`extract`
family, `quatFromAngles`'s composition — those were cross-checked directly
against existing table entries in the Elixir test suite instead).

**2. Structural nodes for >4 inputs or configuration fields.** When a node
needs more than the `(a,b,c,d)` table slots, or reads a non-value
configuration field (a string, not an expression), it becomes a new `if`
block in `eval_node()` with direct access to the full expression dict —
the same treatment `select`/`switch`/`clamp`/`mix` already get:

- `math/combine3x3` (9 inputs), `math/combine4x4` (16 inputs) — read
  `a`..`i` / `a`..`p` directly via the existing `get()` closure.
- `math/quatFromAngles` — reads a `"configuration": {"order": "..."}` field
  directly from `expr`, the same way `math/switch` reads `"selection"`.

**3. `b`-selector convention for multi-output nodes.** Rather than introduce
a new "node returns a `TwValue::Dict`" convention, a node with N logical
outputs takes an extra `b` index argument selecting which output to return,
consistent with how `extract2/3/4` already use `b` as an index into an
array. This applies going forward to `math/matDecompose` (`b`=0/1/2 →
translation/rotation/scale), `math/quatToAxisAngle` (`b`=0/1 → axis/angle),
and `math/rgbToOkLCh`/`math/rgbFromOkLCh` (`b`=0/1/2 → component). Not yet
implemented as of this ADR — recorded here so milestone 4 follows the same
shape rather than re-litigating it per node.

### Consequences

- Good: most Tier 1 nodes are pure drop-in table entries; only a handful
  need `eval_node()` structural treatment, and none need a `TwValue` type
  change.
- Good: the decompose-first + Lean-witness pattern caught the right level of
  rigor — full formal verification for numerically subtle nodes, direct
  cross-checks for mechanical ones — without over-investing in either.
- Neutral: the `b`-selector convention means multi-output nodes cost one
  extra evaluation per output requested (no shared computation across
  outputs of the same call) — acceptable since Tier 1 nodes are pure and
  cheap to recompute, and matches the existing `extract*` precedent exactly.

## More Information

Tracking: milestones 1-2 merged (taskweft-nif #8, #9); milestones 3
(`transform`, `rotate3D`, vector `slerp`, `transpose`/`determinant`/
`inverse`/`matMul`/`matCompose`), 4 (the `b`-selector nodes above,
`quatFromDirections`/`quatFromUpForward`), and 5 (`variable/get`/`set`,
`debug/log` — these touch `load_domain()`/`build_action()` signatures, not
just `kNodeTypes()`) are not yet implemented.
