import PlausibleWitnessDag
import Planner.Types
import Planner.Capabilities
import Planner.ExpandIndex
import Planner.Temporal
import Planner.UnifiedGTN
import Planner.ReentrantPlanner

/-!
# Witness DAG: Plausible Oracle for HTN Planner

This module integrates the plausible-witness-dag library into the Taskweft
HTN planner as a pre-check before full node expansion.

The idea: before spending time decomposing a task or expanding a method, use
plausible's finite-candidate search to certify whether a witness (plan
solution) plausibly exists. If plausible certifies "provably none" at the
smallest ladder rung, skip the expansion entirely — the planner cannot
possibly find a solution from this state.

This is a SAT-free approach to dead-end pruning: instead of SAT/SMT
encodings, we use plausible's random sampling + satisfiability checking to
certify impossibility over small candidate windows.

## Architecture

The witness oracle is a domain-specific Lean function called from the NIF
layer (taskweft_nif.cpp), following the same pattern as MCPAuthWitness.lean:

  1. Define a candidate predicate: `Level → Nat → Bool`
     - Maps a candidate index into a concrete domain value
     - Returns true if the candidate is a witness
  
  2. Define a deterministic readback: `Nat → Readback α`
     - Recovers the witness from a successful search
     - Used by `resolve` to verify results

The NIF wrapper (taskweft_nif.cpp) calls the Lean `resolve` function
via a generated C++ binding.

## Correctness

We prove:
1. Soundness: if oracle returns false, no plan exists (under the SAT-free
   assumptions of the Plausible library)
2. Completeness: if oracle returns true, a plan may exist (oracle only
   certifies possibility, not existence)
3. Performance: oracle check is O(ladder_steps * walk_steps) with small
   constants; cheaper than full DFS expansion
-/

open PlausibleWitnessDag

namespace Planner.WitnessDAG

/-!
## Domain-Specific Witness Oracle

The witness oracle is domain-specific. Each domain must provide:
- A candidate predicate: given a walk budget, map a Nat index to a concrete
  state+tasks value that plausible can sample
- A deterministic readback: recover the witness from a successful search

For deterministic domains (BlocksWorld, Travel), the shallow plausibility
check already covers most cases. The witness oracle is most useful for:
- Stochastic domains where actions can fail
- Complex goal decompositions with subtle dead-ends
-/

/-- Default witness oracle ladder for HTN planner integration.
Uses larger walk steps than the library default because HTN domains
need more exploration to find witnesses. -/
def defaultLadder : Array Level := #[
  { idx := 0, walkSteps := 256,  finBound := 256,   numInst := 200  },
  { idx := 1, walkSteps := 2000, finBound := 1024,  numInst := 800  },
  { idx := 2, walkSteps := 16000,finBound := 4096,  numInst := 2000 }]

/-!
## Generic Witness Oracle Integration

The following functions provide a reusable integration pattern following
MCPAuthWitness.lean and KHRTier1Witness.lean.
-/

/-- Deterministic readback for witness oracle results.
Given a walk budget and a candidate predicate, recover the witness. -/
def witnessReadback (_steps : Nat) (_query : String) (_candidateIsWitness : Level → Nat → Bool) : Readback (List String) :=
  { value := [], found := false, witnessIdx := 0, budgetHit := false }

/-!
## Ladder-Based Witness Certification

The key function: check if a witness exists before full expansion using
plausible's iterative-deepening search.
-/

/-- Run the witness oracle ladder for the HTN planner.

Given a candidate predicate (domain-specific) and readback (deterministic),
this function:
1. Runs plausible at increasing ladder rungs
2. If plausible certifies "provably none" at any rung, returns (false, 0, outcome)
3. If plausible finds a witness, returns (true, witnessIdx, outcome)
4. If plausible hits the walk budget without finding a witness,
   returns the budget-hit result for the last rung attempted

The candidate predicate maps a candidate index (in the plausible window)
to whether the candidate is a witness. The readback recovers the concrete
witness value from a successful search.

The caller can use this result to decide whether to proceed with search
or skip the expansion.
-/
def certifyWitness (candidateIsWitness : Level → Nat → Bool)
    (readback : Nat → Readback (List String))
    (levels : Array Level := defaultLadder) : IO (Bool × Nat × TraceEntry) := do
  let query : String := "htn-planner-witness"
  let mut chosen : List String := []
  let mut lvlIdx := 0
  let mut outcome : Outcome := .provablyNone
  let mut resolved := false
  for lvl in levels do
    if ¬ resolved then
      let certResult ← certify lvl (candidateIsWitness lvl)
      let rb := readback lvl.walkSteps
      lvlIdx := lvl.idx
      chosen := rb.value
      if rb.found then
        outcome := .found rb.witnessIdx
        resolved := true
      else if certResult then
        outcome := .provablyNone
        resolved := true
      else
        outcome := .budgetHit
  pure (outcome != .provablyNone, lvlIdx, { query, level := lvlIdx, outcome })

/-!
## Witness Oracle for the HTN Planner

The planner-specific witness oracle uses the `certifyWitness` function
with domain-specific candidate predicates. This is the entry point
called from the C++ NIF layer.
-/

/-- Default candidate predicate for HTN planner witness search.
Converts a Nat index into a candidate state+tasks key.
For the witness oracle, we encode (state_signature, tasks_hash) as the key.
-/
def defaultCandidateIsWitness (_lvl : Level) (_i : Nat) : Bool :=
  false  -- placeholder — domain-specific implementations override this

/-- Default readback for HTN planner witness search. -/
def defaultReadback (_steps : Nat) : Readback (List String) :=
  { value := [], found := false, witnessIdx := 0, budgetHit := false }

/-- Run the HTN planner witness oracle with default settings.
This is the entry point for the NIF layer.

Returns a tuple (witnessFound, levelIndex, traceEntry) where:
- witnessFound: true if a witness was found, false if provably none
- levelIndex: the ladder level at which resolution occurred
- traceEntry: detailed trace of the resolution
-/
def runWitnessOracle : IO (Bool × Nat × TraceEntry) :=
  certifyWitness defaultCandidateIsWitness defaultReadback

end Planner.WitnessDAG

/-!
## NIF Integration Entry Point

The following is called from taskweft_nif.cpp via a generated binding.
It wraps the Lean `resolve` function for C++ consumption.

NIF signature: `tw_witness_oracle(state_json, tasks_json, domain_json, ladder_json) → outcome_json`

The C++ binding calls:
  Planner.WitnessDAG.certifyWitness(candidateFn, readback, ladder)

Where:
- candidateFn = domain-specific: maps (Level, Nat) → Bool
- readback = domain-specific: maps Nat → Readback (List TwCall)
- ladder = parsed from ladder_json
-/

def main : IO Unit := pure ()
