---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A -- committed directly, no PR review
labels: sandbox, determinism, lockstep, floating-point, proof-of-concept
---

# 0043 Lockstep float-determinism proof of concept: Lean4 -> CBMC -> RISC-V -> libriscv, worked end-to-end

## Context

RFD 0041 chose the verification pipeline (Lean4 spec -> CBMC/`hw-cbmc`
equivalence checking) and RFD 0042 chose the float-determinism strategy
(disciplined native IEEE 754 float, not banned/emulated/fixed-point) --
both by scoring and reasoning, not by building anything. This RFD is
that pipeline actually built, once, end-to-end, against a single
concrete primitive (`Vector3.dot`), plus toolchain setup notes and an
honest account of a real bug found and fixed along the way.

**Toolchain**: `lean`/`lake` (already installed), `riscv-none-elf-gcc`
(already installed, globally -- this is the same cross-compiler RFD
0039 removed as a *project build dependency*; using it here to produce
a hand-built verification artifact does not reintroduce that
dependency into `mix compile`/CI). `cbmc` was not installed; its
official Windows MSI installer requires admin privileges this session
didn't have (`Error 1303`), so it was extracted directly from the MSI
archive with 7-Zip instead -- a real, reusable workaround worth
recording, not just "somehow got it working."

## What was built

- `lean/LockstepDeterminism.lean` -- the spec: `Vector3.dot` with a
  fixed evaluation order, `(x*x' + y*y') + z*z'`, plus a concrete
  non-associativity witness.
- `c_src/lockstep/vector3.c` -- three C implementations: `dot_ref`
  (matches the spec's order), `dot_good` (same order, written with
  intermediate named values -- proves the equivalence check isn't
  fooled by cosmetic rewrites), `dot_bad` (a *different*, still
  mathematically-equal-over-the-reals association -- kept permanently
  as a regression case, not a one-off).
- `c_src/lockstep/cbmc_associativity.c` -- the tractable core CBMC
  proof: `(p+q)+r` vs. differently-associated forms, isolating pure
  addition from multiplication.
- `c_src/host_test/verify_float_determinism.cpp` -- loads a RISC-V64
  guest ELF (cross-compiled by hand from the identical `vector3.c`)
  into this repo's own vendored `libriscv`, and compares its output
  against native execution.
- `c_src/lockstep/README.md` -- exact reproduction commands.

## Findings

**1. CBMC equivalence checking works, but only at a bounded scope.**
The pure-addition-associativity claim (`cbmc_associativity.c`, 3
nondet doubles bounded to ±1000) verifies in well under two minutes:
`dot_good`-shaped reassociation (same order, different syntax) proves
equivalent; a differently-associated form does not (see below for how
that negative case was actually confirmed). The full 6-variable
`Vector3.dot` claim (`cbmc_equivalence.c`) did not conclude within a
240-second bound at double precision, even with inputs bounded to
±1000 -- CBMC's default float bit-blasting doesn't scale to this
many combined multiply/add operations in reasonable time. This is a
real, documented limitation of the *equivalence-checking step
specifically* (not of the underlying determinism claim -- see finding
3, which validates the same claim by direct execution instead).

**2. The reassociated case's counterexample was found by direct
computation, not by waiting for CBMC's SAT search.** Both the
`cbmc_associativity.c -DREASSOC_BAD` direction and the full
`dot_bad`-vs-`dot_ref` direction failed to conclude (SAT search for a
counterexample, as opposed to UNSAT for the "good" direction, took
meaningfully longer in this CBMC version) within a 240-second bound.
Rather than wait longer, Lean4's `#eval`/`--run` was used to directly
compute several classic candidates and confirm `(1.0, 1.0e16, -1.0e16)`
is a real, concrete witness where `(p+q)+r` and `p+(q+r)` diverge
(`0.0` vs. `1.0`) -- cheap, fast, and just as valid a demonstration for
this RFD's purpose. Full symbolic CBMC coverage of the "bad" direction
remains open, not attempted further here.

