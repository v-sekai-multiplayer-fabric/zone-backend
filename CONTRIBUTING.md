# Contributing

Red-green-refactor: every feature is driven by a failing PropCheck
property, committed when green, cleaned up with the properties still
green.

## Guiding principles

- **RED first, always.** Before writing implementation code, write a
  property (or unit test) that fails at runtime. Validate that it
  fails for the right reason — mutation-test it by briefly breaking the
  implementation if the failure message is ambiguous.
- **Narrow the slice.** Each cycle is one public behaviour: one
  Storage API call, one WHERE strategy, one aggregate function. If
  turning a property green requires touching two independent paths,
  split it into two cycles.
- **Error tuples, not exceptions.** Functions return `{:ok, value}` /
  `{:error, reason}` at every boundary. `raise` is reserved for
  programmer errors. NIF boundary `rescue` blocks are the one accepted
  exception — they prevent a NIF crash from crashing the GenServer and
  must return a typed fallback (`nil`, `[]`, `:ok`).
- **Commit every green.** One commit per cycle. Sentence case, no
  `type(scope):` prefix.
- **PropCheck, not mocks.** Generators produce the inputs; properties
  express the invariant. If a generator is hard to write, the API
  surface is too wide.
- **Ecto is optional.** All behaviour registrations are guarded by
  `Code.ensure_loaded?`. See `Taskweft` moduledoc for details.

## Design notes

Implementation details (HRR type boundary, transaction savepoints,
bundle rebuild, Ecto adapter registration) live in the relevant
moduledocs:

- `Taskweft` — savepoints, bundle rebuild, Ecto adapter
- `Taskweft.NIF` — HRR type boundary
- `Taskweft.MCP.Server` — MCP tools, DSPy training-time integration
- `Taskweft.MCP.Client` — peer connection specs
