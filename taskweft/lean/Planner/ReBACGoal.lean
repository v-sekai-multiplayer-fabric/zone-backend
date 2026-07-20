import Planner.Types
import Planner.Capabilities
import Planner.ReBACCorrectness

/-!
# ReBAC-backed Unigoal / Multigoal

Replaces the unigoal `(var, arg, val)` equality check with a full ReBAC
relation-expression check, supporting all relation combinators.

## Mapping

  unigoal `('loc', 'c1', 'loc2')` → `checkRelationExpr graph "c1" (.base LOC) "loc2" fuel`

  union goal: `checkRelationExpr graph s (.union (.base OWNS) (.base CONTROLS)) o fuel`

A block `c1 IS_MEMBER_OF SomeGroup` where `SomeGroup --[LOC]--> loc2` satisfies
any base-relation goal without a direct edge (type inheritance via IS_MEMBER_OF).

## Relation to TwGoalBinding (C++)

  TwGoalBinding { var = "LOC",   key = "c1", desired = "loc2" }
  → plain string → auto-wrapped as {"type":"base","rel":"LOC"}

  TwGoalBinding { var = "{\"type\":\"union\",...}", key = "c1", desired = "loc2" }
  → parsed as full RelationExpr JSON → check_expr call

Goals and multigoals continue to work: a multigoal is a conjunction and
the planner iterates unsatisfied bindings with backtracking as before.
-/

namespace ReBACGoal

open RelationType ReBACCorrectness

-- ── Unigoal: full RelationExpr ───────────────────────────────────────────────

/-- A unigoal: (subject, relation-expression, object).
    `expr` may be any `RelationExpr` — base, union, intersection,
    difference, or tuple_to_userset. -/
structure UniGoal where
  subj : Entity
  expr : RelationExpr
  obj  : Entity
  deriving DecidableEq, Repr

/-- A multigoal is a conjunction of unigoals. -/
abbrev MultiGoal := List UniGoal

-- ── Satisfaction ─────────────────────────────────────────────────────────────

def uniSatisfied (graph : List Relationship) (fuel : Nat) (g : UniGoal) : Bool :=
  checkRelationExpr graph g.subj g.expr g.obj fuel

def multiSatisfied (graph : List Relationship) (fuel : Nat) (gs : MultiGoal) : Bool :=
  gs.all (uniSatisfied graph fuel)

-- ── 1. Base-expression soundness ─────────────────────────────────────────────

