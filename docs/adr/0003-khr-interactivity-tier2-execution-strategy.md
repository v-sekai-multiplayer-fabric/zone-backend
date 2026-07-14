# KHR_interactivity Tier 2: embed libriscv directly, compile RECTGTN behavior graphs to riscv64

- Status: accepted (design only — not yet implemented)
- Date: 2026-07-14
- Deciders: K. S. Ernest (iFire) Lee

## Context and Problem Statement

Tier 1 (see ADR 0002) covers pure value-computation nodes. The remaining
~22 KHR_interactivity nodes — all `flow/*` (sequence, branch, switch, for,
while, doN, multiGate, waitAll, throttle, setDelay, cancelDelay), all
`event/*` (onStart, onTick, onSelect, send, receive, stopPropagation),
`animation/*`, and `pointer/interpolate`/`variable/interpolate` — need an
actual flow-graph execution model: flow sockets (not just value sockets),
asynchronous event triggers, and time-based suspend/resume. No such
execution model exists anywhere in `taskweft_nif`: `tw_planner.hpp` treats
an action's body as a synchronous, opaque `TwActionFn` (state in, state or
nullptr out); `build_action()` executes a body as a strict imperative
sequence with no notion of a persistently "activated" graph.

The user directed building this rather than treating it as out of scope,
on the grounds that IPyHOP (the algorithm `taskweft_nif` implements) was
designed to be a full planner — live/dynamic execution is within its
intended scope, not a foreign addition to a purely-symbolic tool.

## Decision Drivers

- Reuse a vetted, sandboxed execution engine instead of hand-rolling flow
  control, event dispatch, and suspend/resume semantics from scratch,
  per explicit user direction to look at `libriscv`/godot-sandbox-adjacent
  work first.
- The reused component must work standalone inside a C++ NIF (no live
  Godot process, no Variant/Node/scene-tree) — `taskweft_nif` runs inside
  the BEAM, not Godot.
- Avoid introducing a runtime toolchain dependency, since `taskweft_nif`
  already builds on Windows (`Makefile.win`) as a single-TU, single-Makefile
  C++ project with no CMake/submodules.
- The spec is explicit that KHR_interactivity graphs are Turing-complete
  (`00_header_and_introduction.md`, "Turing Completeness") and must be
  time/step bounded — whatever engine is chosen needs a real sandbox, not
  an ad hoc interpreter loop.

## Considered Options

1. **Hand-roll a from-scratch flow-graph interpreter** inside
   `taskweft_nif`'s C++ — full control, but re-derives execution/suspend/
   resume semantics from nothing, and re-derives sandboxing guarantees the
   spec requires.
2. **Reuse `godot-sandbox`** (`github.com/libriscv/godot-sandbox`) directly —
   rejected: it is a Godot GDExtension bound to a live Godot process
   (Variant, Node, scene-tree APIs); has no standalone embedding path.
3. **Embed `libriscv`** (`github.com/libriscv/libriscv`) directly — the
   standalone, engine-agnostic C++ RISC-V emulator library `godot-sandbox`
   itself is built on top of. No Godot dependency; embeds the same way any
   library-form VM does (host allocates a `Machine`, exposes syscalls,
   drives execution).
4. For the graph → guest-program compilation step specifically: **emit C
   source and shell out to an external riscv64 cross-compiler** at
   graph-load time — rejected: adds a runtime toolchain dependency on every
   deployment target, including Windows, which the "single Makefile,
   already builds on Windows" constraint above rules out.
5. **Write a dedicated RECTGTN-behavior-graph → riscv64 compiler**, following
   the pattern of `github.com/V-Sekai-fire/godot-gdscript-compiler-demo`
   (a from-scratch compiler lowering a script/graph representation directly
   to target-ISA machine code) — the compiler itself becomes a component of
   `taskweft_nif`, not an external build tool.

## Decision Outcome

Chosen: **option 3 (embed `libriscv`) + option 5 (a dedicated RECTGTN→riscv64
compiler)**, explicitly not options 1, 2, or 4.

