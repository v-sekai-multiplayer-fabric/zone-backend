# Host-side interface for the s7 guest (ADR 0006, items 5-6)

Design only — nothing here is buildable yet, since no s7 guest binary
exists to link or call into (blocked on the libc work in
`flow-toolchain/thirdparty/s7/MINIMAL_LIBC_SCOPE.md`). Grounded directly
in the vendored `libriscv` API (`flow-toolchain/thirdparty/libriscv/docs/
{VMCALL,SYSCALLS}.md`), not guessed.

## Syscall allowlist (item 6)

`Machine<RISCV64>::install_syscall_handler(number, handler)` is static —
it installs process-wide, once, not per-`Machine` instance ("System call
handlers are static by design to avoid system call setup overhead when
creating many machines" — `SYSCALLS.md`). That fits this repo's actor
model well: a Flow actor calling into scripted content does so
synchronously and sequentially, the same way `fanout-core`'s FFI is
already safe without a lock (`fanout-core/README.md`), so a
process-global handler table is not a new constraint.

Default-deny, not default-permit: `setup_linux_syscalls()` (used by
`libriscv_vendor_test.cpp`'s smoke test) installs the full Linux syscall
surface — `write`/`read`/`open`/`getrandom`/etc. — appropriate for
proving the vendored library works against a real prebuilt Linux
binary, wrong for a sandboxed guest that is supposed to have zero I/O by
construction (ADR 0006's isolation driver). The real guest setup calls
none of that. It installs only:

- `exit` (93) / `exit_group` (94) — mandatory; "there is no graceful way
  to stop running a Linux program without implementing" these
  (`SYSCALLS.md`). Maps to `machine.stop()`.
- Everything else stays unhandled. `machine.on_unhandled_syscall` is set
  to a handler that returns `-ENOSYS` and does nothing else — no silent
  fallback to real I/O. If s7's guest build ever needs `brk`/`mmap` for
  heap growth (open question — depends on which libriscv memory-arena
  mode item 2's build ends up using), that handler is added explicitly
  and reviewed on its own, not folded into an allowlist blindly copied
  from `setup_linux_syscalls()`.

No `write`/`read` means the guest's own `printf`/`fprintf` calls (from
s7's own I/O primitives, or debug output) either go nowhere or need a
narrow, explicit host callback (e.g. a single custom syscall number that
copies a bounded buffer out to a Flow-owned log sink) — deliberately not
decided here, since it depends on whether s7's `stdout`/`stderr` port
gets disabled at the Scheme level (script content has no business doing
raw I/O either, per the same isolation driver) or redirected to a
host-captured string port instead.

## VMCALL boundary (item 5)

`machine.vmcall("function_name", args...)` looks up a symbol by name and
calls it with C-ABI argument marshalling — the same shape
`fanout-core`'s Ffi.lean already exports (`fanout_pub_targets`, etc.) and
the same shape `libriscv_vendor_test.cpp`'s guest, `fib.rv64.elf`, could
be called through, if it exported a named entry point. Prerequisite noted
in `VMCALL.md`: never let the guest's `main()` return normally (that
would run global destructors and leave the machine unreliable for repeat
calls) — the guest calls `_exit()` explicitly instead, and stays alive
for repeat VMCALLs afterward. This matters here specifically because a
Flow actor is expected to call into the same guest instance
repeatedly (per-fanout-decision, not per-process), not spin up a fresh
machine per call — `fanout-core`'s own FFI keeps one process-wide
`IO.Ref State` for exactly this reason.

No concrete guest-side function names or argument shapes are decided
here — that depends on what scripted content actually looks like (mission
scripts vs. loot tables vs. NPC behavior have different natural call
shapes), which is unspecified beyond the examples ADR 0006 already lists.
This section only fixes the calling *mechanism* the eventual content
design should target: `vmcall("<entry point>", <host-supplied
deterministic inputs>...)`, fuel-limited (item 7), against a guest that
never touches real I/O (item 6).
