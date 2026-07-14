<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# RECTGTN — the planner model behind `plan` / `replan`

**RECTGTN** stands for **R**elationship-**E**nabled **C**apability-**T**emporal
**G**oal-**T**ask-**N**etwork. It is the HTN (Hierarchical Task Network) planning
model implemented by the C++ NIF (`taskweft_nif`) and exposed over MCP by the
`plan` and `replan` tools. This document defines the acronym, the task kinds a
domain may contain, and — for each kind — the **golden** (accepted) and
**adversarial** (rejected) JSON-LD shapes as enforced by
`Taskweft.JSONLD.Loader.validate/2`.

The canonical model type is `RECTGTNNode` in `lean/Planner/Types.lean`; the
runtime is `deps/taskweft_nif/standalone/tw_planner.hpp`. This page is the
MCP-facing contract — keep it aligned with the `plan` tool's `domain_json`
description in `taskweft-mcp` (`Taskweft.MCP.Server`).

## What each letter means

Each letter names a capability of the planner. The C++ source tags the
implementing piece with the same single letter (`// … RECTGTN 'X'`).

| Letter | Concept | Where it lives | Source tag |
|--------|---------|----------------|------------|
| **R** | **Relationship** — ReBAC relationship graph gates which actions an actor may take; also the **Replan** loop that recovers from a failed step. | `tw_rebac.hpp`, `tw_replan.hpp` | `'R'` |
| **E** | **Enabled** — a primitive action (a *command* that runs and can fail at runtime). | `tw_planner.hpp` (primitive apply) | `'E'` |
| **C** | **Capability** — ReBAC capability checks (`can(subject, relation, object)`) that guard action preconditions. | `tw_rebac.hpp` | `'C'` |
| **T** | **Temporal** — ISO 8601 action durations, STN consistency, plan timing. Overloaded with the compound **Task** kind (both tagged `'T'`). | `tw_temporal.hpp`, `tw_planner.hpp` | `'T'` |
| **G** | **Goal** — a conjunctive `TwGoal`: desired `(pointer, value)` bindings satisfied by *goal methods*. | `tw_domain.hpp` (`TwGoal`) | `'G'` |
| **T** | **Task** — a compound `TwCall` decomposed through `methods` / `alternatives`. | `tw_planner.hpp` (method dispatch) | `'T'` |
| **N** | **Network** — a `TwMultiGoal`: a set of bindings the planner backjumps over, choosing which to satisfy first. | `tw_domain.hpp` (`TwMultiGoal`) | `'N'` |

## The three task kinds

Everything in a domain's `tasks` list (and in each method's `subtasks`) is one of
three kinds. In the NIF these are the variant `TwTask = std::variant<TwCall,
TwGoal, TwMultiGoal>` (`tw_domain.hpp`).

| Kind | RECTGTN role | JSON-LD form | Dispatch |
|------|--------------|--------------|----------|
| **`TwCall`** | `'E'` (primitive) / `'T'` (compound) | a **call array** `[name, arg…]` | name in `actions` → apply effects; name in `methods` → decompose |
| **`TwGoal`** | `'G'` | the `goals` key (array *or* object form) | `domain.goal_methods.find(var)` — goal-method dispatch |
| **`TwMultiGoal`** | `'N'` | a `tasks` entry `{"multigoal": {…}}` | split into one `TwGoal` per binding; backjump over ordering |

`TwCall` is the shape every bundled problem historically used. `TwGoal` and
`TwMultiGoal` are the two kinds the bundled MCP suite did not exercise until
taskweft #52; this page pins their MCP-facing shapes so a future validator or
schema change surfaces any drift.

---

## `TwCall` — call arrays (`'E'` / `'T'`)

A `TwCall` is a JSON array whose head is an action or method name and whose tail
is its arguments: `[name, arg1, arg2, …]`. If `name` is in `actions` it is a
**primitive action** (`'E'`) — its `body` runs. If `name` is in `methods` it is a
**compound task** (`'T'`) — the planner picks an `alternatives` entry whose
`check` guards pass and recurses on its `subtasks`.

### Golden

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

Effects use `pointer/set`; guards use `{"eval": {"type": "math/<op>", …}}`. The
legacy `set` / `check` shorthand is **rejected** — see
[ADR 0001](adr/0001-gltf-interactivity-node-shape.md).

### Adversarial

| Rejected shape | Validator error |
|----------------|-----------------|
| `"tasks": ["top"]` — bare string, not a call array | (arity/shape checks assume arrays; a bare string is treated as an unknown call) |
| `["do_a", "x"]` when `do_a` has 0 params | `tasks: do_a expects 0 arg(s), got 1` |
| action body `{"set": "/done/a", "value": true}` | `action …: legacy \`set\` step is no longer supported …; use {"pointer/set": …}` |
| method `check` `{"pointer": "/x", "eq": 1}` | `method …: legacy \`{"pointer": …}\` check clause is no longer supported …; use {"eval": …}` |
| `body` references `{z}` not in params/variables | `action …: undeclared variable {z}` |

