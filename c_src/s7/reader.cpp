// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "reader.h"

#include <cctype>
#include <stdexcept>

namespace s7 {

namespace {

struct Reader {
  const std::string& src;
  size_t pos = 0;
  int line = 1;

  explicit Reader(const std::string& s) : src(s) {}

  [[noreturn]] void fail(const std::string& msg) const {
    throw std::runtime_error("reader: line " + std::to_string(line) + ": " + msg);
  }

  bool at_end() const { return pos >= src.size(); }

  char peek() const { return src[pos]; }

  char advance() {
    char c = src[pos++];
    if (c == '\n') line++;
    return c;
  }

  void skip_ws_and_comments() {
    while (!at_end()) {
      char c = peek();
      if (c == ';') {
        while (!at_end() && peek() != '\n') advance();
      } else if (std::isspace(static_cast<unsigned char>(c))) {
        advance();
      } else {
        return;
      }
    }
  }

  static bool is_delim(char c) {
    return c == '(' || c == ')' || c == ';' || std::isspace(static_cast<unsigned char>(c));
  }

  SExpr read_expr() {
    skip_ws_and_comments();
    if (at_end()) fail("unexpected end of input");
    char c = peek();
    if (c == '(') {
      advance();
      SExpr list;
      list.kind = SExpr::Kind::List;
      for (;;) {
        skip_ws_and_comments();
        if (at_end()) fail("unbalanced '(' -- missing ')'");
        if (peek() == ')') {
          advance();
          return list;
        }
        list.list.push_back(read_expr());
      }
    }
    if (c == ')') fail("unexpected ')'");
    return read_atom();
  }

  SExpr read_atom() {
    size_t start = pos;
    while (!at_end() && !is_delim(peek())) advance();
    std::string text = src.substr(start, pos - start);
    if (text.empty()) fail("empty atom");

    if (text == "#t") {
      SExpr e;
      e.kind = SExpr::Kind::Bool;
      e.bool_value = true;
      return e;
    }
    if (text == "#f") {
      SExpr e;
      e.kind = SExpr::Kind::Bool;
      e.bool_value = false;
      return e;
    }

    // Integer: optional leading '-', then all digits.
    bool numeric = !text.empty() && (std::isdigit(static_cast<unsigned char>(text[0])) ||
                                     (text[0] == '-' && text.size() > 1));
    if (numeric) {
      for (size_t i = 1; i < text.size(); ++i) {
        if (!std::isdigit(static_cast<unsigned char>(text[i]))) {
          numeric = false;
          break;
        }
      }
    }
    if (numeric) {
      SExpr e;
      e.kind = SExpr::Kind::Int;
      try {
        e.int_value = std::stoll(text);
      } catch (const std::exception&) {
        fail("integer out of range: " + text);
      }
      return e;
    }

    SExpr e;
    e.kind = SExpr::Kind::Sym;
    e.sym = text;
    return e;
  }
};

}  // namespace

std::vector<SExpr> read_all(const std::string& source) {
  Reader reader(source);
  std::vector<SExpr> forms;
  for (;;) {
    reader.skip_ws_and_comments();
    if (reader.at_end()) return forms;
    forms.push_back(reader.read_expr());
  }
}

}  // namespace s7
