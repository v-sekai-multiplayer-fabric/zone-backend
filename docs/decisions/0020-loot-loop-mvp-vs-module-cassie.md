---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: ideation
discussion: N/A — pre-discussion draft
labels: mvp, vertical-slice, loot-loop, cassie, s7-sandbox
---

# 0020 Best minimal viable product: loot-action loop vs module-cassie

## Context

Two candidate "cores" of the product were compared at source level. The
original design
([20260611-loot-action-core-loop-mvp-vertical-slice](https://v-sekai-multiplayer-fabric.github.io/multiplayer-fabric-manuals/decisions/20260611-loot-action-core-loop-mvp-vertical-slice.html))
is a four-player instanced loot-action slice: Hub -> Field -> melee
combo -> first-touch loot contention -> inventory commit -> Hub, built
as five hexagonal pure reducers (combat, loot, presence, progression,
budgeter) under single-`zone-server` authority. Its own Confirmation
section records it as **shipped and smoke-verified** (`godot-loop-slice`:
one bot granted, one profile row committed), with known cuts — 2/5
cores as named reducers, SQLite only, no budgeter, perf gate unmeasured.

`fabric-godot-core#feat/module-cassie` is **not** an implementation of
that design. It is a CASSIE (CHI '21) VR-sketching engine module:
strokes -> constraint-solved beautify -> planar arrangement -> surface
patches, bit-deterministic across peers (strict-FP, CSP1 packets), with
heavy vendored deps (eigen, geogram, PMP, Slang) and **incomplete
upstream parity** (50/234 arrangement cycles). `weft-warp-loop`'s ADRs
already assessed the cassie stack: vendor beautify behind a C ABI
(accepted, unimplemented), defer surfaces/AVBD as
determinism-hostile — and its "Sigil Fabric" feature defines the
synthesis: drawn sigils (cassie-minus-beautify) as the action verb,
feeding per-spell-family s7 scripts in the libriscv sandbox — the same
loot_roll/combat_replay/progression_replay capability tier this repo
(zone-backend) hosts and compiles ([[0019-s7-aot-compiler-no-cross-toolchain]]).

## Decision Outcome

**The best MVP is the loot-action loop slice — it stays the product
spine.** It is done, verified end to end, and exercises every
integration seam the doc demanded. module-cassie must not gate any MVP:
it is a different product axis (an authoring verb, not a game loop),
its parity is unfinished, and its dependency/determinism cost is
already documented as MVP-hostile by weft-warp-loop ADR 0005.

The minimal forward step that uses both without betting on either:
keep the shipped loop slice as-is, and route new gameplay content
through the s7 sandbox tier (loot tables, combat scripts, progression
rules — Sigil Fabric's content model), for which this repo's compiler
and trampoline are the enabling infrastructure. Cassie integration, if
it comes, enters later as one more *input source* to the same loop
(stroke -> deterministic shape params -> s7 script), scoped per
weft-warp-loop ADR 0003 (beautify-only, C ABI) — never as a rewrite of
the loop.

## Consequences

Good: MVP remains the already-passing slice; new content lands as
sandboxed scripts without engine changes; cassie can mature on its own
branch without blocking releases. Bad: the sketching verb stays out of
the MVP, so Sigil Fabric's differentiating input remains unproven in
the slice; two determinism models (single-authority reducer vs
bit-identical re-simulation) continue to coexist unreconciled.

## Confirmation

Accepted when: the loop slice's `smoke.sh` still passes; at least one
slice behavior (loot table or combo rule) executes from an
s7-compiled/sandboxed script through zone-backend's trampoline; and no
MVP build depends on `feat/module-cassie` merging.