---

## `TwGoal` — goals (`'G'`)

A `TwGoal` is a conjunction of desired `(pointer, value)` bindings. The planner
looks up a **goal method** for each bound state variable
(`domain.goal_methods.find(var)`) and decomposes it into an action sequence that
reaches the desired value. The `goals` key has **two accepted shapes**:

- **Array form (problem side)** — a list of bindings folded into one conjunctive
  goal: `[{"pointer": "/var/key", "eq": desired}, …]`. This is the only form
  with a fixed binding shape, so it is the form the validator checks in detail.
- **Object form (domain side)** — goal *methods* keyed by state-var name:
  `{<var>: {"params": […], "alternatives": [ … ]}}`, validated structurally like
  `methods`.

### Golden — array form (a problem)

```json
{"@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
              "domain": "khr:planning/domain/"},
 "@type": "domain:Problem", "name": "switch_goal",
 "variables": [{"name": "switch", "init": {"x": false}}],
 "goals": [{"pointer": "/switch/x", "eq": true}]}
```

### Golden — object form (goal methods in a domain)

```json
{"@type": "domain:Definition", "name": "blocks",
 "goals": {"pos": {"params": ["block", "dest"],
                   "alternatives": [{"name": "stack_it", "subtasks": [["stack", "block", "dest"]]}]}}}
```

### Adversarial

| Rejected shape | Validator error |
|----------------|-----------------|
| `[{"pointer": "/switch/x"}]` — no `eq` | `goals[0]: binding must have an "eq" field` |
| `[{"eq": true}]` — no `pointer` | `goals[0]: binding must have a "pointer" field` |
| `[{"pointer": 5, "eq": true}]` — non-string pointer | `goals[0]: "pointer" must be a string` |
| `["/switch/x"]` — binding is not an object | `goals[0]: expected object, got string` |
| `"goals": 42` — neither object nor array | `expected goals to be object or array, got integer` |

---

## `TwMultiGoal` — multigoals (`'N'`)

A `TwMultiGoal` is a `tasks` entry of the form
`{"multigoal": {<var>: {<key>: desired, …}, …}}`. The planner treats each bound
key as a separate `TwGoal` subtask and **backjumps over which binding to satisfy
first** — a distinct branching path from a single `TwGoal`. Each unsatisfied
binding becomes a single-binding `TwGoal`; the multigoal is re-queued until all
bindings hold (`tw_domain.hpp`, `tw_planner.hpp`).

A `tasks` list may freely mix call arrays and multigoal objects.

### Golden

```json
{"@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
              "domain": "khr:planning/domain/"},
 "@type": "domain:Problem", "name": "switch_multigoal",
 "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
 "tasks": [{"multigoal": {"switch": {"x": true, "y": true}}}]}
```

Mixed with a call array in the same list:

```json
"tasks": [["move_one", "a", "table"], {"multigoal": {"pos": {"c": "b"}}}]
```

### Adversarial

| Rejected shape | Validator error |
|----------------|-----------------|
| `{"multigoal": {}}` | `tasks[0]: multigoal must bind at least one variable` |
| `{"multigoal": {"pos": {}}}` | `tasks[0]: multigoal[pos] must bind at least one key` |
| `{"multigoal": {"pos": "table"}}` — var → non-object | `tasks[0]: multigoal[pos] must be an object of key→desired` |
| `{"multigoal": "pos"}` — value not an object | `tasks[0]: "multigoal" must be an object, got string` |
| `{"goal": {}}` — object task that is not a multigoal | `tasks[0]: object task must be a {"multigoal": {…}} entry` |

---

## Soundness contract

Every RECTGTN domain that validates and plans must satisfy the QA invariant used
across the suite: replanning the returned plan with `fail_step == -1` reports the
whole plan complete.

```elixir
{:ok, plan_json} = Taskweft.plan(domain_json)
{:ok, out}       = Taskweft.replan(domain_json, plan_json, -1)
env = Jason.decode!(out)
env["fail_step"]       == -1                    # no failure
env["completed_steps"] == length(Jason.decode!(plan_json))  # every step ran
```

The bundled `blocks_world_multigoal` fixture (`taskweft_plans`) is asserted
against this contract in `test/taskweft/jsonld/loader_test.exs`, driving the
`'N'` branch through the compiled NIF.

## See also

- [ADR 0001](adr/0001-gltf-interactivity-node-shape.md) — the action-body node
  shape (`eval` + `pointer/set`) the `TwCall` bodies above use.
- `lib/taskweft/jsonld/loader.ex` — the validator these shapes are checked
  against.
- `deps/taskweft_nif/standalone/tw_domain.hpp` — `TwTask`, `TwGoal`,
  `TwMultiGoal` structs.
