---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: s7-compiler, bignum, licensing
---

# 0018 Bignums via the BEAM's own integers, through a host-call trampoline

## Context

The s7 compiler (`c_src/s7/`) supports fixnums only (61-bit, tag `000`).
Real s7 in multiprecision mode promotes transparently; the user wants
bignum support under a hard MIT/Apache-2 vendoring constraint. Options
considered, in order:

1. **GMP** (s7's own upstream choice) — rejected: dual LGPLv3/GPLv2,
   static vendoring carries relink/source obligations incompatible with
   the license bar.
2. **libtommath v1.3.0** (Unlicense/public domain, verified) — briefly
   vendored, then superseded the same session by the user's better
   observation:
3. **The BEAM already has bignums.** Elixir integers are arbitrary-
   precision natively, and the host side of every sandbox ecall *is*
   the BEAM node. `erl_nif` exposes no bignum API (int64/uint64 only —
   confirmed against both fine.hpp copies earlier this session), so
   even a C++-side bignum library would need binary marshalling at the
   NIF boundary anyway.

## Decision Outcome

**Bignum arithmetic is delegated to Elixir via a host-call trampoline**,
no numeric library vendored at all:

- Guest fixnum ops gain overflow checks. On overflow (or a bignum-handle
  operand), the guest ecalls; the syscall handler stops the
  `libriscv::Machine` (whose state persists inside the NIF resource —
  no serialization needed) and the NIF returns `{:host_call, op, args}`
  to the owning `WeftWarpBurrito.Sandbox` GenServer.
- Elixir computes the operation with native integers (`a + b`), then
  calls a resume NIF that writes the result back and continues the same
  machine execution. Results demote to fixnums when they fit 61 bits
  (matching s7's promotion/demotion); otherwise they become handles.
- The handle table itself lives in **Elixir GenServer state as a map of
  real terms**, not a C++ table — the same trampoline serves the whole
  GuestValue plan (List/Tuple/Map/Binary/Atom ops all compute against
  native Elixir values), collapsing what would have been a C++
  reimplementation of term operations into plain Elixir.

## Consequences

Good: zero vendored numeric code; exact BEAM semantics for free
(comparison, printing, interop); one mechanism (trampoline) serves
bignums and every other handle type; the C++ layer stays thin
(marshal scalars, stop/resume). Bad: each host-call round-trips
NIF→Elixir→NIF, slower than an in-C++ handler — acceptable because
overflow and handle ops are the rare path and the fixnum fast path is
unchanged; the trampoline also means a capability call is no longer a
single NIF invocation, changing `Sandbox`'s GenServer loop shape.

## Confirmation

Decision recorded ahead of implementation; the trampoline + overflow
checks land with the handle-table/GuestValue syscall increment (PERT
task C), with differential tests against real s7 semantics (fixnum
boundary at ±2^60, promotion/demotion round-trips). The libtommath
subtree was removed in the same branch that briefly added it.
