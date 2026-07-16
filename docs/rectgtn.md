<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# RECTGTN — the planner model behind `plan` / `replan`

**RECTGTN** stands for **R**elationship-**E**nabled **C**apability-**T**emporal
**G**oal-**T**ask-**N**etwork — the HTN (Hierarchical Task Network) planning
model exposed over MCP by the `plan` and `replan` tools.

`priv/schemas/rectgtn_domain.schema.json` is the authoritative shape — every
top-level key a document may use, exhaustively, enforced by
`Taskweft.JSONLD.Loader.validate/2` with `additionalProperties: false`. This
page is prose and rationale on top of it, not a restatement: `@context`,
`@type`, `name` (required), `description`, `version`, `source`, `enums`,
`variables`, `actions`, `methods`, `capabilities`, `todo_list` — see the
schema for each one's exact shape.

## The three task kinds

Everything in a domain's `todo_list` (and in each method's `subtasks`) is one
of three kinds. `todo_list` is GTPyHOP's own term for this exact heterogeneous
list — `find_plan(state, todo_list)` — a name that fits because it mixes
calls, goals, and multigoals, not one uniform thing:

| Kind | JSON-LD form | Meaning |
|------|--------------|---------|
| **`TwCall`** | a call array `[name, arg…]` | name in `actions` → a primitive that runs; name in `methods` → a compound task decomposed via `alternatives` |
| **`TwGoal`** | a `todo_list` entry `{"goal": [{"pointer", "eq"}, …]}` | desired `(pointer, value)` bindings, satisfied via goal methods |
| **`TwMultiGoal`** | a `todo_list` entry `{"multigoal": {…}}` | a set of bindings the planner backjumps over, choosing which to satisfy first |

## `TwCall` — call arrays

```json
{"@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
              "domain": "khr:planning/domain/"},
 "@type": "domain:Definition", "name": "demo",
 "variables": [{"name": "done", "init": {"a": false, "b": false}}],
 "actions": {"do_a": {"params": [], "body": [{"pointer/set": "/done/a", "value": true}]},
             "do_b": {"params": [], "body": [{"pointer/set": "/done/b", "value": true}]}},
 "methods": {"top": {"params": [], "alternatives": [{"name": "seq",
                                                     "subtasks": [["do_a"], ["do_b"]]}]}},
 "todo_list": [["top"]]}
```

Effects use `pointer/set`; guards use `{"eval": {"type": "math/<op>", …}}`.

## `TwGoal` — goals

A conjunction of desired `(pointer, value)` bindings, as a `todo_list` entry —
satisfied by a *goal method*, which is not a distinct concept: it's an
ordinary `methods` entry named after the state var it targets. There's no
separate `goals` key — a goal method (`TwGoalMethodFn`) is mechanically
identical to an ordinary method, invoked as `(state, [key, desired])` the
same way any method is invoked as `(state, args)`:

```json
{"@type": "domain:Definition", "name": "blocks",
 "methods": {"pos": {"params": ["block", "dest"],
                     "alternatives": [{"name": "stack_it", "subtasks": [["stack", "block", "dest"]]}]}}}
```

```json
{"@type": "domain:Problem", "name": "switch_goal",
 "variables": [{"name": "switch", "init": {"x": false}}],
 "todo_list": [{"goal": [{"pointer": "/switch/x", "eq": true}]}]}
```

Because it's an ordinary method, a problem may instead just call it directly
as a `TwCall`: `"todo_list": [["pos", "a", "table"]]`.

## `TwMultiGoal` — multigoals

```json
{"@type": "domain:Problem", "name": "switch_multigoal",
 "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
 "todo_list": [{"multigoal": {"switch": {"x": true, "y": true}}}]}
```

A `todo_list` may freely mix call arrays, goal, and multigoal objects:
`"todo_list": [["move_one", "a", "table"], {"multigoal": {"pos": {"c": "b"}}}]`.

## Relationships and capabilities — one ReBAC graph

RECTGTN's "Relationship-Enabled" and "Capability" are the same engine: a
domain's `capabilities` object is compiled into a ReBAC (Relationship-Based
Access Control) graph — the same graph `Taskweft.ReBAC` (`taskweft_rebac`)
exposes standalone via `Taskweft.rebac_check/5`/`Taskweft.rebac_expand/4` —
and action guards are evaluated against it, so a capability requirement can
be a composed relation expression, not just a direct edge (ADR 0004).

