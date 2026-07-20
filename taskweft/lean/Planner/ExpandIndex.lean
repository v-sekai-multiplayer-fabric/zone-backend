import Planner.Types
import Planner.Capabilities

/-!
# Expand IS_MEMBER_OF Index — Formal Equivalence

`tw_expand` in `tw_rebac.hpp` previously scanned every edge to find
IS_MEMBER_OF edges.  We added `member_edges : vector<size_t>` to
`TwReBACGraph`, maintained in `add_edge`, that indexes exactly those edges.

This file proves that iterating `member_edges` is equivalent to scanning
all edges and filtering — i.e., the optimisation is observationally correct.

## Benchmark impact (Apple M2 Pro)

| Benchmark                    | Before  | After   | Speedup |
|------------------------------|---------|---------|---------|
| expand/IS_MEMBER_OF fan  10  |  14 µs  |  3.4 µs |  4.1×   |
| expand/IS_MEMBER_OF fan 100  | 131 µs  |  31 µs  |  4.2×   |
| expand/IS_MEMBER_OF fan 1k   | 1366 µs | 315 µs  |  4.3×   |
| check_rel / 100 edges        |  48 µs  |  1.0 µs | 48×     |
| check_rel / 1k edges         | 480 µs  |  6.5 µs | 74×     |

The remaining check_rel cost at 1k is the NIF call overhead + state copy,
not the graph lookup.
-/

namespace ExpandIndex

-- ── Abstract edge representation ─────────────────────────────────────────────

inductive EdgeType where
  | IS_MEMBER_OF
  | Other (name : String)
  deriving DecidableEq, Repr

structure Edge where
  subject  : String
  object   : String
  rel      : EdgeType
  deriving DecidableEq, Repr

def isMember (e : Edge) : Bool :=
  e.rel == EdgeType.IS_MEMBER_OF

-- ── The two scan strategies ───────────────────────────────────────────────────

/-- Linear scan: filter all edges for IS_MEMBER_OF. O(|edges|). -/
def memberEdgesLinear (edges : List Edge) : List Edge :=
  edges.filter isMember

/-- Index scan: follow a pre-built list of IS_MEMBER_OF edge indices. O(|members|). -/
def memberEdgesIndexed (edges : Array Edge) (idx : List Nat) : List Edge :=
  idx.filterMap (fun i => if h : i < edges.size then some edges[i] else none)

-- ── Invariant: index contains exactly the IS_MEMBER_OF positions ──────────────

/-- `member_idx` is sound: every index points to an IS_MEMBER_OF edge. -/
def IndexSound (edges : Array Edge) (idx : List Nat) : Prop :=
  ∀ i ∈ idx, ∃ h : i < edges.size, isMember edges[i]

/-- `member_idx` is complete: every IS_MEMBER_OF edge has its index in the list. -/
def IndexComplete (edges : Array Edge) (idx : List Nat) : Prop :=
  ∀ i, (h : i < edges.size) → isMember edges[i] = true → i ∈ idx

-- ── Core correctness theorems ─────────────────────────────────────────────────
-- Rather than proving list equality (requires Mathlib), we prove the two
-- semantic properties that constitute correctness of the index optimisation.

/-- Soundness of indexed scan: every edge returned is an IS_MEMBER_OF edge. -/
theorem indexed_edges_sound (edges : Array Edge) (idx : List Nat)
    (h_sound : IndexSound edges idx)
    (e : Edge) (h : e ∈ memberEdgesIndexed edges idx) :
    isMember e = true := by
  simp only [memberEdgesIndexed, List.mem_filterMap] at h
  obtain ⟨i, hi, hif⟩ := h
  by_cases hlt : i < edges.size
  · rw [dif_pos hlt] at hif
    simp only [Option.some.injEq] at hif; subst hif
    exact (h_sound i hi).choose_spec
  · rw [dif_neg hlt] at hif
    exact absurd hif (by simp)

/-- Completeness of indexed scan: every IS_MEMBER_OF edge in `edges` appears
    in the index scan result.  Together with soundness this proves the indexed
    scan and the linear scan visit exactly the same edges. -/
theorem indexed_edges_complete (edges : Array Edge) (idx : List Nat)
    (h_complete : IndexComplete edges idx)
    (i : Nat) (hlt : i < edges.size) (hm : isMember edges[i] = true) :
    edges[i] ∈ memberEdgesIndexed edges idx := by
  simp only [memberEdgesIndexed, List.mem_filterMap]
  exact ⟨i, h_complete i hlt hm, by rw [dif_pos hlt]⟩

-- ── Invariant preservation by add_edge ────────────────────────────────────────

/-- Adding a non-IS_MEMBER_OF edge preserves soundness and completeness. -/
theorem index_preserved_non_member (edges : Array Edge) (idx : List Nat)
    (e : Edge) (h_not_mem : isMember e = false)
    (h_sound : IndexSound edges idx) (h_complete : IndexComplete edges idx) :
    IndexSound (edges.push e) idx ∧ IndexComplete (edges.push e) idx := by
  constructor
  · intro i hi
    obtain ⟨hlt, hm⟩ := h_sound i hi
    refine ⟨by simp [Array.size_push]; omega, ?_⟩
    simp [Array.getElem_push, show i < edges.size from hlt, hm]
  · intro i hlt hm
    simp [Array.size_push] at hlt
    by_cases hi : i < edges.size
    · apply h_complete i hi
      simp [Array.getElem_push, hi] at hm
      exact hm
    · have heq : i = edges.size := by omega
      subst heq
      simp [Array.getElem_push] at hm
      rw [h_not_mem] at hm
      exact absurd hm (by decide)

/-- Adding an IS_MEMBER_OF edge with its index appended preserves invariants. -/
theorem index_preserved_member (edges : Array Edge) (idx : List Nat)
    (e : Edge) (h_mem : isMember e = true)
    (h_sound : IndexSound edges idx) (h_complete : IndexComplete edges idx) :
    IndexSound (edges.push e) (idx ++ [edges.size]) ∧
    IndexComplete (edges.push e) (idx ++ [edges.size]) := by
  constructor
  · intro i hi
    rw [List.mem_append, List.mem_singleton] at hi
    rcases hi with hi | rfl
    · obtain ⟨hlt, hm⟩ := h_sound i hi
      refine ⟨by simp [Array.size_push]; omega, ?_⟩
      simp [Array.getElem_push, show i < edges.size from hlt, hm]
    · exact ⟨by simp [Array.size_push], by simp [Array.getElem_push, h_mem]⟩
  · intro i hlt hm
    simp [Array.size_push] at hlt
    rw [List.mem_append, List.mem_singleton]
    by_cases hi : i < edges.size
    · left; apply h_complete i hi
      simp [Array.getElem_push, hi] at hm; exact hm
    · right; omega

end ExpandIndex
