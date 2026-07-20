import Planner.Types
import Planner.Capabilities

/-!
# ReBAC Correctness Proofs

Formal verification of `hasCapability` and related functions (Planner.Capabilities).
These proofs justify `tw_rebac.hpp` and are the benchmark: a storage refactor
is worthwhile only if these proofs become strictly shorter or simpler.

## Key theorems

1. **Direct-edge soundness** — a direct edge is always found.
2. **IS_MEMBER_OF transitivity** — membership propagates capabilities.
3. **Fuel monotonicity** — more fuel never breaks a passing check.
4. **Expand soundness** — every entity returned by `expand` holds the relation.
5. **check_expr/base reduction** — base reduces to `hasCapability`.
-/

namespace ReBACCorrectness

open RelationType

-- ── 1. Direct-edge soundness ────────────────────────────────────────────────

/-- A direct edge `⟨s, rel, o⟩` is always found at fuel ≥ 1. -/
theorem hasCapability_direct (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (hmem : ⟨s, rel, o⟩ ∈ graph) :
    hasCapability graph s rel o (n + 1) = true := by
  simp only [hasCapability, Bool.or_eq_true]; left; left
  exact List.any_eq_true.mpr ⟨⟨s, rel, o⟩, hmem, by simp⟩

-- ── 2. IS_MEMBER_OF transitivity ────────────────────────────────────────────

/-- Direct membership propagates capabilities one fuel step. -/
theorem hasCapability_member_trans (graph : List Relationship)
    (s g : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (hmem : ⟨s, IS_MEMBER_OF, g⟩ ∈ graph)
    (hcap : hasCapability graph g rel o n = true) :
    hasCapability graph s rel o (n + 1) = true := by
  simp only [hasCapability, Bool.or_eq_true]; left; right
  exact List.any_eq_true.mpr ⟨⟨s, IS_MEMBER_OF, g⟩, hmem, by simp [hcap]⟩

-- ── 3. Fuel monotonicity ────────────────────────────────────────────────────

-- One-step lift, universally quantified over entity (needed for member branch).
private theorem hasCapability_fuel_succ (graph : List Relationship)
    (rel : RelationType) (o : Entity) :
    ∀ n s, hasCapability graph s rel o n = true →
           hasCapability graph s rel o (n + 1) = true := by
  intro n
  induction n with
  | zero => intro s h; simp [hasCapability] at h
  | succ p ih =>
    intro s h
    simp only [hasCapability, Bool.or_eq_true] at h ⊢
    rcases h with ((hdirect | hmember) | hdeleg)
    · exact Or.inl (Or.inl hdirect)
    · apply Or.inl; apply Or.inr
      simp only [List.any_eq_true, Bool.and_eq_true] at hmember ⊢
      obtain ⟨r, hr_mem, ⟨⟨hsubj, hrel⟩, hcap⟩⟩ := hmember
      exact ⟨r, hr_mem, ⟨⟨hsubj, hrel⟩, ih r.object hcap⟩⟩
    · exact Or.inr hdeleg

/-- `hasCapability` is monotone in fuel. -/
theorem hasCapability_fuel_mono (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (h : hasCapability graph s rel o n = true) (k : Nat) :
    hasCapability graph s rel o (n + k) = true := by
  induction k with
  | zero => simpa
  | succ m ih => exact hasCapability_fuel_succ graph rel o (n + m) s ih

-- ── 4. check_expr / base reduction ─────────────────────────────────────────

@[simp]
theorem checkRelationExpr_base_eq (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity) (n : Nat) :
    checkRelationExpr graph s (.base rel) o (n + 1) =
    hasCapability graph s rel o n := by
  simp [checkRelationExpr]

theorem checkRelationExpr_base_sound (graph : List Relationship)
    (s : Entity) (rel : RelationType) (o : Entity) (n : Nat)
    (h : hasCapability graph s rel o n = true) :
    checkRelationExpr graph s (.base rel) o (n + 1) = true := by simp [h]

-- ── 5. Union monotonicity ───────────────────────────────────────────────────

-- Note: union at fuel n+1 evaluates sub-expressions at fuel n.
theorem checkRelationExpr_union_left (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : checkRelationExpr graph s a o n = true) :
    checkRelationExpr graph s (.union a b) o (n + 1) = true := by
  simp only [checkRelationExpr, Bool.or_eq_true]
  exact Or.inl h

theorem checkRelationExpr_union_right (graph : List Relationship)
    (s : Entity) (a b : RelationExpr) (o : Entity) (n : Nat)
    (h : checkRelationExpr graph s b o n = true) :
    checkRelationExpr graph s (.union a b) o (n + 1) = true := by
  simp only [checkRelationExpr, Bool.or_eq_true]
  exact Or.inr h

-- ── 6. Expand soundness ─────────────────────────────────────────────────────

/-- Every entity returned by `expand` genuinely holds the relation.
    Delegates to `expandSoundness` in Planner.Capabilities; included here so
    the benchmark struct is self-contained. -/
theorem expand_sound (graph : List Relationship)
    (rel : RelationType) (o : Entity) (fuel : Nat)
    (s : Entity) (hs : s ∈ expand graph rel o fuel) :
    hasCapability graph s rel o (fuel + 1) = true :=
  expandSoundness graph rel o fuel s hs

-- ── Summary ─────────────────────────────────────────────────────────────────

/-- Core correctness properties. A storage refactor of `tw_rebac.hpp` is
    worthwhile only if instantiating this struct becomes strictly simpler. -/
structure ReBACCorrect where
  direct_sound :
    ∀ (graph : List Relationship) (s : Entity) (rel : RelationType)
      (o : Entity) (n : Nat),
      ⟨s, rel, o⟩ ∈ graph → hasCapability graph s rel o (n + 1) = true :=
    hasCapability_direct
  member_trans :
    ∀ (graph : List Relationship) (s g : Entity) (rel : RelationType)
      (o : Entity) (n : Nat),
      ⟨s, IS_MEMBER_OF, g⟩ ∈ graph →
      hasCapability graph g rel o n = true →
      hasCapability graph s rel o (n + 1) = true :=
    hasCapability_member_trans
  fuel_mono :
    ∀ (graph : List Relationship) (s : Entity) (rel : RelationType)
      (o : Entity) (n : Nat),
      hasCapability graph s rel o n = true →
      ∀ k, hasCapability graph s rel o (n + k) = true :=
    fun g s r o n h k => hasCapability_fuel_mono g s r o n h k
  expand_is_sound :
    ∀ (graph : List Relationship) (rel : RelationType) (o : Entity)
      (fuel : Nat) (s : Entity),
      s ∈ expand graph rel o fuel →
      hasCapability graph s rel o (fuel + 1) = true :=
    expand_sound

end ReBACCorrectness
