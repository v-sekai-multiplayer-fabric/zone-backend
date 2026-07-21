; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; Lisp macros for the immutable-record-update pattern combat.scm and
; progression.scm both hand-wrote as verbose vector reconstructions -
; per Paul Graham's "Beating the Averages" (ADR 0028's own citation),
; macros are the other half of Lisp's development-velocity case besides
; interactive iteration: bend the language to the problem instead of
; writing the same boilerplate by hand at every call site.
;
; define-record generates a constructor and per-field accessors over a
; plain vector (no new runtime type, no allocator beyond a vector - a
; deliberate console-grade choice, ADR 0029). record-with generates a
; positional reconstruction at macro-expansion time (not a runtime
; case-dispatch), so a call site only names what's changing, directly
; mirroring Lean's `{ s with f := v }` syntax instead of listing every
; unchanged field's accessor by hand.

(define-macro (define-record name . fields)
  (let* ((name-str (symbol->string name))
         (mk (string->symbol (string-append "make-" name-str))))
    (let loop ((fs fields) (i 0) (accessors '()))
      (if (null? fs)
          `(begin
             (define (,mk ,@fields) (vector ,@fields))
             ,@(reverse accessors))
          (loop (cdr fs) (+ i 1)
                (cons `(define (,(string->symbol (string-append name-str "-" (symbol->string (car fs)))) r)
                         (vector-ref r ,i))
                      accessors))))))

; (record-with make-state '(tick combo last-attack hp spawn alive) s (hp (- (st-hp s) dmg)))
; -> (make-state (vector-ref s 0) (vector-ref s 1) (vector-ref s 2) (- (st-hp s) dmg) (vector-ref s 4) (vector-ref s 5))
; Field positions are resolved at macro-expansion time (a literal quoted
; field list, matching the same order define-record used to build the
; vector) - no runtime dispatch, no vector-copy, no hidden state shared
; between macro invocations.
(define-macro (record-with ctor quoted-fields r . updates)
  (let ((fields (cadr quoted-fields)))
    (let loop ((fs fields) (i 0) (args '()))
      (if (null? fs)
          `(,ctor ,@(reverse args))
          (let ((u (assoc (car fs) updates)))
            (loop (cdr fs) (+ i 1)
                  (cons (if u (cadr u) `(vector-ref ,r ,i)) args)))))))
