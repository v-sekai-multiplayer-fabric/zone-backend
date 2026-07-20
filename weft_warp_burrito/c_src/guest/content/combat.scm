; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; Hand-ported from v-sekai-multiplayer-fabric/combat's
; core/CombatCore/Core.lean (translated line-for-line) - the
; combo/invulnerability/damage reducer.
;
; Source of truth: v-sekai-multiplayer-fabric/combat is upstream and
; authoritative. This file is a pinned, one-time translation, not an
; ongoing mirror - ADR 0032. Ported from commit
; f9a1964892c6943e120c82bad398646944aaa10e. If that repo's Core.lean
; changes, this file is stale until re-ported by hand against the new
; commit - nothing here re-checks upstream automatically.
;
; Uses record-macros.scm's define-record/record-with (ADR 0034) instead
; of hand-written vector reconstruction - each `{ s with f := v }` site
; now names only what changed, matching the Lean source directly instead
; of spelling out every unchanged field's accessor by hand. The quoted
; field list is repeated at each record-with call site (unavoidable:
; define-macro receives unevaluated syntax, so a variable holding the
; field list wouldn't be visible at macro-expansion time) - a real,
; accepted cost, still smaller than the boilerplate it replaces.
;
; No (load ...) here: the guest runs entirely inside libriscv's
; fuel-metered VMCALL sandbox (resume/pause/gas-limit all come from
; that boundary, per ADR 0006) - a guest-side (load "record-macros.scm")
; would need a real filesystem syscall from inside the sandbox, outside
; the gas-limited/marshaled call path entirely. record-macros.scm's
; content is concatenated on the HOST side instead (same pattern
; s7_riscv_*_golden_test.cpp already uses to assemble one big
; expression string before the single VMCALL), never loaded by the
; guest itself.

(define combo-min-gap 6)
(define combo-max-gap 18)
(define invuln-ticks 30)
(define enemy-max-hp 100)

(define (damage-of stage)
  (cond ((= stage 0) 10)
        ((= stage 1) 15)
        (else 25)))

(define-record state tick combo last-attack hp spawn alive)

(define initial-state (make-state 0 0 0 0 0 #f))

; CombatCore.resolveSwing
(define (resolve-swing s stage)
  (cond
    ((not (state-alive s))
     (list s (list (list 'swing stage))))
    ((< (state-tick s) (+ (state-spawn s) invuln-ticks))
     (list s (list (list 'swing stage) 'blocked)))
    (else
     (let ((dmg (damage-of stage)))
       (if (<= (state-hp s) dmg)
           (list (record-with make-state '(tick combo last-attack hp spawn alive) s (hp 0) (alive #f))
                 (list (list 'swing stage) (list 'hit dmg) 'death))
           (list (record-with make-state '(tick combo last-attack hp spawn alive) s (hp (- (state-hp s) dmg)))
                 (list (list 'swing stage) (list 'hit dmg))))))))

; CombatCore.step
(define (combat-step s event)
  (cond
    ((eq? event 'tick)
     (let ((s1 (record-with make-state '(tick combo last-attack hp spawn alive) s (tick (+ (state-tick s) 1)))))
       (if (and (> (state-combo s1) 0) (> (state-tick s1) (+ (state-last-attack s1) combo-max-gap)))
           (list (record-with make-state '(tick combo last-attack hp spawn alive) s1 (combo 0)) (list 'comboDrop))
           (list s1 '()))))
    ((eq? event 'spawn)
     (list (record-with make-state '(tick combo last-attack hp spawn alive) s
             (alive #t) (hp enemy-max-hp) (spawn (state-tick s)))
           '()))
    ((eq? event 'attack)
     (if (= (state-combo s) 0)
         (resolve-swing (record-with make-state '(tick combo last-attack hp spawn alive) s
                          (combo 1) (last-attack (state-tick s)))
                        0)
         (let ((gap (- (state-tick s) (state-last-attack s))))
           (if (and (<= combo-min-gap gap) (<= gap combo-max-gap))
               (let* ((stage (state-combo s))
                      (next (if (>= stage 2) 0 (+ stage 1))))
                 (resolve-swing (record-with make-state '(tick combo last-attack hp spawn alive) s
                                  (combo next) (last-attack (state-tick s)))
                                stage))
               (list (record-with make-state '(tick combo last-attack hp spawn alive) s (combo 0)) (list 'whiff))))))
    (else (list s '()))))

; CombatCore.replay
(define (combat-replay events)
  (let loop ((evs events) (acc (list initial-state '())))
    (if (null? evs)
        acc
        (let* ((r (combat-step (car acc) (car evs))))
          (loop (cdr evs) (list (car r) (append (cadr acc) (cadr r))))))))