A graph is `{"edges": [{"subject", "rel", "object"}], "definitions": {}}` —
field order matches the canonical Lean model's `⟨subject, RelationType,
object⟩` tuple (`Planner.Capabilities`); JSON keys are looked up by name, not
position, so this is purely for readability/consistency, not a wire format
requirement.
Relations are `HAS_CAPABILITY`, `CONTROLS`, `OWNS`, `IS_MEMBER_OF`,
`DELEGATED_TO`, `SUPERVISOR_OF`, `PARTNER_OF`, `CAN_ENTER`, `CAN_INSTANCE`.

```elixir
graph =
  Taskweft.ReBAC.new_graph()
  |> Taskweft.ReBAC.add_edge("alice", "team_x", "IS_MEMBER_OF")
  |> Taskweft.ReBAC.add_edge("team_x", "resource_1", "OWNS")

Taskweft.ReBAC.check_rel(graph, "alice", "OWNS", "resource_1")
# => true, via the IS_MEMBER_OF -> OWNS chain
```

Relation *expressions* compose beyond a single relation name: `union`,
`intersection`, `difference`, and `tuple_to_userset` (follow a `pivot_rel`
chain, e.g. membership, before checking the inner expression).

## Capabilities and temporal duration

A `TwCall`, `TwGoal`, or `TwMultiGoal` domain may add either or both.

**Capabilities** — a top-level `capabilities` object binds which entities hold
which capabilities, and (optionally) an explicit relationship graph. This is
a dedicated top-level key, not a variable: structured/relational data gets
its own namespaced slot, matching glTF Interactivity's own convention for
extension data that isn't a scalar/vector value socket (e.g.
`KHR_lights_punctual`'s `/extensions/KHR_lights_punctual/lights`).

```json
"capabilities": {
  "entities": {"<entity>": ["<cap>", ...], ...},
  "graph":     {"edges": [...], "definitions": {}}
}
```

`entities` compiles to direct `HAS_CAPABILITY` edges. There is no compiled
sugar for action requirements: write the guard directly into the action's
own body as an ordinary `{"eval": {"type": "rebac/check", "rel": <relation>,
"subject": <ref>, "object": <cap>}}` step — the same mechanism every other
action precondition already uses. An agent qualifies if it's a *member of a
team* that holds the capability, not just a direct holder, by expressing
`rel` as a relation expression rather than a bare name:

```json
"capabilities": {
  "graph": {"edges": [{"subject": "alice", "rel": "IS_MEMBER_OF", "object": "flight_team"},
                      {"subject": "flight_team", "rel": "HAS_CAPABILITY", "object": "fly"}]}
},
"actions": {
  "a_fly": {"params": ["agent"],
            "body": [{"eval": {"type": "rebac/check", "rel": "HAS_CAPABILITY",
                                "subject": "{agent}", "object": "fly"}},
                      {"pointer/set": "/loc/{agent}", "value": "..."}]}
}
```

An action only applies to an agent for whom the guard holds; the planner
tries the next alternative otherwise (or reports no plan if none qualify).

**Temporal duration** — any action may carry `"duration": "<ISO 8601>"` (e.g.
`"PT5M"`); actions without one default to `"PT0S"`. Every `plan` response
includes a `"temporal"` block computed from these durations, with no separate
call needed:

```json
{"plan": [["a_fly", "drone_1", "city"]],
 "temporal": {"consistent": true, "origin": "PT0S", "total": "PT5M",
              "steps": [{"action": "a_fly", "duration": "PT5M", "start": "PT0S", "end": "PT5M"}]}}
```

## Soundness contract

Replanning a returned plan with `fail_step == -1` reports the whole plan
complete:

```elixir
{:ok, plan_json} = Taskweft.plan(domain_json)
{:ok, out}       = Taskweft.replan(domain_json, plan_json, -1)
env = Jason.decode!(out)
env["fail_step"]       == -1
env["completed_steps"] == length(Jason.decode!(plan_json))
```

## See also

- [ADR 0001](https://github.com/taskweft/taskweft/blob/main/docs/adr/0001-gltf-interactivity-node-shape.md) — the action-body node shape (`eval` + `pointer/set`).
- [ADR 0002](https://github.com/taskweft/taskweft/blob/main/docs/adr/0002-khr-interactivity-tier1-node-conventions.md) — the glTF Interactivity node catalog conventions.
- [ADR 0003](https://github.com/taskweft/taskweft/blob/main/docs/adr/0003-khr-interactivity-tier2-execution-strategy.md) — the planned flow-graph execution engine.
- [ADR 0004](https://github.com/taskweft/taskweft/blob/main/docs/adr/0004-unify-domain-capabilities-with-rebac-graph.md) — unifying domain capabilities with the ReBAC relation-expression engine (issue #96).
