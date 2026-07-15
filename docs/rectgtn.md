<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# RECTGTN — the planner model behind `plan` / `replan`

**RECTGTN** stands for **R**elationship-**E**nabled **C**apability-**T**emporal
**G**oal-**T**ask-**N**etwork — the HTN (Hierarchical Task Network) planning
model exposed over MCP by the `plan` and `replan` tools. This page defines the
JSON-LD shapes a domain may use.

## The three task kinds

Everything in a domain's `tasks` list (and in each method's `subtasks`) is one
of three kinds:

| Kind | JSON-LD form | Meaning |
|------|--------------|---------|
| **`TwCall`** | a call array `[name, arg…]` | name in `actions` → a primitive that runs; name in `methods` → a compound task decomposed via `alternatives` |
| **`TwGoal`** | the `goals` key (array or object form) | desired `(pointer, value)` bindings, satisfied via goal methods |
| **`TwMultiGoal`** | a `tasks` entry `{"multigoal": {…}}` | a set of bindings the planner backjumps over, choosing which to satisfy first |

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
 "tasks": [["top"]]}
```

Effects use `pointer/set`; guards use `{"eval": {"type": "math/<op>", …}}`.

## `TwGoal` — goals

A conjunction of desired `(pointer, value)` bindings, in two shapes:

```json
{"@type": "domain:Problem", "name": "switch_goal",
 "variables": [{"name": "switch", "init": {"x": false}}],
 "goals": [{"pointer": "/switch/x", "eq": true}]}
```

```json
{"@type": "domain:Definition", "name": "blocks",
 "goals": {"pos": {"params": ["block", "dest"],
                   "alternatives": [{"name": "stack_it", "subtasks": [["stack", "block", "dest"]]}]}}}
```

## `TwMultiGoal` — multigoals

```json
{"@type": "domain:Problem", "name": "switch_multigoal",
 "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
 "tasks": [{"multigoal": {"switch": {"x": true, "y": true}}}]}
```

A `tasks` list may freely mix call arrays and multigoal objects:
`"tasks": [["move_one", "a", "table"], {"multigoal": {"pos": {"c": "b"}}}]`.

## Relationships — the ReBAC graph

The "Relationship-Enabled" in RECTGTN is a standalone ReBAC (Relationship-Based
Access Control) graph engine, separate from a plan domain's `capabilities`
object below — `Taskweft.rebac_check/5` and `Taskweft.rebac_expand/4` (backed
by `taskweft_rebac`) answer relationship questions on their own, independent
of `plan`/`replan`.

A graph is `{"edges": [{"subject", "object", "rel"}], "definitions": {}}`.
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
chain, e.g. membership, before checking the inner expression) — pass one of
these as `expr_json` to `Taskweft.rebac_check/5` instead of a bare relation
name.

## Capabilities and temporal duration

A `TwCall`, `TwGoal`, or `TwMultiGoal` domain may add either or both.

**Capabilities** — a top-level `capabilities` object binds which entities hold
which capabilities, and which capabilities each action requires:

```json
"capabilities": {
  "entities": {"<entity>": ["<cap>", ...], ...},
  "actions":   {"<action>": ["<cap>", ...], ...}
}
```

An action only applies to an agent holding every capability it requires; the
planner tries the next alternative otherwise.

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
- [ADR 0004](https://github.com/taskweft/taskweft/blob/main/docs/adr/0004-unify-domain-capabilities-with-rebac-graph.md) — the planned unification of domain capabilities with the ReBAC relation-expression engine (issue #96).
