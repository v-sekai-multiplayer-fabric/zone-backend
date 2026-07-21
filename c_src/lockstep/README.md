# Lockstep float-determinism proof of concept (RFD 0043)

Not part of the default build (`mix compile`/`make`) -- this is a
manually-run verification exercise proving RFD 0041/0042's chosen
approach (Lean4 spec -> CBMC equivalence checking -> RISC-V -> libriscv
execution) actually works, using `Vector3.dot` as the one worked
example. See `docs/decisions/0043-lockstep-float-determinism-poc.md`
for the full writeup and findings.

## Files

- `vector3.h`/`vector3.c` -- `dot_ref`/`dot_good`/`dot_bad`, the guest
  math functions. Freestanding-compatible (no libc calls), so this
  compiles unmodified as a normal host object and as a RISC-V guest ELF.
- `finite_check.h` -- NaN/infinity check via raw bit inspection (CBMC's
  C parser can't handle this toolchain's mingw `<math.h>`).
- `cbmc_associativity.c` -- the tractable, isolated CBMC equivalence
  proof (pure addition, no multiplication).
- `cbmc_equivalence.c` -- the full `Vector3.dot` equivalence claim
  (intractable for CBMC's default float bit-blasting within a few
  minutes at full double range -- a documented limitation, not a
  disproof).
- `../host_test/verify_float_determinism.cpp` -- loads a RISC-V guest
  ELF into this repo's own vendored `libriscv` and compares its output
  against native execution of the identical source.
- `../../lean/LockstepDeterminism.lean` -- the Lean4 spec these C
  implementations are checked against.

## Reproducing the verification

Requires `lean`/`lake` (already used by this org elsewhere), `cbmc`,
and `riscv-none-elf-gcc` -- none of these are project dependencies;
install them yourself to reproduce this.

```sh
# 1. Lean4 spec: prints test vectors and the non-associativity witness.
lean --run lean/LockstepDeterminism.lean

# 2. CBMC: proves dot_good bit-identical to dot_ref (pure addition,
#    tractable); the reassociated direction is expected NOT to verify
#    (see the RFD for why this direction didn't conclude within a
#    reasonable bound in practice, and the concrete counterexample used
#    instead).
cbmc c_src/lockstep/cbmc_associativity.c --gcc --function main
cbmc c_src/lockstep/cbmc_associativity.c --gcc -DREASSOC_BAD --function main

# 3. Cross-compile the SAME source to a freestanding RISC-V64 guest ELF,
#    once with default compiler flags and once with -ffp-contract=off:
riscv-none-elf-gcc -march=rv64gc -mabi=lp64d -static -O2 -ffreestanding \
  -Wl,--undefined=dot_ref -Wl,--undefined=dot_good -Wl,--undefined=dot_bad \
  -nostartfiles c_src/lockstep/vector3.c -o guest_default.elf
riscv-none-elf-gcc -march=rv64gc -mabi=lp64d -static -O2 -ffreestanding \
  -ffp-contract=off \
  -Wl,--undefined=dot_ref -Wl,--undefined=dot_good -Wl,--undefined=dot_bad \
  -nostartfiles c_src/lockstep/vector3.c -o guest_strict.elf

# 4. Build the libriscv comparison harness and run it against both ELFs
#    (native_default.o/native_strict.o are the same vector3.c, compiled
#    for the host with matching -ffp-contract flags -- see the RFD for
#    why BOTH sides must agree on the flag, not just the guest side):
cmake --build build --target verify_float_determinism
./build/verify_float_determinism guest_default.elf
./build/verify_float_determinism guest_strict.elf
```

## What this proved (see the RFD for the full narrative)

- `dot_ref`/`dot_good` (same evaluation order) are bit-identical between
  native x86-64 and libriscv-interpreted RISC-V64, in every
  configuration tested.
- `dot_bad` (deliberately reassociated) diverges from `dot_ref` on both
  sides as expected -- and, with an input exercising an inexact
  multiplication, ALSO diverges between native and guest at default
  compiler flags (confirmed via `objdump`: the default RISC-V build
  fuses into `fmadd.d`). `-ffp-contract=off` on **both** sides
  eliminates this divergence completely.
- An input relying only on exact multiplications (`1.0 * x`) does NOT
  exercise this risk at all -- an earlier pass of this exact
  verification used only that input and drew a false conclusion from an
  unrelated register-read bug in the harness itself (see the RFD). Test
  with an input that actually rounds.
