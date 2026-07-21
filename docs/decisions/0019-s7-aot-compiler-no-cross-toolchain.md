---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: s7-compiler, riscv, repo-structure
---

# 0019 s7 AOT compiler: from-scratch s7-subset -> RISC-V, no cross-toolchain

## Context

The `riscv-none-elf-gcc` cross-compiler was this repo's most painful
build dependency: a 465MB download, no scoop package, CI-only
verification, and upstream-documented `MAX_PATH` failure modes on
Windows. The user's direction: write our own compiler, modeled on
`v-sekai-multiplayer-fabric/godot-sandbox-gdscript-compiler` (which
proved the technique — hand-rolled RV64 encoding + hand-rolled ELF
layout, zero external `as`/`ld`), targeting the s7 Scheme dialect the
sandbox guest already speaks (`c_src/thirdparty/s7` is the interpreter;
same language, two execution strategies).

## Decision Outcome

`c_src/s7/`: an ahead-of-time compiler for a documented s7 subset,
running as an ordinary host-side tool (any C++ compiler) and emitting
RISC-V ELF binaries directly. Pipeline: s-expression reader -> vreg IR
-> IR interpreter (correctness oracle) -> RV64IM encoder + stack-slot
codegen -> multi-symbol ELF builder. Every test is cross-checked three
ways (oracle == libriscv execution == hand-computed value) so lowering
bugs and encoding bugs can never masquerade as each other.

Shipped so far: fixnums/booleans/nil (tagged 64-bit GuestValues),
`define`/`if`/`let`/`let*`/`begin`/`set!`/`and`/`or`, arithmetic and
comparisons, mutual recursion, closures (lambda lifting, by-value
capture, heap records, `auipc`+`jalr` indirect calls), and checked
arithmetic with transparent bignum promotion via the host-call ABI
([[0018-bignum-beam-integers-host-call-trampoline]]). Documented
non-goals for now: floats, strings/pairs as guest values (arriving as
host-owned handles per the GuestValue roadmap), `set!` on captured
variables, TCO, macros (s7 itself has no `syntax-rules`), `call/cc`.

## Consequences

Good: zero external cross-toolchain for guest capabilities written in
the subset; the whole pipeline is ~1500 lines of in-repo C++ iterating
at local-build speed. Bad: the subset is far from full s7 — the
interpreter guest remains the semantics reference and fallback; the
stack-slot codegen trades performance for correctness (a register
allocator is a known later optimization, not a requirement).

## Confirmation

26/26 tests pass locally (clang + ninja, no riscv-none-elf-gcc
anywhere), including fact/fib recursion, closure composition and
nested capture, and bignum round-trips (`(quotient (fact 25)
(fact 24))` = 25) through the reference host table. Fidelity diffing
against the real s7 interpreter (Stage 3 of the roadmap) is the next
verification tier.
