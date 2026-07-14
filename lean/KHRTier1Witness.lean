-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 K. S. Ernest (iFire) Lee
import PlausibleWitnessDag

/-!
# KHR_interactivity Tier 1 — decomposition witness certification

"Write Lean first, then C++, then cross-check" for the `taskweft_nif` Tier 1
node catalog (see `docs/adr/0001-gltf-interactivity-node-shape.md` and the
KHR_interactivity Tier 1 plan): this file is the **Lean reference model**,
written *before* the C++ implementation in
`deps/taskweft_nif/standalone/tw_loader.hpp`. It is later cross-checked
against the compiled C++ via `test/taskweft/khr_interactivity_prop_test.exs`
(the golden vectors this file prints are pasted there as expected values).

Per the spec, `math/smoothStep` is *defined* in terms of `math/min` and
`math/saturate` (02_node_types.md, "Smooth Step") — there is no independent
"reference formula" to check the decomposition against, so instead of a
literal cross-check we certify the invariants the spec *implies* must hold
(saturated output range, boundary values, length-preservation for
`math/rotate2D`) using `PlausibleWitnessDag`'s iterative-deepening search —
reusing the same search-for-a-counterexample technique as
`MCPAuthWitness.lean`, rather than a hand-rolled brute-force loop over a
fixed sample grid.

Note: `Float` in Lean 4 is not kernel-reducible (`@[extern]`), so unlike
`MCPAuthWitness.lean`'s ReBAC facts (`decide`-checked), the concrete facts
here are runtime-checked in `run` rather than `decide`-checked.
-/

open PlausibleWitnessDag

namespace KHRTier1Witness

-- ---------------------------------------------------------------------------
-- Reference model (mirrors the C++ decomposition to be written in
-- tw_loader.hpp's kNodeTypes()/eval_node()).
-- ---------------------------------------------------------------------------

/-- math/saturate — clamp to [0,1]. -/
def saturate (x : Float) : Float :=
  if x < 0.0 then 0.0 else if x > 1.0 then 1.0 else x

/-- math/smoothStep(a, b, c) — Hermite interpolation, per spec defined via
    math/min + math/saturate. -/
def smoothStep (a b c : Float) : Float :=
  let t := saturate ((c - min a b) / Float.abs (b - a))
  t * t * (3.0 - 2.0 * t)

/-- math/rotate2D(a = (ax, ay), angle) — 2D rotation. -/
def rotate2D (ax ay angle : Float) : Float × Float :=
  (ax * Float.cos angle - ay * Float.sin angle,
   ax * Float.sin angle + ay * Float.cos angle)

-- ---------------------------------------------------------------------------
-- Deterministic candidate-space derivation: Nat index -> sample inputs.
-- ---------------------------------------------------------------------------

/-- Map a candidate index into a spread-out float in roughly [-8, 8]. -/
def idxToFloat (i : Nat) : Float :=
  (Float.ofNat (i % 17) - 8.0) + (Float.ofNat ((i / 17) % 5)) / 5.0

def smoothStepInputs (i : Nat) : Float × Float × Float :=
  (idxToFloat i, idxToFloat (i + 5), idxToFloat (i + 11))

def rotate2DInputs (i : Nat) : Float × Float × Float :=
  (idxToFloat i, idxToFloat (i + 3), idxToFloat (i * 7 % 251) / 40.0)

-- ---------------------------------------------------------------------------
-- Invariants: candidateIsWitness returns true when the candidate is a
-- COUNTEREXAMPLE (violates the invariant). We want `resolve` to report
-- `provablyNone` — i.e. no counterexample exists in the searched window —
-- which certifies the decomposition.
-- ---------------------------------------------------------------------------

/-- smoothStep's output must stay within [0,1] (saturate guarantees this,
    barring the degenerate a=b case which the spec leaves undefined/NaN and
    which we exclude from the search). -/
def smoothStepRangeViolation (_lvl : Level) (i : Nat) : Bool :=
  let (a, b, c) := smoothStepInputs i
  if a == b then false
  else
    let v := smoothStep a b c
    ! (v >= 0.0 && v <= 1.0)