**3. `dot_ref`/`dot_good` are bit-identical between native x86-64 and
libriscv-interpreted RISC-V64, in every configuration tested** --
confirming RFD 0042's central claim by actual execution, the step that
RFD's own "Non-decision" section called for. This held for both the
default compiler flags and with `-ffp-contract=off` on both sides, on
two different input sets.

**4. A real, confirmed cross-environment divergence for `dot_bad`,
and confirmation that RFD 0042's recommended fix eliminates it.**
Using an input set where the multiplications are genuinely inexact in
binary (`0.1 * 0.11` etc., not `1.0 * x`), `dot_bad` produced
**different bit patterns** on native x86-64 (`0.21300000000000002`)
vs. libriscv-hosted RISC-V64 (`0.21299999999999999`) at each platform's
default compiler flags -- confirmed via `objdump` to be `fmadd.d`
(fused multiply-add) contraction on the RISC-V side that the native
build didn't perform. Rebuilding **both** sides with `-ffp-contract=off`
made all three functions, including `dot_bad`, agree bit-for-bit. This
is `-ffp-contract` actually mattering, empirically, not a theoretical
risk cited from RFD 0042's literature search.

**5. That divergence does NOT show up with every input.** The first
input set tried (`1.0, 1.0, 1.0, 1.0, 1.0e16, -1.0e16`) -- chosen to
demonstrate non-associativity cleanly -- happens to involve only exact
multiplications (`1.0 * anything` never rounds), so FMA contraction
changes nothing for it; `dot_bad` matched across native/guest at
default flags for *this* input alone. **A verification exercise that
only tests exact-multiplication inputs will not catch this risk** --
`c_src/host_test/verify_float_determinism.cpp` now runs both input
sets for exactly this reason, not just the clean pedagogical one.

## A bug found and fixed along the way, documented rather than
## quietly corrected

An earlier pass of this verification appeared to show `dot_bad`
diverging between native and guest even on the "exact multiplication"
input set -- which would have contradicted finding 5 above. That
result was **wrong**: `verify_float_determinism.cpp` read the guest's
return value from `getfl(0)`, but RISC-V's `fa0` (where a `double`
return value actually lands) is f-register **10** (`REG_FA0`), not
register 0 (`ft0`, an unrelated scratch register the guest functions
never touch). Every "guest" value this bug produced was silently a
stale/default `0.0` -- which coincidentally equalled the correct answer
for `dot_ref`/`dot_good` on that specific input (both happen to
evaluate to `0.0`), making them look like they matched, while `dot_bad`
(whose correct answer is `1.0`) looked like a mismatch that wasn't
real. Caught by a targeted sanity check (`dot_ref(1,2,3,4,5,6)` via
`libriscv`, expected `32`, got `0`) once the "FMA contraction" story
seemed suspicious against the `-ffp-contract=off`-on-both-sides result
that should have resolved it but didn't. Fixed by reading
`getfl(riscv::REG_FA0)` instead of `getfl(0)`; the comment explaining
why is left permanently in the source, not just in this RFD or a
commit message, since the exact same mistake (assuming ABI register
index 0 == argument/return position 0) is easy to make again.

**The lesson generalizes beyond this one bug**: a verification harness
that "confirms" a security- or determinism-relevant finding needs the
same skepticism as the code it's checking. A too-convenient early
result (in this case, one that lined up with what RFD 0042 predicted)
was still checked with an independent sanity test before being trusted.

## Confirmation

`c_src/host_test/verify_float_determinism.cpp`, built via
`cmake --build build --target verify_float_determinism` (not part of
the default build), run against both a default-flags and a
`-ffp-contract=off` guest ELF -- output reproduced in
`c_src/lockstep/README.md`. `dot_ref`/`dot_good` bit-identical across
native/libriscv in all four combinations tried (2 input sets x 2 flag
configurations); `dot_bad` diverges exactly when expected (inexact-
multiplication input, mismatched or default `-ffp-contract`) and never
otherwise.
