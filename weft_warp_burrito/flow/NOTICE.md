# Provenance

Vendored, unmodified except as noted, from https://github.com/apple/foundationdb,
commit `6fafd8e08ee1410917ea6e0d99bd27233c89fe15` (`main`), Apache License 2.0:

- `actorcompiler/` ← `flow/actorcompiler_py/` (renamed as a package). This
  is FoundationDB's own current default actor-compiler
  (`cmake/CompileActorCompiler.cmake`: `ACTORCOMPILER_COMMAND = python -m
  flow.actorcompiler_py`) — the C#/.NET implementation is a fallback path
  (`FDB_USE_CSHARP_TOOLS`). Zero external pip dependencies (stdlib only).
- `flow/` and `contrib/{crc32,stacktrace,folly_memcpy,SimpleOpt,libb64}` —
  upstream's own `flow/CMakeLists.txt` compiles the entire `flow/`
  directory as one library with no networking/non-networking split, so
  there is no smaller officially-sanctioned subset to vendor instead.

**Excluded from `flow/`** (own `main()`, not needed for a library):
`LinkTest.cpp`, `TLSTest.cpp`, `MkCertCli.cpp`, `acac.cpp`, `FlowTest.cpp`,
`CoroTests.cpp`, `IThreadPoolTest.cpp`, `UnitTestRunner.cpp`,
`swift_concurrency_hooks.cpp`, `swift_task_priority.cpp` (need an actual
Swift compiler; this project never defines `WITH_SWIFT`).

**Kept, one level deeper:** `Net2.cpp` includes `flow/swift_concurrency_hooks.h`
unconditionally (only its contents are `WITH_SWIFT`-gated), which needs
`swift.h` and `flow/swift/ABI/{Task,MetadataValues}.h` +
`flow/swift/Basic/FlagSet.h` — self-contained, stdlib-only headers from
swift.org (Apache 2.0 with Runtime Library Exception), no Swift compiler
needed to parse them. `swift_future_support.h`, `swift_stream_support.h`,
`unsafe_swift_compat.h` are not kept: they need
`SwiftModules/Flow_CheckedContinuation.h`, generated at build time by the
actual Swift compiler over a Swift module — nothing this project compiles
needs them.

Dependency versions, per upstream `cmake/CompileBoost.cmake` and
`cmake/GetFmt.cmake`: Boost 1.86.0 (components: `context` [non-Windows] +
`filesystem iostreams program_options serialization system url`), fmt
11.1.4, OpenSSL, Python3 + Jinja2 (`ProtocolVersion.h` codegen via
`flow/protocolversion/protocol_version.py`). `vcpkg.json` pulls current
vcpkg versions of these, which may not exactly match upstream's pins.

**Modified**: `flow/SimpleCounter.cpp` -
`flow/patches/0001-simplecounter-skip-invalid-name.patch`. Upstream's
`simpleCounterReport()` asserts every counter name is a valid Prometheus
metric name and crashes the process otherwise; one dynamic counter this
tree exercises (`/flow/fastalloc/allocateCallsSize%d` and its siblings in
`FastAlloc.cpp`, built via `format()`) intermittently loses its entire
dynamic suffix under real use, tripping that assertion independent of
concurrency or process exit path (a reentrancy bug in `format()` itself,
too broad and load-bearing to chase down safely here). The patch skips a
malformed counter for that one report instead of crashing.