/-- rotate2D preserves vector length (rotation is an isometry). -/
def rotate2DLengthViolation (_lvl : Level) (i : Nat) : Bool :=
  let (ax, ay, angle) := rotate2DInputs i
  let (x, y) := rotate2D ax ay angle
  let lenBefore := Float.sqrt (ax * ax + ay * ay)
  let lenAfter := Float.sqrt (x * x + y * y)
  Float.abs (lenAfter - lenBefore) > 1.0e-9

def noViolationReadback (_steps : Nat) : Readback Unit :=
  { value := (), found := false, budgetHit := false }

-- ---------------------------------------------------------------------------
-- Golden vectors: printed for pasting into
-- test/taskweft/khr_interactivity_prop_test.exs as literal expected values,
-- closing the "Lean first, then C++, then cross-check" loop.
-- ---------------------------------------------------------------------------

def smoothStepGolden : List (Float × Float × Float × Float) :=
  [ (0.0, 1.0, 0.0, smoothStep 0.0 1.0 0.0)
  , (0.0, 1.0, 1.0, smoothStep 0.0 1.0 1.0)
  , (0.0, 1.0, 0.5, smoothStep 0.0 1.0 0.5)
  , (0.0, 1.0, 0.25, smoothStep 0.0 1.0 0.25)
  , (-2.0, 2.0, 0.0, smoothStep (-2.0) 2.0 0.0)
  , (2.0, -2.0, 0.0, smoothStep 2.0 (-2.0) 0.0) ]  -- a > b: spec note, must still work

def piF : Float := 3.14159265358979323846

def rotate2DGolden : List (Float × Float × Float × Float × Float) :=
  [ (1.0, 0.0, piF / 2.0,
      (rotate2D 1.0 0.0 (piF / 2.0)).1, (rotate2D 1.0 0.0 (piF / 2.0)).2)
  , (1.0, 0.0, piF,
      (rotate2D 1.0 0.0 piF).1, (rotate2D 1.0 0.0 piF).2)
  , (3.0, 4.0, 0.5,
      (rotate2D 3.0 4.0 0.5).1, (rotate2D 3.0 4.0 0.5).2) ]

def run : IO Unit := do
  -- Concrete boundary facts (runtime-checked: Float is not kernel-reducible,
  -- so these can't be `decide`d the way MCPAuthWitness's ReBAC facts are).
  unless Float.abs (smoothStep 0.0 1.0 0.0 - 0.0) < 1.0e-12 do
    throw (IO.userError "smoothStep(0,1,0) should be 0")
  unless Float.abs (smoothStep 0.0 1.0 1.0 - 1.0) < 1.0e-12 do
    throw (IO.userError "smoothStep(0,1,1) should be 1")
  unless Float.abs (smoothStep 0.0 1.0 0.5 - 0.5) < 1.0e-12 do
    throw (IO.userError "smoothStep(0,1,0.5) should be 0.5 (symmetric Hermite)")

  -- Witness-search certification (searches for a counterexample; none found
  -- within the ladder's window ⇒ certified over the searched space).
  let (_, lvl1, tr1) ← resolve "smoothStep-range" smoothStepRangeViolation noViolationReadback
  IO.println s!"smoothStep range: {repr tr1.outcome} (level {lvl1})"
  if tr1.outcome == .provablyNone then
    IO.println "OK: no smoothStep range-violation witness found"
  else
    throw (IO.userError "smoothStep range invariant violated — do not implement the C++ this way")

  let (_, lvl2, tr2) ← resolve "rotate2D-length" rotate2DLengthViolation noViolationReadback
  IO.println s!"rotate2D length: {repr tr2.outcome} (level {lvl2})"
  if tr2.outcome == .provablyNone then
    IO.println "OK: no rotate2D length-violation witness found"
  else
    throw (IO.userError "rotate2D is not length-preserving — do not implement the C++ this way")

  IO.println "-- golden vectors (a, b, c, smoothStep) --"
  for (a, b, c, v) in smoothStepGolden do
    IO.println s!"{a} {b} {c} -> {v}"

  IO.println "-- golden vectors (ax, ay, angle, x, y) --"
  for (ax, ay, angle, x, y) in rotate2DGolden do
    IO.println s!"{ax} {ay} {angle} -> {x} {y}"

  IO.println "OK: KHR Tier 1 decomposition witnesses certified"

end KHRTier1Witness

def main : IO Unit := KHRTier1Witness.run
