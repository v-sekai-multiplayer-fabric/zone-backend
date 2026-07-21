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
