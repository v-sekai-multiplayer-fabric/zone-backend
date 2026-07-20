---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: prediscussion
discussion: N/A — no PR yet, plan under active iteration
labels: hrr, tagging, migration, rebac
---

# 0013 Plan: slow migration off multiplayer-fabric-taskweft toward weft-warp-burrito

## Context

`zone-backend` depends on `taskweft` (`V-Sekai-fire/multiplayer-fabric-taskweft`)
today for two real, live production call sites:

- **ReBAC**: `Taskweft.ReBAC.new_graph/0`, `add_edge/4`, `check_rel/4` —
  used in `lib/uro/v_sekai.ex` (zone `CAN_ENTER`/`OWNS`) and
  `lib/uro/helpers/user_content_helper.ex` (avatar/map/prop uploader
  membership checks).
- **Planning**: `Taskweft.NIF.plan/1`, wrapped by
  `lib/uro/v_sekai/entity_planner.ex`.

This session added `weft_warp_burrito` (`weftspun/weft-warp-burrito`)
as a new git dependency (see `mix.exs`). Reading that repo's own
`rfd/0001`–`0005` (published there, not here) matters before treating
it as a taskweft replacement:

- **RFD 1** (published): `weft-warp-burrito` is a BEAM/NIF port of
  `weft-warp-loop`'s s7-in-`libriscv` sandbox, exposing exactly **three
  fixed capabilities** — `loot_roll`, `combat_replay`,
  `progression_replay`. No ReBAC. No general planner.
- **RFD 4** (published): `taskweft/taskweft` and `taskweft/nif` were
  copied *into* `weft-warp-burrito` as untouched sibling Mix projects —
  not merged with the sandbox, not reimplemented. The live upstream
  `taskweft` repos this org depends on are unchanged.
- **RFD 2** (prediscussion, in that repo): `weft-warp-burrito` itself
  is slated to be **archived**, its BEAM/OTP host absorbed into
  `weft-warp-loop`.
- **RFD 5** (ideation, in that repo): the longer-term architecture puts
  **Flow (C++)**, not BEAM, as the embeddable core for "the whole
  multiplayer server"; BEAM consumers (like `taskweft`, and by
  extension `zone-backend`) would reach it via an Erlang C Node, not a
  NIF.

So `weft-warp-burrito` today provides **no equivalent** to either of
`zone-backend`'s two live `Taskweft` call sites, and its own RFDs say
its current shape (a standalone Burrito executable) is itself
transitional.

## Decision Outcome

**Slow migration, staged, not a swap.** Concretely:

1. **Now**: `weft_warp_burrito` is added as a dependency but called
   from nowhere in `zone-backend` — it exists to be evaluated, not
   used. `Taskweft.ReBAC` and `Taskweft.NIF.plan/1` call sites are
   untouched.
2. **Next**: track `weft-warp-burrito` RFD 2's archival and RFD 5's
   Flow/C-Node direction from the outside — do not deepen
   `zone-backend`'s coupling to `weft-warp-burrito` specifically until
   one of those settles (its `state` moves past `prediscussion`/
   `ideation`), since the repo may not exist in its current form
   later.
3. **Later, conditional**: only once something in the
   `weft-warp-burrito`/`weft-warp-loop` line exposes a ReBAC- or
   planner-equivalent capability does a real per-call-site migration
   become possible — and it should happen one call site at a time
   (ReBAC first, since it's the simpler of the two), each as its own
   RFD, not a single big-bang dependency swap.

## Consequences

Good: `zone-backend` doesn't couple itself to a dependency
(`weft-warp-burrito`) that its own maintainer has already flagged for
archival, and doesn't lose the real, working `taskweft` ReBAC/planner
in the meantime. Bad: `zone-backend` carries two taskweft-lineage
dependencies at once (`taskweft` in active use, `weft_warp_burrito`
unused) until upstream's own architecture (RFD 2/5) settles —
`mix.exs` will look like it has redundant/half-migrated dependencies
to anyone reading it without this RFD.

## Confirmation

`weft_warp_burrito` fetches cleanly (`mix deps.get`, git dep pinned at
`b1e04b1`). Its own native build (CMake + `mingw32-make` +
`riscv-none-elf-gcc`) has not been exercised in this environment — the
existing `bcrypt_elixir`/`nmake` gap already blocks `mix compile`
before reaching it. No `zone-backend` code references
`WeftWarpBurrito.*` yet, by design. Revisit this RFD once
`weft-warp-burrito` RFD 2 or RFD 5 reaches `published`/`committed`.
