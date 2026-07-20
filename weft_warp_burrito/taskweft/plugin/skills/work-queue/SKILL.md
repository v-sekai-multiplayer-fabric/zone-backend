---
description: Show the current Taskweft work queue — load priv/plans/domains/work_queue.jsonld and report each item's phase, the pass-condition and scenario status, and stack-component readiness. Use when the user asks "what's left", "what's the status", "what's in flight", or names this skill explicitly.
---

# Work queue

The work queue lives at `priv/plans/domains/work_queue.jsonld` — a JSON-LD HTN domain document. It is the source of truth for project status; do not infer status from `git log` or open PRs.

## What to do

1. Read `priv/plans/domains/work_queue.jsonld`.
2. Read the four `variables[]` entries: `phase`, `pass_condition`, `scenario`, `stack_ready`. Each has an `init` map of `name → integer`.
3. Decode integers using the `enums` block at the top of the file:
   - `phase`: `0=unstarted, 1=stub, 2=green, 3=done`
   - `status` (used by `pass_condition`, `scenario`, `stack_ready`): `0=unmet/unverified/not-ready, 1=met/verified/ready`
   - `approach`: `0=direct, 1=prototype_first`
4. Report by section, in this order, terse:
   - **In flight** — `phase` items where value is `1` (stub) or `2` (green). One line each: `name — stub|green`.
   - **Unstarted** — `phase` items at `0`. One line each: `name`. If the list is long, group by dev track using the `methods` field (each `*_dev_track` lists its subtasks).
   - **Done** — count only, do not list.
   - **Pass conditions** — items where `pass_condition` is `0` (unmet). One line each.
   - **Scenarios** — `concert/chokepoint/convoy/ragdoll`, mark `0` as unverified.
   - **Stack readiness** — components where `stack_ready` is `0`.
5. End with the `win_condition` field verbatim — one line.

## What not to do

- Do not edit the file. This skill is read-only.
- Do not infer or invent items not present in the variables. If the user asks about an item that isn't there, say so.
- Do not summarise the `actions` or `methods` blocks unless asked. They describe how items advance, not their current state.
- Do not translate phases into prose ("almost done", "blocked"). Report the integer-decoded label only.

## When the user asks for one item

If the user asks `what's the status of <item>`, show:

```
<item>: phase=<label> ( approach=<label> if present )
gating method: <method-name from methods[] whose name is complete_<item> >
```

Then list the method's `alternatives[].subtasks` so they can see what unblocks it.
