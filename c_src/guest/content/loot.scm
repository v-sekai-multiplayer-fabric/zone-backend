; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; Checkpoint 2 of the "real content through the interpreted s7 path"
; plan (ADR 0028). Hand-ported from
; v-sekai-multiplayer-fabric/loot's core/LootCore/{Rng,Loot}.lean
; (totalWeight, pick, roll, and the exact xorshift32 RNG both the Lean
; spec and its SPIR-V kernel already agree on bit-for-bit) - not a
; reinterpretation, a direct line-for-line translation.
;
; Source of truth: v-sekai-multiplayer-fabric/loot is upstream and
; authoritative. This file is a pinned, one-time translation, not an
; ongoing mirror - ADR 0032. Ported from commit
; 6c4439441c7ea9ef24b80fc68b6486e97219285b (2026-06-12). If that repo's
; Rng.lean/Loot.lean change, this file is stale until re-ported by hand
; against the new commit - nothing here re-checks upstream
; automatically.
;
; RNG: Lean's UInt32 arithmetic wraps automatically (mod 2^32); s7's
; integers are arbitrary-precision, so every operation that could
; exceed 32 bits is explicitly masked with (u32 ...) to reproduce that
; wraparound - `ash` with a negative shift is a logical right shift for
; any non-negative operand, which every intermediate value here always
; is (masked before use), so no sign-extension mismatch versus Lean's
; unsigned `>>>`.

(define (u32 x) (logand x #xFFFFFFFF))

(define (xorshift32-next32 s)
  (let* ((s (u32 (logxor s (u32 (ash s 13)))))
         (s (u32 (logxor s (ash s -17))))
         (s (u32 (logxor s (u32 (ash s 5))))))
    s))

; LootCore.Rng.range
(define (rng-range seed bound)
  (if (= bound 0) 0 (modulo (xorshift32-next32 seed) bound)))

; LootCore.totalWeight - table is a list of (item . weight) pairs,
; mirroring LootTable := List (Item x Weight).
(define (total-weight table)
  (let loop ((t table) (acc 0))
    (if (null? t) acc (loop (cdr t) (+ acc (cdr (car t)))))))

; LootCore.pick
(define (pick table r acc)
  (if (null? table)
      0
      (let* ((entry (car table))
             (item (car entry))
             (w (cdr entry))
             (new-acc (+ acc w)))
        (if (< r new-acc) item (pick (cdr table) r new-acc)))))

; LootCore.roll
(define (loot-roll seed table)
  (let ((tot (total-weight table)))
    (if (= tot 0) 0 (pick table (rng-range seed tot) 0))))
