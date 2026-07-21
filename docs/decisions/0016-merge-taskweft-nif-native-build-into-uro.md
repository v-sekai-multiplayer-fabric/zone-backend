---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: hrr, migration, repo-structure
---

# 0016 Merge taskweft_nif's native build directly into :uro

## Context

Following [[0015-extract-taskweft-rebac-and-sandbox-into-lib]], `taskweft_nif`
(C++20 planner NIF, `Taskweft.NIF`) was left as a `path:` dependency, since a
NIF loader is normally bound to whichever app's `priv/` its native build
writes into via `:code.priv_dir(:app_name)`. Unlike `weft_warp_burrito`'s
native build (CMake+Ninja, a vendored `libriscv`+`s7`, a RISC-V
cross-compiler), `taskweft_nif`'s is a single 448-line `.cpp` file, header-only
`standalone/` includes, and a plain `Makefile`/`Makefile.win` invoking
`g++`/`cl` directly — genuinely simple and cross-platform (`elixir: "~> 1.17"`,
plain `make` on non-Windows). Worth merging all the way in rather than
keeping it a separate dependency.

## Decision Outcome

Moved `c_src/taskweft_nif.cpp`, `standalone/` (all header-only), `Makefile`,
`Makefile.win`, and `lib/taskweft.ex`/`lib/taskweft/nif.ex`/
`lib/taskweft/mc_executor.ex` to zone-backend's own root/`lib/`, unchanged
except `Taskweft.NIF.__on_load__`'s `:code.priv_dir(:taskweft_nif)` →
`:code.priv_dir(:uro)`. `mix.exs`: added `compilers: [:elixir_make] ++
Mix.compilers()` and a `make_options/0` mirroring `taskweft_nif`'s own former
OS-detection logic (`nmake` when `VCINSTALLDIR` is set, `mingw32-make` on
plain Windows, default `make` otherwise); added `{:elixir_make, "~> 0.10",
runtime: false}` directly; removed the `taskweft_nif` path dependency.
Deleted the now-fully-absorbed `taskweft_nif/` subtree. Also ran `mix
deps.unlock --unused`, dropping ~28 stale `mix.lock` entries (MCP/OAuth/RDF
packages pulled in transitively by the now-deleted `taskweft`/`taskweft_rebac`
Hex references) — `mix.lock` went from 126 to 98 dependencies.

## Consequences

Good: `Taskweft.NIF`'s implementation is now fully part of this repo, no
separate dependency boundary; `mix.lock` is meaningfully smaller and
accurate. Bad: `:uro`'s own `mix compile` now requires a C++ toolchain +
`make` unconditionally (previously only true transitively, hidden inside a
dependency) — on this development machine specifically, that means `mix
compile` needs `mingw32-make`, which isn't installed, same class of gap as
the pre-existing `bcrypt_elixir`/`nmake` issue, just now also affecting
`:uro`'s own compile step directly rather than only a dependency's.

## Confirmation

`elixir -e Code.string_to_quoted!` and `mix format --check-formatted` pass
on all moved/edited files. `mix deps.get` resolves cleanly post-unlock.
`CI=true MIX_ENV=dev mix deps.compile` still shows no `weft_warp_burrito`/
`mingw32-make` output. `taskweft_nif`'s merged build itself not exercised
locally — blocked by the pre-existing `bcrypt_elixir`/`nmake` gap that stops
the compile chain before reaching `:uro`; this is the first time its build
runs as part of `:uro` directly rather than as an isolated dependency, so
CI is relied on for first confirmation.
