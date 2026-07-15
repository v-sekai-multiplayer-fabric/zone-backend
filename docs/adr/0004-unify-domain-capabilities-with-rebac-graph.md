# Unify domain `capabilities` with the ReBAC relation-expression engine

- Status: accepted (design only — not yet implemented)
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

Concretely (not yet implemented):

- **Domain shape**: `capabilities` gains an optional `"graph"` key (the same
  `{"edges": [...], "definitions": {...}}` wire format `Taskweft.ReBAC`
  already uses) and lets `"actions"` entries be either the existing bare
  capability-name-list (sugar for direct `HAS_CAPABILITY` edges) or a full
  relation-expression object (`{"type": "union", ...}`).
- **Loader** (`tw_loader.hpp`): stop pre-flattening into `_cap_*` booleans.
  Instead, parse the optional graph + per-action expression and store them
  on the domain; expand the flat sugar shape into an equivalent graph +
  `base` expression at load time so both shapes reach the planner in one
  representation.
- **Planner** (`tw_planner.hpp`): action guards call into `tw_rebac.hpp`'s
  expression evaluator (already used by `Taskweft.ReBAC.check/5`) at
  guard-check time against the domain's graph, instead of reading a
  precomputed boolean.
- **Validator** (`lib/taskweft/jsonld/loader.ex`): extend `check_capabilities`
  to accept the new `"graph"` key and either shape for `"actions"` entries.
- **`taskweft_rebac`**: no interface change needed — the planner becomes a
  new caller of the existing `check/5`, not a reason to change its API.

### Consequences

- Good: one authorization model instead of two; a domain can express
  transitive/composed capability requirements without inventing new syntax.
- Good: existing bundled domains keep working unchanged (flat shape is sugar
  for the simple case, not removed).
- Bad: touches the C++ planner's guard-evaluation path, the loader's domain
  representation, and the JSON-LD validator — a real cross-cutting change,
  not a quick patch. Sequence after other in-flight NIF work (KHR
  Interactivity Tier 1/2, ADR 0002/0003) rather than interleaving.
- Open, deliberately not resolved here: whether the `"graph"` key lives
  inline in the domain JSON-LD or is referenced separately (e.g. loaded from
  `taskweft_plans` alongside the domain) — a real design question for
  whoever implements this, not to be guessed now.

## More Information

Tracked as taskweft/taskweft#96. Not yet implemented as of this ADR.
