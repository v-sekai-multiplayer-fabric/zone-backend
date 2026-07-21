---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: s7-compiler, bitwise
---

# 0024 Bitwise primitives: `logand`, `logxor`, `ash`

## Context

`c_src/guest/content/loot.scm`'s xorshift32 RNG (already Lean-verified,
hand-ported, running today only via the *interpreted* real-s7 path) needs
`logand`/`logxor`/`ash`. Our AOT compiler had no bitwise primitives — only
the IR's internal `AND`/`OR`/`XOR`/`SLL`/`SRA` ops, used solely for
GuestValue tag manipulation.

## Decision Outcome

Expose `logand`/`logxor` as direct primitives on tagged fixnums — no
untag/retag needed, since bitwise ops commute with the tag's left-shift
(zero low bits don't interact). `ash` needs care: left shift (`SLL`) also
works directly on tagged values, but right shift does not — it must
untag, shift, then retag, or tag bits bleed into the result.

## Consequences

Zero new host ops, zero IR changes — pure guest ALU, exactly as fast as
the RISC-V `AND`/`SLL`/`SRA` instructions already emitted for tagging.

## Confirmation

`verify_s7` covers `logand`/`logxor`/`ash` (positive and negative shift)
three ways (IR oracle == RISC-V == expected).
