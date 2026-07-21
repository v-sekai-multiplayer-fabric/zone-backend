; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; Compiled at build time by s7c into priv/s7_basic.elf, exercised by
; test/weft_warp_burrito/program_test.exs through the host-call
; trampoline (RFD 0018).
(define (add a b) (+ a b))
(define (lt a b) (< a b))
(define (bigfact n) (if (< n 2) 1 (* n (bigfact (- n 1)))))
(define (bigfact-rem n m) (remainder (bigfact n) m))
(define (compose-demo x)
  (let ((inc (lambda (v) (+ v 1)))
        (dbl (lambda (v) (* v 2))))
    (inc (dbl x))))
; Handle-value ops: lists/tuples/maps/binaries/atoms live host-side
; (real Elixir terms); every structural op below round-trips through
; the trampoline.
(define (sum-list l) (if (null? l) 0 (+ (car l) (sum-list (cdr l)))))
(define (second l) (list-ref l 1))
(define (build-list a b) (cons a (list b 3)))
(define (tuple-pick t) (vector-ref t 1))
(define (tuple-size t) (vector-length t))
(define (map-get m k) (hash-table-ref m k))
(define (bin-size b) (string-length b))
(define (same? a b) (eq? a b))
