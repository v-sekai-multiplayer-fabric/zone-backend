# s7, compiled to RISC-V, running inside libriscv

`s7_guest.elf` is `thirdparty/s7/s7.c` + `s7_guest_main.c`, cross-compiled
with a real newlib toolchain and run as a guest binary under the
vendored libriscv (`thirdparty/libriscv`) — ADR 0006's sandboxed
scripting tier, actually wired up: fuel-metered (RISC-V instructions,
not wall-clock), zero-syscall by default, and proven deterministic
across independent `Machine` instances, now including through a real
Flow actor (`flow-toolchain/examples/s7_riscv_actor.actor.cpp` +
`s7_riscv_actor_test.cpp`).

## Toolchain

musl was ruled out explicitly for this tier; newlib was approved instead
(a libc built for embedded/freestanding targets, unlike musl's
full-Linux-userspace scope). The prebuilt Windows toolchain used:

```
https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64.zip
```

Extract it to a **short path** — `riscv-none-elf-gcc`'s own internal
include-search-path construction (several chained `../../../../`
segments) can exceed Windows' `MAX_PATH` if the toolchain lives under a
long path (this bit us for real: extracting under a ~200-character temp
directory produced "sys/unistd.h: No such file or directory" even
though the file existed — moving the same toolchain to `C:/rv/toolchain`
fixed it immediately, no other change).

## Build recipe

```sh
touch mus-config.h   # s7's own docs: "make mus-config.h (it can be empty)"

riscv-none-elf-gcc -march=rv64gc -mabi=lp64d -static -O2 \
    -I. -I../thirdparty/s7 -DWITH_C_LOADER=0 -DWITH_SYSTEM_EXTRAS=0 \
    -c ../thirdparty/s7/s7.c -o s7.o

riscv-none-elf-gcc -march=rv64gc -mabi=lp64d -static -O2 \
    -I. -I../thirdparty/s7 -c s7_guest_main.c -o s7_guest_main.o

riscv-none-elf-gcc -march=rv64gc -mabi=lp64d -static -O2 \
    -Wl,--undefined=guest_eval \
    s7_guest_main.o s7.o -lm -o s7_guest.elf
```

Two flags matter beyond the obvious `-march`/`-mabi`:

- `-DWITH_SYSTEM_EXTRAS=0` — `s7.c` defines `WITH_SYSTEM_EXTRAS` as
  `!_MSC_VER` (true for any non-MSVC compiler, including this one), which
  pulls in `<dirent.h>`/`DIR`/`readdir`/`closedir` for a directory-listing
  feature. newlib doesn't provide these in a bare freestanding build (no
  real filesystem) — compilation fails without this override. (This is
  also the moment `flow-toolchain/thirdparty/s7/MINIMAL_LIBC_SCOPE.md`'s
  earlier note about `WITH_C_LOADER` turned out to only be half the
  picture — verify-by-building keeps finding these, one at a time.)
- `-Wl,--undefined=guest_eval` — without a reference to it, the linker's
  garbage collection drops the one function the host actually calls via
  VMCALL (see `libriscv/docs/VMCALL.md`'s own warning about this: even
  `__attribute__((used, retain))` isn't always enough against
  `--gc-sections`-style stripping).

## Runtime: the bug this took to actually run correctly

The guest ran and produced correct output (`s7_guest_run.cpp`, a
throwaway host harness) on the first real attempt with one exception:
`s7RiscvInitialize()`'s own `RISCV_BRK_MEMORY_SIZE` default is 1MB
(`thirdparty/libriscv/lib/libriscv/common.hpp`) — nowhere near enough
for `s7_init()`'s own heap needs. `malloc` returning `NULL` past that
point, unchecked, was a guest-side null-pointer dereference reported by
libriscv as a generic "Protection fault" with no address — bisected by
disassembling `_sbrk` in the guest binary directly
(`riscv-none-elf-objdump -d`) and noticing the second `ecall` (the one
that actually requests more heap, not just queries the current break)
was exactly where execution stopped. Fixed by raising
`RISCV_BRK_MEMORY_SIZE` (128MB) as a compile definition on the `riscv`
CMake target — see `flow-toolchain/CMakeLists.txt`.

A second, separate bug surfaced only once this got wired into a real
`.actor.cpp` + `flow.lib` build: `libriscv`'s `Memory` keeps a
non-owning `std::string_view` over the guest ELF bytes
(`memory.hpp`: `const std::string_view m_binary`) — it does not copy
them. `s7_riscv_core.cpp`'s first version read the ELF into a
function-local `std::vector`, which was destroyed the moment
`s7RiscvInitialize()` returned, leaving `Machine`'s view dangling. Calls
made *inside* that function (`simulate()`, running the guest's own
`main()`) still worked; anything called afterward — `vmcall()`,
`address_of()` — touched freed memory. Fixed by keeping the byte buffer
alive as a companion global next to the `Machine` itself, for as long as
the `Machine` lives.

## Not done here

- No shrubbery-notation reader — `s7_guest_main.c`'s `guest_eval` takes
  plain s7 s-expression text.
- `guest_eval` prints its result through the guest's own stdout (a real
  Linux `write()` syscall, routed by `setup_linux_syscalls()` to this
  process's real stdout) rather than marshalling a return buffer across
  the host/guest address-space boundary — the simplest correct option
  for a single string result; a raw host pointer passed as a `vmcall`
  argument is **not** valid guest-visible memory (a bug hit and reverted
  during development of the ArtifactsMMO agent's own FFI, before this
  guest existed — same class of mistake, worth remembering here too).
- The syscall allowlist is still whatever `setup_linux_syscalls()`
  installs (the full Linux surface) — ADR 0006's default-deny design
  (`flow-toolchain/examples/riscv_guest_host_interface.md`) calls for
  installing only `exit`/`exit_group` and denying everything else; this
  guest hasn't been narrowed to that yet.
- This CMake project doesn't cross-compile `s7_guest.elf` itself — it's
  vendored here as a built artifact, since building it needs the
  separate RISC-V toolchain above, which this build doesn't otherwise
  require. Wiring an actual cross-compile step (gated behind finding
  that toolchain) is unstarted.
