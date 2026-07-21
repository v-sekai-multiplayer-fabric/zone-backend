; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; ReBAC base-relation check, ported from standalone/tw_rebac.hpp's
; check_base (RFD 0022, Stage 4). A graph is a list of edges; each edge
; is a 3-element list (subj obj rel), subj/obj/rel are strings. Compiled
; via s7c into priv/rebac.elf, driven by Uro.ReBAC.SandboxAdapter
; through the GuestValue handle trampoline (RFD 0021) -- the graph
; never enters guest memory, it stays a host-owned Elixir list of
; 3-tuples-as-lists the guest walks one cons cell at a time.
;
; This subset has no string literals (the reader has no Str kind), so
; the three fixed relation-name constants the algorithm itself needs to
; recognize (IS_MEMBER_OF / CONTROLS / DELEGATED_TO) are passed in by
; the caller as `rel-consts`, a 3-element list, rather than embedded as
; literals -- the adapter (not this program) owns that fixed vocabulary.
;
; Semantics kept: direct-edge match, transitive IS_MEMBER_OF (subject
; inherits its group's relations), and CONTROLS-via-DELEGATED_TO
; inversion. Dropped (not reachable through Uro.Ports.ReBAC.check_rel,
; which only ever builds a {"type":"base",...} expr): union/
; intersection/difference/tuple_to_userset composite expressions.
(define (edge-subj e) (car e))
(define (edge-obj e) (car (cdr e)))
(define (edge-rel e) (car (cdr (cdr e))))

(define (rc-member rc) (car rc))
(define (rc-controls rc) (car (cdr rc)))
(define (rc-delegated rc) (car (cdr (cdr rc))))

(define (find-direct edges subj rel obj)
  (if (null? edges)
      #f
      (if (and (string=? (edge-subj (car edges)) subj)
               (string=? (edge-rel (car edges)) rel)
               (string=? (edge-obj (car edges)) obj))
          #t
          (find-direct (cdr edges) subj rel obj))))

(define (find-member-transitive edges all-edges subj rel obj fuel rc)
  (if (null? edges)
      #f
      (if (and (string=? (edge-subj (car edges)) subj)
               (string=? (edge-rel (car edges)) (rc-member rc)))
          (if (check-base all-edges (edge-obj (car edges)) rel obj (- fuel 1) rc)
              #t
              (find-member-transitive (cdr edges) all-edges subj rel obj fuel rc))
          (find-member-transitive (cdr edges) all-edges subj rel obj fuel rc))))

(define (find-controls-delegation edges subj obj rc)
  (if (null? edges)
      #f
      (if (and (string=? (edge-subj (car edges)) obj)
               (string=? (edge-rel (car edges)) (rc-delegated rc))
               (string=? (edge-obj (car edges)) subj))
          #t
          (find-controls-delegation (cdr edges) subj obj rc))))

(define (check-base edges subj rel obj fuel rc)
  (if (< fuel 1)
      #f
      (if (find-direct edges subj rel obj)
          #t
          (if (find-member-transitive edges edges subj rel obj fuel rc)
              #t
              (if (string=? rel (rc-controls rc))
                  (find-controls-delegation edges subj obj rc)
                  #f)))))

(define (check-rel graph subj rel obj rc) (check-base graph subj rel obj 8 rc))
