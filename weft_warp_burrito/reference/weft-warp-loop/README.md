# Reference snapshot from weft-warp-loop

These files are **copies**, not vendored build inputs - nothing under
`reference/` is referenced by `c_src/Makefile`, `c_src/CMakeLists.txt`,
or `mix.exs`. They exist so this repo is a self-contained historical
snapshot once it's archived (see `rfd/0002/README.adoc`), without
requiring a checkout of `weft-warp-loop` to see what this repo's own
`c_src/guest/weft_guest.c` was compared against and diverged from.

Copied verbatim at `weft-warp-loop` commit `07066051` (2026-07-20):

- `riscv-guests/s7_guest_main.c` - the original `guest_eval`-only guest
  (a plain-string-eval entry point), superseded in both `weft-warp-loop`
  and this repo by fixed, named capabilities - kept here as the
  starting point the "no generic eval" rule (RFD 1) was a reaction to.
- `riscv-guests/s7_sandbox_guest.c` - the in-progress `fabric-godot-core`
  Sandbox port. Uses `GuestVariant`, Godot's own Variant wire format,
  which this repo's `c_src/guest/weft_guest.c` deliberately does not:
  see `rfd/0001/README.adoc`'s "What was deliberately not ported"
  section. As of this commit it implements `guest_loot_roll` and
  `guest_combat_replay` only - no `progression_replay` yet, unlike this
  repo.
- `riscv-guests/combat_embed.h` - `s7_sandbox_guest.c`'s generated
  `.incbin`-equivalent for `record-macros.scm` + `combat.scm`; included
  here only so that file compiles for reference/reading, not to be
  built.
- `riscv-guests/README.md` - the toolchain and build-recipe notes this
  repo's own RFD 1 draws its Windows-`MAX_PATH` and
  `WITH_SYSTEM_EXTRAS=0` notes from.
- `examples/s7_riscv_{loot,combat,progression}_golden_test.cpp` - the
  host-side tests that establish the three reference vectors
  `test/weft_warp_burrito_test.exs` checks against, each in turn
  checked against a Lean4 reference in `fanout-core`.
- `riscv-guests/shrubbery/*.shrub` - the human-authored shrubbery
  source for the taskweft HTN planner and its supporting layers
  (types, temporal, ReBAC/FloydWarshall, HRR, WitnessDAG, the
  reentrant planner, ISO8601 duration parsing, `qc-fuzz`, and
  `loot.shrub`), plus `_verify_snippet.shrub`. Source only - the
  *generated* `.scm` output (`shrubbery_to_scheme.py`'s build product,
  one `-generated.scm` per `.shrub` file) and the Python reader itself
  are intentionally not copied: regenerating from `.shrub` is the
  point of keeping only the source, not a frozen build artifact that
  can silently drift from it.

Not copied: `flow-toolchain` itself (the Flow actor compiler/runtime),
`fanout-core`'s Lean4 proofs, and the taskweft HTN planner's own
generated Scheme/Python tooling (see previous bullet) - see
`rfd/0001/README.adoc`'s "What was deliberately not ported" for the
broader rationale.
