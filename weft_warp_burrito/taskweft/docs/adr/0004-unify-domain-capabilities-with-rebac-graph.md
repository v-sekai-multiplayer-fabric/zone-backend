# Unify domain `capabilities` with the ReBAC relation-expression engine

- Status: accepted, implemented (taskweft-nif#15, taskweft#96 followups)
- Date: 2026-07-15
- Deciders: K. S. Ernest (iFire) Lee

## Context and Problem Statement

RECTGTN's `C` (Capability) and `R` (Relationship) are documented as one
coherent concept (`docs/rectgtn.md`), but the implementation is two
disconnected mechanisms:

- A plan domain's `capabilities` object (`{"entities": {...}, "actions":
  {...}}`) is flattened at domain-load time into boolean state variables
  (`_cap_<capability>[entity] = true`, `tw_loader.hpp` lines ~925-956) and
  checked as simple guards during planning. There is no relationship graph,
  no transitive membership, no expression composition — just a flat
  entity→capability→bool lookup table baked in once at load time.
- `Taskweft.ReBAC` (`taskweft_rebac`, wrapping `tw_rebac.hpp`) is a real
  relationship graph engine: edges (`subject`-[`rel`]->`object`), transitive
  `IS_MEMBER_OF` expansion, and composable relation expressions (`union`,
  `intersection`, `difference`, `tuple_to_userset`). It is invoked only
  directly (`Taskweft.rebac_check/5`, `Taskweft.rebac_expand/4`) — a domain's
  `tasks`/`actions` cannot reference it at all.

The result: a domain author who wants "an agent qualifies for this action if
it directly holds capability X, OR is a member of a team that holds X" cannot
express that — the flat model has no transitivity or composition, and the
graph engine that *does* support it has no hook into action guards.

## Decision Drivers

- RECTGTN's own model (this session's `docs/rectgtn.md`) already claims
  Relationship and Capability are one concept; the implementation should
  match the model, not contradict it.
- `taskweft_rebac`'s relation-expression engine is real and tested — reuse it
  rather than deepen the flat-boolean special case.
- Backward compatibility: existing bundled domains use the flat
  `{"entities": {...}, "actions": {...}}` shape and must keep working.

## Considered Options

1. **Leave both mechanisms as-is.** Document the split (this session already
   did, in the R section of `docs/rectgtn.md`) and accept two parallel
   authorization models.
2. **Unify: let an action's capability requirement be an arbitrary ReBAC
   relation expression, evaluated at guard-time against a graph the domain
   carries or references** — the flat `{"entities": ..., "actions": ...}`
   shape becomes sugar that compiles to the simplest case of this
   (`base` relation, direct edge), not a separate mechanism.
3. **Replace the flat model entirely**, forcing every domain to author full
   relation-expression JSON even for the simple direct-capability case.

## Decision Outcome

Chosen: **option 2**. The flat shape stays as valid, simple-case sugar
(direct `HAS_CAPABILITY` edges, no transitivity needed), but the planner's
guard evaluation goes through the same relation-expression engine
`Taskweft.ReBAC` already implements, so a domain *can* opt into
transitive/composed expressions without a second mechanism being invented.

Implemented as:

- **Domain shape**: `capabilities` gains an optional `"graph"` key (the same
  `{"edges": [...], "definitions": {...}}` wire format `Taskweft.ReBAC`
  already uses, inline in the domain JSON-LD — not referenced separately)
  and lets `"actions"` entries be either the existing bare capability-name
  string (sugar for a direct `HAS_CAPABILITY` edge) or a full
  `{"rel": <relation-expression>, "object": <string>}` requirement.
- **Loader** (`tw_loader.hpp`): stopped pre-flattening into only `_cap_*`
  booleans. `capabilities.entities` now also compiles to `HAS_CAPABILITY`
  edges on a `TwReBAC::TwReBACGraph` (the `_cap_*` state vars are still
  populated too, for introspection/back-compat); the optional `"graph"` key
  merges further edges/definitions into the same graph.
- **Action guards**: turned out to need no `tw_planner.hpp` changes at all —
  `tw_planner.hpp` already treated actions as an opaque `TwActionFn`
  (state-in/state-out), so the guard-evaluation change is entirely inside
  the `TwActionFn`-wrapping closure `tw_loader.hpp` builds per action: it now
  calls `TwReBAC::check_expr` against the compiled `(relation-expression,
  object)` requirements and the domain's graph, instead of reading a
  precomputed boolean.
- **Validator** (`lib/taskweft/jsonld/loader.ex`): `check_capabilities`
  extended to accept the new `"graph"` key and either shape for `"actions"`
  entries.
- **`taskweft_rebac`**: no interface change — the planner became a new
  caller of the existing `check_expr`, not a reason to change its API.

### Consequences

- Good: one authorization model instead of two; a domain can express
  transitive/composed capability requirements without inventing new syntax
  (verified: a transitive team-membership case, impossible under the old
  flat model, now plans correctly — see
  `test/taskweft/capabilities_rebac_test.exs`).
- Good: existing bundled domains keep working unchanged (flat shape is sugar
  for the simple case, not removed) — full test suite (253 tests) passes
  with no regressions.
- Neutral: `tw_planner.hpp` needed zero changes, simpler than this ADR's
  original estimate — the existing opaque-`TwActionFn` boundary already
  isolated guard evaluation inside `tw_loader.hpp`.

## More Information

Tracked as taskweft/taskweft#96. Implemented in taskweft-nif#15 (C++ guard
evaluation) and taskweft#96's own PR (Elixir validator + tests), published as
`taskweft_nif` 0.2.0-dev.1 / `taskweft` 0.4.0-dev.4.