/-- A direct edge satisfies a `.base rel` unigoal. -/
theorem uniSatisfied_base_direct (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (hmem : ⟨s, rel, o⟩ ∈ graph) :
    uniSatisfied graph (n + 2) ⟨s, .base rel, o⟩ = true :=
  checkRelationExpr_base_sound graph s rel o (n + 1)
    (hasCapability_direct graph s rel o n hmem)

/-- IS_MEMBER_OF inheritance for `.base rel` goals. -/
theorem uniSatisfied_base_inherited (graph : List Relationship)
    (s grp : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (hmem : ⟨s, IS_MEMBER_OF, grp⟩ ∈ graph)
    (hgrp : hasCapability graph grp rel o n = true) :
    uniSatisfied graph (n + 2) ⟨s, .base rel, o⟩ = true := by
  simp only [uniSatisfied, checkRelationExpr_base_eq]
  exact hasCapability_member_trans graph s grp rel o n hmem hgrp

-- ── 2. Union goals ───────────────────────────────────────────────────────────

/-- If the left branch of a union is satisfied at fuel `n`, the union goal
    is satisfied at fuel `n + 1`. -/
theorem uniSatisfied_union_left (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : checkRelationExpr graph s a o n = true) :
    uniSatisfied graph (n + 1) ⟨s, .union a b, o⟩ = true :=
  checkRelationExpr_union_left graph s a b o n h

/-- If the right branch of a union is satisfied at fuel `n`, the union goal
    is satisfied at fuel `n + 1`. -/
theorem uniSatisfied_union_right (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : checkRelationExpr graph s b o n = true) :
    uniSatisfied graph (n + 1) ⟨s, .union a b, o⟩ = true :=
  checkRelationExpr_union_right graph s a b o n h

-- ── 3. Intersection goals ────────────────────────────────────────────────────

/-- Both branches satisfied implies the intersection goal is satisfied. -/
theorem uniSatisfied_intersection (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (ha : checkRelationExpr graph s a o n = true)
    (hb : checkRelationExpr graph s b o n = true) :
    uniSatisfied graph (n + 1) ⟨s, .intersection a b, o⟩ = true := by
  simp only [uniSatisfied, checkRelationExpr, Bool.and_eq_true]
  exact ⟨ha, hb⟩

/-- Intersection implies each branch. -/
theorem uniSatisfied_intersection_left (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : uniSatisfied graph (n + 1) ⟨s, .intersection a b, o⟩ = true) :
    checkRelationExpr graph s a o n = true := by
  simp only [uniSatisfied, checkRelationExpr, Bool.and_eq_true] at h
  exact h.1

theorem uniSatisfied_intersection_right (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : uniSatisfied graph (n + 1) ⟨s, .intersection a b, o⟩ = true) :
    checkRelationExpr graph s b o n = true := by
  simp only [uniSatisfied, checkRelationExpr, Bool.and_eq_true] at h
  exact h.2

-- ── 4. Tuple-to-userset goals ────────────────────────────────────────────────

/-- A pivot edge `⟨s, pivotRel, mid⟩` plus `mid` satisfying the inner expression
    yields a `tupleToUserset` goal. -/
theorem uniSatisfied_ttu (graph : List Relationship)
    (s mid : Entity) (pivotRel : RelationType) (inner : RelationExpr) (o : Entity) (n : Nat)
    (hpivot : ⟨s, pivotRel, mid⟩ ∈ graph)
    (hinner : checkRelationExpr graph mid inner o n = true) :
    uniSatisfied graph (n + 1) ⟨s, .tupleToUserset pivotRel inner, o⟩ = true := by
  simp only [uniSatisfied, checkRelationExpr]
  apply List.any_eq_true.mpr
  exact ⟨⟨s, pivotRel, mid⟩, hpivot, by simp [hinner]⟩

-- ── 5. Multigoal conjunction ─────────────────────────────────────────────────

@[simp]
theorem multiSatisfied_nil (graph : List Relationship) (fuel : Nat) :
    multiSatisfied graph fuel [] = true := by simp [multiSatisfied]

theorem multiSatisfied_cons (graph : List Relationship) (fuel : Nat)
    (g : UniGoal) (gs : MultiGoal)
    (hg  : uniSatisfied graph fuel g = true)
    (hgs : multiSatisfied graph fuel gs = true) :
    multiSatisfied graph fuel (g :: gs) = true := by
  simp only [multiSatisfied, List.all_cons, Bool.and_eq_true]
  exact ⟨hg, hgs⟩

theorem multiSatisfied_iff (graph : List Relationship) (fuel : Nat) (gs : MultiGoal) :
    multiSatisfied graph fuel gs = true ↔
    ∀ g ∈ gs, uniSatisfied graph fuel g = true := by
  simp [multiSatisfied, List.all_eq_true]

/-- If one goal in a multigoal is unsatisfied, the whole multigoal is unsatisfied. -/
theorem multiSatisfied_false_of_member (graph : List Relationship) (fuel : Nat)
    (gs : MultiGoal) (g : UniGoal)
    (hmem : g ∈ gs) (hfalse : uniSatisfied graph fuel g = false) :
    multiSatisfied graph fuel gs = false := by
  have hne : ¬multiSatisfied graph fuel gs = true := by
    rw [multiSatisfied_iff]
    intro hall
    exact absurd (hall g hmem) (by simp [hfalse])
  cases hb : multiSatisfied graph fuel gs with
  | false => rfl
  | true  => exact absurd hb hne

-- ── 6. Fuel monotonicity ─────────────────────────────────────────────────────
-- Note: `.difference a b` is NOT fuel-monotone (b may become satisfiable at
-- higher fuel, flipping the result). Monotonicity is proved per expression type
-- for the monotone combinators: base, union, intersection, tupleToUserset.

/-- A `.base rel` unigoal is fuel-monotone. -/
theorem uniSatisfied_base_fuel_mono (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity)
    (n : Nat) (h : uniSatisfied graph n ⟨s, .base rel, o⟩ = true) (k : Nat) :
    uniSatisfied graph (n + k) ⟨s, .base rel, o⟩ = true := by
  simp only [uniSatisfied] at *
  cases n with
  | zero => simp [checkRelationExpr] at h
  | succ p =>
    simp only [checkRelationExpr_base_eq] at h ⊢
    have hk : p + k + 1 = p + 1 + k := by omega
    rw [show p.succ + k = (p + k) + 1 from by omega]
    simp only [checkRelationExpr_base_eq]
    exact hasCapability_fuel_mono graph s rel o p h k

/-- A `.union` unigoal is fuel-monotone when each branch is. -/
theorem uniSatisfied_union_fuel_mono (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat) (k : Nat)
    (ha_mono : ∀ m, checkRelationExpr graph s a o m = true →
                    checkRelationExpr graph s a o (m + k) = true)
    (hb_mono : ∀ m, checkRelationExpr graph s b o m = true →
                    checkRelationExpr graph s b o (m + k) = true)
    (h : uniSatisfied graph n ⟨s, .union a b, o⟩ = true) :
    uniSatisfied graph (n + k) ⟨s, .union a b, o⟩ = true := by
  simp only [uniSatisfied] at *
  cases n with
  | zero => simp [checkRelationExpr] at h
  | succ p =>
    simp only [checkRelationExpr, Bool.or_eq_true] at h ⊢
    rw [show p.succ + k = (p + k) + 1 from by omega]
    simp only [checkRelationExpr, Bool.or_eq_true]
    rcases h with ha | hb
    · exact Or.inl (ha_mono p ha)
    · exact Or.inr (hb_mono p hb)

/-- A satisfied multigoal of `.base` goals remains satisfied with more fuel. -/
theorem multiSatisfied_base_fuel_mono (graph : List Relationship)
    (gs : MultiGoal) (n : Nat)
    (h : multiSatisfied graph n gs = true)
    (hall_base : ∀ g ∈ gs, ∃ rel, g.expr = .base rel)
    (k : Nat) :
    multiSatisfied graph (n + k) gs = true := by
  rw [multiSatisfied_iff] at h ⊢
  intro g hg
  obtain ⟨rel, hexpr⟩ := hall_base g hg
  simp only [uniSatisfied] at h ⊢
  have hg_sat := h g hg
  rw [hexpr] at hg_sat ⊢
  cases n with
  | zero => simp [checkRelationExpr] at hg_sat
  | succ p =>
    simp only [checkRelationExpr_base_eq] at hg_sat ⊢
    rw [show p.succ + k = (p + k) + 1 from by omega]
    simp only [checkRelationExpr_base_eq]
    exact hasCapability_fuel_mono graph g.subj rel g.obj p hg_sat k

-- ── 7. Subset monotonicity ───────────────────────────────────────────────────

/-- Removing goals from a satisfied multigoal leaves it satisfied. -/
theorem multiSatisfied_of_subset (graph : List Relationship) (fuel : Nat)
    (gs gs' : MultiGoal)
    (hsub : ∀ g ∈ gs', g ∈ gs)
    (h : multiSatisfied graph fuel gs = true) :
    multiSatisfied graph fuel gs' = true := by
  rw [multiSatisfied_iff] at h ⊢
  exact fun g hg => h g (hsub g hg)

end ReBACGoal
