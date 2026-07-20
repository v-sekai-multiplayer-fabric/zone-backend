import Planner.Types

/-!
# Planner Failure Cache: Soundness, Completeness, and Performance

This module models the failure-cache optimization used by the C++ planner:
if a `(state_signature, tasks_signature)` key has already been proven to fail,
skip re-exploring it.

We prove:
1. **Soundness**: cache-guarded search never returns a false witness.
2. **Completeness**: if the cache only stores true failures, any real witness
   is still found.
3. **Performance**: cache checks are never worse in this one-step cost model,
   and are strictly better on cache hits with nonzero expansion cost.
-/

namespace Planner.FailCache

abbrev Key := String
abbrev Cache := List Key

/-- Abstract witness predicate for a search key. -/
abbrev Search := Key → Prop

/-- Cache validity: every cached key is truly unsatisfiable. -/
def ValidCache (search : Search) (cache : Cache) : Prop :=
  ∀ k, k ∈ cache → ¬ search k

/-- Cache-guarded search: skip immediately on cache hit, otherwise run search. -/
def cachedSearch (search : Search) (cache : Cache) (k : Key) : Prop :=
  k ∉ cache ∧ search k

/-- Soundness: any witness returned by cached search is a true witness. -/
theorem cached_sound (search : Search) (cache : Cache) (k : Key) :
    cachedSearch search cache k → search k := by
  intro h
  exact h.right

/-- Completeness under a valid cache: true witnesses are never pruned. -/
theorem cached_complete
    (search : Search) (cache : Cache)
    (hvalid : ValidCache search cache)
    (k : Key) :
    search k → cachedSearch search cache k := by
  intro hk
  have hnotin : k ∉ cache := by
    intro hin
    exact (hvalid k hin) hk
  exact And.intro hnotin hk

/-- A tiny one-step cost model: 1 for the check, plus expansion on miss. -/
def stepCost (cache : Cache) (expandCost : Key → Nat) (k : Key) : Nat :=
  if k ∈ cache then 1 else Nat.succ (expandCost k)

/-- Baseline cost without a failure cache. -/
def baselineCost (expandCost : Key → Nat) (k : Key) : Nat :=
  Nat.succ (expandCost k)

/-- Failure cache check is never worse than baseline. -/
theorem stepCost_le_baseline
    (cache : Cache) (expandCost : Key → Nat) (k : Key) :
    stepCost cache expandCost k ≤ baselineCost expandCost k := by
  by_cases hk : k ∈ cache
  · simp [stepCost, baselineCost, hk]
  · simp [stepCost, baselineCost, hk]

/-- On a cache hit with nonzero expansion work, cache is strictly better. -/
theorem stepCost_strict_on_hit
    (cache : Cache) (expandCost : Key → Nat) (k : Key)
    (hk : k ∈ cache) (hexp : 0 < expandCost k) :
    stepCost cache expandCost k < baselineCost expandCost k := by
  unfold stepCost baselineCost
  simp [hk]
  exact hexp

end Planner.FailCache
