; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; Hand-ported from v-sekai-multiplayer-fabric/progression's
; core/ProgressionCore/Core.lean (translated line-for-line) - the
; inventory/affinity-gate/credit reducer.
;
; Source of truth: v-sekai-multiplayer-fabric/progression is upstream
; and authoritative. This file is a pinned, one-time translation, not
; an ongoing mirror - ADR 0032. Ported from commit
; 659d52239ba50ab313614bf3aa6233165eb89788. If that repo's Core.lean
; changes, this file is stale until re-ported by hand against the new
; commit - nothing here re-checks upstream automatically.
;
; Uses record-macros.scm's define-record/record-with (ADR 0034), same
; as combat.scm - no (load ...): record-macros.scm is concatenated on
; the host side, the guest never loads its own files (a libriscv
; sandbox/gas-limit concern, not just style - see combat.scm's header).

; `filter` is not a builtin in this s7 build (verified: map/assoc/member
; all resolve fine, filter alone throws "unbound variable") - defined
; locally rather than assuming a library load path exists for it.
(define (filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
        (else (filter pred (cdr lst)))))

(define-record profile credits affinity items arts)

(define initial-profile (make-profile 200 15 '() '()))

(define (art-cost a) (cond ((= a 1) 100) ((= a 2) 250) (else 500)))
(define (art-affinity-req a) (cond ((= a 1) 10) ((= a 2) 25) (else 40)))

; ProgressionCore.countOf
(define (count-of p item)
  (let ((e (assoc item (profile-items p))))
    (if e (cdr e) 0)))

; ProgressionCore.addItem
(define (add-item p item d)
  (if (assoc item (profile-items p))
      (record-with make-profile '(credits affinity items arts) p
        (items (map (lambda (e) (if (= (car e) item) (cons (car e) (+ (cdr e) d)) e)) (profile-items p))))
      (record-with make-profile '(credits affinity items arts) p
        (items (append (profile-items p) (list (cons item d)))))))

; ProgressionCore.removeItem
(define (remove-item p item)
  (record-with make-profile '(credits affinity items arts) p
    (items (filter (lambda (e) (> (cdr e) 0))
                    (map (lambda (e) (if (= (car e) item) (cons (car e) (- (cdr e) 1)) e)) (profile-items p))))))

; ProgressionCore.step - events are (list 'grant item), (list 'sell item price),
; (list 'buyArt art), or the bare symbol 'train.
(define (progression-step p event)
  (cond
    ((and (pair? event) (eq? (car event) 'grant))
     (list (add-item p (cadr event) 1) (list (list 'granted (cadr event)))))
    ((and (pair? event) (eq? (car event) 'sell))
     (let ((item (cadr event)) (price (caddr event)))
       (if (= (count-of p item) 0)
           (list p (list (list 'refusedNoItem item)))
           (list (remove-item (record-with make-profile '(credits affinity items arts) p
                                 (credits (+ (profile-credits p) price)))
                               item)
                 (list (list 'sold item price))))))
    ((and (pair? event) (eq? (car event) 'buyArt))
     (let ((art (cadr event)))
       (cond
         ((member art (profile-arts p)) (list p (list (list 'refusedDup art))))
         ((< (profile-affinity p) (art-affinity-req art)) (list p (list (list 'refusedGate art))))
         ((< (profile-credits p) (art-cost art)) (list p (list (list 'refusedPoor art))))
         (else (list (record-with make-profile '(credits affinity items arts) p
                       (credits (- (profile-credits p) (art-cost art)))
                       (arts (append (profile-arts p) (list art))))
                     (list (list 'learned art)))))))
    ((eq? event 'train)
     (let ((a (+ (profile-affinity p) 1)))
       (list (record-with make-profile '(credits affinity items arts) p (affinity a)) (list (list 'trained a)))))
    (else (list p '()))))

; ProgressionCore.replay
(define (progression-replay events)
  (let loop ((evs events) (acc (list initial-profile '())))
    (if (null? evs)
        acc
        (let ((r (progression-step (car acc) (car evs))))
          (loop (cdr evs) (list (car r) (append (cadr acc) (cadr r))))))))
