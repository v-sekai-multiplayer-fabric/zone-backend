# Align the planner stack on the glTF Interactivity node shape

- Status: accepted
- Date: 2026-07-12
- Deciders: K. S. Ernest (iFire) Lee
- Issues: #66, #67 · PRs: #68, #69 · taskweft-nif #6/#7 · taskweft-plans #1

## Context and Problem Statement

Taskweft domains describe action bodies as a list of steps. Two shapes existed:

- **Legacy shorthand** — a state read is `{"check": "/ptr", "eq": v}` and a write
  is `{"set": "/ptr", "value": v}`.
- **glTF Interactivity node shape** — a read is an `{"eval": {...}}` step whose
  node is a `math/<op>` comparison over a `pointer/get`, and a write is
  `{"pointer/set": "/ptr", "value": v}`.

The pieces of the stack migrated to the node shape at different times and this
app pinned an inconsistent mix:

- `taskweft_nif` (#6/#7) replaced the shorthand with `eval` + `pointer/set` and
  **rejects** `check`/`set` — but this app pinned the pre-migration NIF.
- `taskweft_plans` (#1) migrated its bundled domains to the node shape — but this
  app resolved a pre-migration commit transitively via `taskweft_mcp`.
- This app's `Taskweft.JSONLD.Loader.validate` already **required** the node
  shape (rejecting `check`/`set` as legacy).

That left two live contradictions: the pinned NIF could not execute domains the
validator accepted (#67), and the app could not consume post-migration
`taskweft_plans` fixtures — pointing at them made every planner call return
`no_plan` (#66).

## Decision Drivers

- One canonical action-body shape across NIF, bundled plans, validator, and
  tests — no "valid but unrunnable" documents.
- Converge on the glTF Interactivity standard nodes (the direction the NIF and
  plans already moved), not the bespoke shorthand.
- Keep the change verifiable in CI, which compiles the C++20 NIF from source.

## Considered Options

1. **Bump the whole stack to the node shape** — advance `taskweft_nif` and
   `taskweft_plans` to their migrated versions and migrate in-repo test domains.
2. **Revert the validator to accept `check`/`set`** — keep the old pinned NIF and
   old plans, and relax `Loader.validate`.
3. **Support both shapes everywhere** — teach the NIF (again) and the validator
   to accept legacy and node forms indefinitely.

## Decision Outcome

Chosen: **Option 1 — bump the whole stack to the node shape.** The validator was
already correct; the rest of the stack caught up to it.

- `taskweft_nif` `26ff6d9` → `0a2a90d` (`eval` + `pointer/set`; drops
  `check`/`set`). No Elixir-binding changes — purely C++ planner/loader.
- `taskweft_plans` resolved to `65e3ed7` (migrated domains + the
  `blocks_world_multigoal` fixture), governed transitively by `taskweft_mcp`.
- In-repo test domains migrated off the removed shorthand: a read becomes
  `{"eval": {"type": "math/<op>", "a": {"type": "pointer/get", "pointer": p},
  "b": v}}`; a write becomes `{"pointer/set": p, "value": v}`.
- No `lib/` change — `Loader.validate` was already consistent with the target.

## Consequences

Good:

- NIF, bundled plans, validator, and tests now agree on one shape; a domain that
  validates is one the NIF can run.
- The app consumes post-migration `taskweft_plans` fixtures, so the #52 multigoal
  soundness test runs against the real bundled fixture rather than a workaround.

Bad / follow-through:

- The node shape is more verbose than the shorthand (a comparison is a nested
  `eval` node rather than an inline `eq`).
- CI could no longer cache `_build`: `mix` will not recompile a git dep whose app
  version is unchanged when its locked sha moves, so a cached `_build` silently
  ran the old NIF against new domains. CI now caches only `deps` and compiles the
  NIF fresh each run (`.github/workflows/ci.yml`); `release.yml` already did.
- `taskweft_mcp` still declares `taskweft_plans`/`taskweft_nif` as `github: main`
  (no ref), so versions track main. A future consumer bump should pin refs if
  reproducibility matters.

## More Information

- Canonical forms live in the bundled `taskweft_plans` domains (e.g.
  `blocks_world.jsonld`) and `deps/taskweft_nif/standalone/tw_loader.hpp`
  (`build_action`, and the `math/<op>` table).
- Comparison ops accepted by the NIF: `math/eq`, `math/neq`, `math/lt`,
  `math/le`, `math/gt`, `math/ge`.
