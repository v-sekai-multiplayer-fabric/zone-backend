---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: taskweft, planner, elixir-port
---

# 0029 `tw_soltree.hpp` ported to plain Elixir

## Context

Continuing the "port taskweft to Elixir, slowly" direction (RFD
0026/0028): `standalone/tw_soltree.hpp` records the HTN method-choice
derivation tree so incremental replan can backtrack at the exact
choice point instead of restarting the full search. Self-contained
bookkeeping, no untrusted content, no floating point — the same
pattern as the prior two ports. `tw_replan.hpp` (not yet ported)
depends on it, so this lands first.

## Decision Outcome

`lib/uro/planner/sol_tree.ex`. Nodes are kept in a
`%{index => Node.t()}` map (not a growable array) — `restore/2`
"removes" nodes by dropping map keys and unlinking them from any
surviving parent, exactly mirroring the original's `nodes.resize(cp)`
plus parent-side `children` cleanup. `add_node/6`'s parent-linking
guard (`parent_id < id`) matches the original's `parent_id <
nodes.size() - 1` exactly, since at that point in the original the new
node has already been pushed.

## Consequences

Complete, tested building block; not yet wired to a caller since
`tw_replan.hpp` (the actual incremental-replan search that uses this
tree) is separate, not-yet-ported follow-on work.

## Confirmation

`test/uro/planner/sol_tree_test.exs` (9 cases): parent-child linking,
checkpoint/restore (node removal, parent unlinking, `action_nodes`
trimming), `nearest_retryable_ancestor` (finds a retryable task,
returns `nil` once exhausted or at the root, returns `nil` for an
unknown task name), and `prefix_length`'s default-vs-explicit
`first_step` behavior.
