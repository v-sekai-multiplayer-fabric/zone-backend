---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: s7-compiler, guestvalue, trampoline, nif
---

# 0021 GuestValue handle syscalls: structured terms through the trampoline

## Context

[[0018-bignum-beam-integers-host-call-trampoline]] gave compiled s7
programs one escape hatch to the host (ecall 600: op, a, b -> result),
used only for checked arithmetic. The GuestValue design
([[0019-s7-aot-compiler-no-cross-toolchain]]) reserved the handle tag
(`0x2`) for host-owned structured values, godot-sandbox
CurrentState-style, but no operations existed — Elixir lists, tuples,
maps, binaries, and atoms could not cross into compiled guests.

## Decision Outcome

Reuse the trampoline unchanged: ops 16+ on the same ecall are
structural operations on handles. No new syscall, no NIF change, no
guest-memory serialization — the real terms stay in the Elixir
GenServer's per-call table (or the `__int128`-era reference table,
now a tagged `HostValue` variant, for the C++ oracle/harnesses).
New IR op `HOST_OP` (unconditional slow path — the value lives
host-side, so there is nothing to inline). New primitives: `car`,
`cdr`, `cons`, `list`, `length`, `list-ref`, `pair?`, `vector-ref`/
`vector-length` (Elixir tuples), `hash-table-ref` (maps, missing key
-> `#f` as in s7), `string-length` (binaries, bytes). `null?` is pure
guest (nil is an immediate); the empty list IS nil, so Elixir `[]`
and `nil` collapse to one value and decode as `nil`. Atoms are
interned per call — same atom, same handle — so guest `eq?` is
meaningful on them.

## Consequences

Good: full structured-argument capability with zero ABI or NIF
changes; three-way verification extends to every new op (IR oracle ==
libriscv == expected, plus real-s7 fidelity for the list subset).
Bad: every structural op costs a full host round trip (fine for the
ReBAC use case — fetch a few fields, compute, return); deep structural
equality for map keys is content-equality only for atoms/binaries/
bignums; no mutation ops (hash-table-set! etc.) — guests read host
data and build lists, nothing else, until a real need appears.

## Confirmation

verify_s7 adds nine handle-value tests (sum over a list, list-ref,
cons/list round-trip decoded structurally, tuple/map/binary ops,
interned-atom eq?); verify_s7_fidelity adds eight list-op programs
diffed against the real s7 interpreter; program_test.exs proves the
Elixir boundary (lists in, guest-built lists out as real terms, tuple/
map/binary/atom ops, missing-key -> false).