- **Engine**: vendor `libriscv` into `taskweft_nif` header/`.cpp`-style,
  matching the existing vendoring pattern (`thirdparty/tsl_ordered_map.h`,
  `date/`) — no CMake or submodule needed.
- **Compiler**: a new component (planned file: `tw_graph_compile.hpp`) that
  lowers a KHR_interactivity-shaped behavior graph (flow nodes + event nodes
  + Tier 1 value nodes) directly into riscv64 (Linux ABI) machine code —
  flow-graph control edges become basic blocks with explicit
  branches/calls — rather than routing through C source and an external
  toolchain.
- **Host/guest boundary** (planned file: `tw_graph_vm.hpp`): a minimal
  syscall ABI back into existing machinery —
  `tw_pointer_get`/`tw_pointer_set` (→ `TwState::get_nested`/`set_nested`,
  unchanged), `tw_eval` (→ `TwLoader::eval_node`/`eval_expr`, meaning Tier 2
  depends on Tier 1 being complete first), `tw_wait_tick`, `tw_emit_event`,
  `tw_set_delay`/`tw_cancel_delay` (host-side suspend/resume + timer/event
  dispatch). Values cross the ABI as JSON, reusing existing `TwValue`
  (de)serialization, not a new binary struct layout — smaller, safer
  surface, consistent with the rest of the codebase treating JSON as its
  lingua franca at every boundary.
- **Suspend/resume**: each graph instance owns a serialized `libriscv`
  machine snapshot (the library supports this natively) plus a
  `shared_ptr<TwState>` and a small pending-timer/subscription table, keyed
  by an opaque instance id (mirrors `taskweft_nif.cpp`'s existing
  `s_domain_cache` pattern).
- **New entry point**: `tw_execute_graph`, distinct from `tw_plan`/`replan`,
  with new NIF functions (`execute_graph`, `resume_event`, `tick`) and a new
  `lib/taskweft/graph.ex` Elixir wrapper — `tw_planner.hpp` requires **no
  changes**, since it already treats action execution as opaque
  (`TwActionFn`'s state-in/state-out contract covers both symbolic actions
  and graph-backed ones).

### Consequences

- Good: reuses a real, vetted sandboxed VM instead of a bespoke interpreter;
  the sandboxing/Turing-completeness concern the spec calls out is handled
  by `libriscv`'s existing execution-budget mechanisms, not re-derived.
- Good: no runtime cross-compiler dependency — graph compilation is a
  component of `taskweft_nif` itself, works the same on Windows as
  everywhere else.
- Good: `tw_planner.hpp`/`tw_domain.hpp` need zero changes; Tier 2 is purely
  additive alongside the existing symbolic planner.
- Bad: this is a genuinely new, sizeable subsystem (a custom compiler
  targeting a real ISA, plus a VM host layer) — not a quick add like Tier 1.
  Explicitly sequenced *after* Tier 1 completes, since `tw_eval` depends on
  the full Tier 1 value layer.
- Open, deliberately not resolved by this ADR: whether a graph-backed
  action is synchronous (planner calls it, gets a new state back
  immediately) or genuinely async (tick/event-driven, observed only via
  later replanning) — to be decided when `tw_planner.hpp` integration is
  actually implemented, not speculatively now.

## More Information

Not yet implemented as of this ADR. See the Tier 1 milestones (ADR 0002)
for the prerequisite value layer. Planned milestone order: (1) vendor
`libriscv`, prove a hand-written trivial guest ELF runs and
serializes/resumes inside `tw_graph_vm.hpp`; (2) build the compiler for the
no-state subset (`flow/sequence`/`branch`/`switch`), wire `tw_execute_graph`
+ `Taskweft.Graph`; (3) event model + suspend/resume persistence; (4)
remaining flow nodes, `animation/*`, `pointer/interpolate`/
`variable/interpolate`; (5) resolve the sync-vs-async action integration
question against `tw_planner.hpp`.
