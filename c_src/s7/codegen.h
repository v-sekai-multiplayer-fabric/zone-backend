// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Frontend lowering: s-expressions -> IR. This is where GuestValue
// tagging (value.h) becomes explicit shift/mask IR instructions, keeping
// the IR itself machine-shaped and untyped.
//
// Stage 1 language subset (documented non-goals: closures/lambda come in
// Stage 2; floats, strings, pairs, call/cc, macros, TCO are out for now):
//   (define (name params...) body...)      top-level functions only
//   (if c t e)  (let ...)  (let* ...)  (begin ...)  (set! ...)
//   (and ...)  (or ...)
//   + - * quotient remainder < <= > >= = eq? not
//   integer literals, #t, #f, variable references, direct calls
#pragma once
#include <vector>

#include "ir.h"
#include "reader.h"

namespace s7 {

// Lowers all top-level forms (each must be a define) into an IRProgram.
// Throws std::runtime_error on unknown symbols/forms or arity errors.
IRProgram lower(const std::vector<SExpr>& forms);

}  // namespace s7
