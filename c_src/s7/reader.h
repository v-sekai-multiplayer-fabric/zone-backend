// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// S-expression reader. Parens ARE the structure, so this is the whole
// frontend parse step -- no precedence ladder, no indentation stack
// (contrast with the GDScript reference compiler's 400-line lexer +
// 840-line parser this replaces for our language).
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace s7 {

struct SExpr {
  enum class Kind { Int, Sym, Bool, List };
  Kind kind = Kind::List;
  int64_t int_value = 0;
  bool bool_value = false;
  std::string sym;
  std::vector<SExpr> list;
};

// Reads every top-level form in `source`. Throws std::runtime_error with
// a line number on malformed input (unbalanced parens, bad atom).
std::vector<SExpr> read_all(const std::string& source);

}  // namespace s7
