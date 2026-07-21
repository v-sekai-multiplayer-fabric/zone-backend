---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: ideation
discussion: N/A -- not yet reviewed
labels: sandbox, godot, ideation
---

# 0040 Should zone-backend adopt the godot-sandbox guest API surface, and does `lib_godot_connector` belong here?

## Context

This RFD is ideation-stage, written to capture and scope a request before
any implementation, following [Oxide Computer Company's RFD
process](https://rfd.shared.oxide.computer/rfd/0001) -- record the
question and the options honestly, even (especially) when the answer
isn't decided yet, rather than let it live only in chat history or a
scratch `todo.md`.

The request names four external resources. Each was actually read
(not assumed) before writing this:

1. **`extension_api-4-7-single-precision.json` /
   `extension_api-4-7-double-precision.json`** -- Godot 4.7's full
   GDExtension API descriptor (every class/method/enum/signal Godot
   exposes to native extensions), one JSON file per float-precision
   build. These live in `taskweft/godotweft` (item 3 below): the
   single-precision file is pulled directly from `godotengine/godot-cpp`
   master; the double-precision file is a documented placeholder --
   its `README.md` explains it must be produced by building Godot 4.7
   with `scons precision=double` and dumping the API, not by cloning.
2. **`fabric-godot-core`'s `feat/sandbox/modules/sandbox/program/cpp/api`**
   -- the godot-sandbox project's guest-side C++ API surface (this
   org's fork/branch of `libriscv/godot-sandbox`): headers/sources for
   `Variant`, `Array`, `Dictionary`, `String`, `Node`/`Node2D`/`Node3D`,
   `Vector2/3/4`, `Basis`, `Quaternion`, `Transform2D/3D`, `Rect2`,
   `Rect2i`, `Plane`, `RID`, `Callable`, `Timer`, `CanvasItem`, plus
   `syscalls.h`/`syscalls_fwd.hpp` (the ecall numbering a guest program
   links against) and `api.cpp`/`api.hpp`/`api_inline.hpp`/`native.cpp`
   (the glue). This is the real, much richer sibling of the tiny
   tagged-GuestValue ABI `WeftWarpBurrito.Program` speaks (RFD 0018) --
   it lets a RISC-V guest program manipulate live Godot scene-tree
   objects, not just fixnums/atoms/lists/maps.
3. **`taskweft/godotweft`** (private) -- "Taskweft extern taxonomy for
   the Godot 4.x GDExtension API": a Lean4 formalization of the
   GDExtension API's known methods (organized into
   `Core_1..8`/`Editor`/`Node`/`Object`/`Properties_1..3`/`Resource`/
   `Server_1..2`/`Signals`/`Utility`/`Builtin` -- one Lean file per
   category), the two `extension_api-4-7-*.json` files above, two
   JSON-LD files (`godot-sandbox-elf.jsonld`, `planweft-riscv-asm.jsonld`
   -- domain/context vocabularies, evidently for describing sandboxed
   ELF programs and RISC-V assembly in the same RDF-ish style this
   repo's own `capabilities`/ReBAC graph JSON already uses) and one
   patch, `bigassm-sandbox.patch`, which adapts a separate RISC-V
   assembler project ("bigassm") to run *as a godot-sandbox guest ELF
   itself* -- replacing its CLI entry point with the `api.hpp` vmcall
   surface from item 2, and writing its output ELF to an in-memory
   buffer instead of a file. This is prior art for "a real, nontrivial
   guest program built against the godot-sandbox API," not taxonomy
   alone.
4. **`lib_godot_connector`** (hex.pm, v4.5.1, author `ddaian`,
   `github.com/Ughuuu/libgodot`) -- an unrelated, proof-of-concept
   package: "Elixir connector for LibGodot via NIFs." **This solves a
   different problem than items 2-3.** LibGodot embeds the actual
   Godot *engine* as a linkable library, callable from a host process
   (BEAM, here) -- there is no RISC-V sandbox, no guest/host ecall
   boundary; it's direct, unsandboxed, in-process engine access, aimed
   at a process that wants to *run* Godot. godot-sandbox (items 2-3) is
   the opposite shape: a RISC-V guest program, sandboxed and gas-
   metered, calling back into a *separate* host process (the actual
   game/editor) through a narrow ecall surface. `WeftWarpBurrito.Program`
   (RFD 0018/0039) is built for the godot-sandbox shape, not the
   LibGodot shape.

**Immediately relevant, from this same session**: RFD 0039 just retired
`WeftWarpBurrito.Sandbox` (the fixed-capability
`:loot_roll`/`:combat_replay`/`:progression_replay` guest, `c_src/guest/`,
and the vendored `c_src/thirdparty/s7` interpreter it embedded) as dead
code, and `Uro.ReBAC.SandboxAdapter`/`Uro.Planner.SandboxAdapter` as
plain-Elixir ports -- both because their content was trusted, bundled,
non-adversarial, so a RISC-V sandbox added machinery with no matching
threat to contain. `WeftWarpBurrito.Program` (the generic tagged-
GuestValue trampoline) was kept specifically for "a future genuinely-
untrusted-content guest program." **This request may be exactly that
future case arriving** -- or it may not be; that's the open question
this RFD exists to name rather than assume.

## Open questions (not yet answered)

1. **What's the actual driving use case?** zone-backend is a headless
   Phoenix API backend with no live Godot process of its own (`grep`
   confirms no Godot engine dependency anywhere in `mix.exs`). Item 2's
   API surface (`Node`, `CanvasItem`, `Timer`, scene-tree manipulation)
   only means something inside an actual running Godot process/editor
   -- i.e. **on the client/game side**, not this backend. Concretely:
   is the ask (a) zone-backend should be able to *validate or simulate*
   guest programs written against this API surface (e.g. a CI/tooling
   role, never actually executing inside a live scene tree), (b) some
   future zone-backend capability needs to *produce* godot-sandbox ELFs
   for the game client to run (the `bigassm`-on-sandbox pattern:
   compile something server-side into a guest ELF the client then
   executes), or (c) something else? The RFD can't respond to none of
   the three intended without this.
2. **Does `lib_godot_connector` actually apply here, given it's the
   LibGodot shape (item 4) and this request's other three items are
   all the godot-sandbox shape?** If the goal is "run/inspect a Godot
   process from BEAM directly," that's a `lib_godot_connector`-shaped
   problem, disconnected from `WeftWarpBurrito.Program`/godot-sandbox
   entirely -- worth stating plainly rather than trying to force one
   package to serve both shapes.
3. **"Must only clone the exposed surface area"** -- confirmed narrow:
   `modules/sandbox/program/cpp/api` is the guest-linkable API only
   (not `modules/sandbox`'s host-side NIF/editor-integration code,
   which is Godot-engine-internal and has no BEAM-side counterpart to
   speak to). Vendoring that one directory (mirroring how
   `c_src/thirdparty/libriscv` is already vendored) is mechanically
   straightforward once (1) is answered -- it isn't itself the hard
   part of this RFD.
4. **Does `taskweft/godotweft`'s Lean taxonomy get consumed, or just
   referenced?** Its `KnownMethods` categorization and the
   `godot-sandbox-elf.jsonld`/`planweft-riscv-asm.jsonld` vocabularies
   look like they'd matter most for validating that a guest program
   only calls methods the sandbox actually implements (item 2 doesn't
   expose 100% of the GDExtension API -- only what's in that `api/`
   directory) -- but that's speculative without knowing the driving
   use case from (1).

## Non-decision

No implementation decision is made here. This RFD exists so the
question and the four resources it references are recorded accurately
(their real contents, not assumptions) before any cloning, vendoring,
or dependency work happens. Once (1) is answered, a follow-on RFD
should cover the actual chosen shape -- likely one of: "vendor
`modules/sandbox/program/cpp/api` for guest-program validation/CI,"
"add a godot-sandbox-shaped `WeftWarpBurrito` guest capability for a
concrete new feature," or "evaluate `lib_godot_connector` for a
separate LibGodot-shaped need" -- rather than one RFD trying to resolve
all three at once.
