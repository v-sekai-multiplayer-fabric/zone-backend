// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "codegen.h"

#include <stdexcept>
#include <string>
#include <unordered_map>

#include "value.h"

namespace s7 {

namespace {

struct FnCodegen {
  const IRProgram& program;  // for callee name -> index lookup
  IRFunction& func;
  std::vector<std::unordered_map<std::string, int>> scopes;
  int next_label = 0;

  [[noreturn]] void fail(const std::string& msg) const {
    throw std::runtime_error("codegen: in " + func.name + ": " + msg);
  }

  int new_vreg() { return func.num_vregs++; }
  int new_label() { return next_label++; }

  void emit(Instr in) { func.instrs.push_back(std::move(in)); }

  void emit_label(int label) {
    Instr in;
    in.op = Op::LABEL;
    in.label = label;
    emit(in);
  }

  void emit_jump(int label) {
    Instr in;
    in.op = Op::JUMP;
    in.label = label;
    emit(in);
  }

  void emit_branch_zero(int vreg, int label) {
    Instr in;
    in.op = Op::BRANCH_ZERO;
    in.a = vreg;
    in.label = label;
    emit(in);
  }

  int emit_imm(int64_t imm) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::LOAD_IMM;
    in.dst = dst;
    in.imm = imm;
    emit(in);
    return dst;
  }

  void emit_move(int dst, int src) {
    Instr in;
    in.op = Op::MOVE;
    in.dst = dst;
    in.a = src;
    emit(in);
  }

  int emit_binop(Op op, int a, int b) {
    int dst = new_vreg();
    Instr in;
    in.op = op;
    in.dst = dst;
    in.a = a;
    in.b = b;
    emit(in);
    return dst;
  }

  int emit_eqz(int a) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::EQZ;
    in.dst = dst;
    in.a = a;
    emit(in);
    return dst;
  }

  // raw 0/1 -> tagged #f/#t:  (raw << 3) | 0x06
  int tag_raw_bool(int raw) {
    int three = emit_imm(3);
    int shifted = emit_binop(Op::SLL, raw, three);
    int six = emit_imm(kFalse);
    return emit_binop(Op::OR, shifted, six);
  }

  // Scheme truthiness test: branch to `label` when vreg holds #f.
  void branch_if_false(int vreg, int label) {
    int f = emit_imm(kFalse);
    int diff = emit_binop(Op::XOR, vreg, f);
    emit_branch_zero(diff, label);
  }

  int lookup(const std::string& name) const {
    for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
      auto found = it->find(name);
      if (found != it->end()) return found->second;
    }
    return -1;
  }

  int gen_body(const std::vector<SExpr>& forms, size_t start) {
    if (start >= forms.size()) fail("empty body");
    int result = -1;
    for (size_t i = start; i < forms.size(); ++i) result = gen_expr(forms[i]);
    return result;
  }

  int gen_expr(const SExpr& e) {
    switch (e.kind) {
      case SExpr::Kind::Int: return emit_imm(tag_fixnum(e.int_value));
      case SExpr::Kind::Bool: return emit_imm(tag_bool(e.bool_value));
      case SExpr::Kind::Sym: {
        int vreg = lookup(e.sym);
        if (vreg < 0) fail("unbound variable: " + e.sym);
        return vreg;
      }
      case SExpr::Kind::List: return gen_list(e);
    }
    fail("unreachable");
  }

  int gen_list(const SExpr& e) {
    if (e.list.empty()) fail("cannot evaluate ()");
    const SExpr& head = e.list[0];
    if (head.kind != SExpr::Kind::Sym) fail("operator must be a symbol (no lambdas yet)");
    const std::string& op = head.sym;

    if (op == "if") return gen_if(e);
    if (op == "let") return gen_let(e, /*sequential=*/false);
    if (op == "let*") return gen_let(e, /*sequential=*/true);
    if (op == "begin") return gen_body(e.list, 1);
    if (op == "set!") return gen_set(e);
    if (op == "and") return gen_and_or(e, /*is_and=*/true);
    if (op == "or") return gen_and_or(e, /*is_and=*/false);

    if (op == "+") return gen_fold(e, Op::ADD, tag_fixnum(0));
    if (op == "-") return gen_sub(e);
    if (op == "*") return gen_mul(e);
    if (op == "quotient") return gen_quotient(e);
    if (op == "remainder") return gen_binary_prim(e, Op::REM);
    if (op == "<") return gen_compare(e, /*swap=*/false, /*negate=*/false);
    if (op == ">") return gen_compare(e, /*swap=*/true, /*negate=*/false);
    if (op == ">=") return gen_compare(e, /*swap=*/false, /*negate=*/true);
    if (op == "<=") return gen_compare(e, /*swap=*/true, /*negate=*/true);
    if (op == "=" || op == "eq?") return gen_eq(e);
    if (op == "not") return gen_not(e);

    return gen_call(e);
  }

  int gen_if(const SExpr& e) {
    if (e.list.size() != 3 && e.list.size() != 4) fail("if wants 2 or 3 forms");
    int result = new_vreg();
    int else_label = new_label();
    int end_label = new_label();

    int cond = gen_expr(e.list[1]);
    branch_if_false(cond, else_label);
    emit_move(result, gen_expr(e.list[2]));
    emit_jump(end_label);
    emit_label(else_label);
    if (e.list.size() == 4) {
      emit_move(result, gen_expr(e.list[3]));
    } else {
      emit_move(result, emit_imm(kNil));
    }
    emit_label(end_label);
    return result;
  }

  int gen_let(const SExpr& e, bool sequential) {
    if (e.list.size() < 3) fail("let wants bindings + body");
    const SExpr& bindings = e.list[1];
    if (bindings.kind != SExpr::Kind::List) fail("let bindings must be a list");

    scopes.emplace_back();
    // Plain `let`: evaluate all inits before any binding is visible.
    // `let*`: each binding sees the previous ones.
    std::vector<std::pair<std::string, int>> pending;
    for (const SExpr& binding : bindings.list) {
      if (binding.kind != SExpr::Kind::List || binding.list.size() != 2 ||
          binding.list[0].kind != SExpr::Kind::Sym) {
        fail("let binding must be (name expr)");
      }
      int value = gen_expr(binding.list[1]);
      int slot = new_vreg();
      emit_move(slot, value);
      if (sequential) {
        scopes.back()[binding.list[0].sym] = slot;
      } else {
        pending.emplace_back(binding.list[0].sym, slot);
      }
    }
    for (auto& [name, slot] : pending) scopes.back()[name] = slot;

    int result = gen_body(e.list, 2);
    scopes.pop_back();
    return result;
  }

  int gen_set(const SExpr& e) {
    if (e.list.size() != 3 || e.list[1].kind != SExpr::Kind::Sym) fail("set! wants (set! name expr)");
    int vreg = lookup(e.list[1].sym);
    if (vreg < 0) fail("set! of unbound variable: " + e.list[1].sym);
    int value = gen_expr(e.list[2]);
    emit_move(vreg, value);
    return vreg;
  }

  int gen_and_or(const SExpr& e, bool is_and) {
    int result = new_vreg();
    if (e.list.size() == 1) {
      emit_move(result, emit_imm(is_and ? kTrue : kFalse));
      return result;
    }
    int end_label = new_label();
    for (size_t i = 1; i < e.list.size(); ++i) {
      emit_move(result, gen_expr(e.list[i]));
      if (i + 1 == e.list.size()) break;
      if (is_and) {
        // Stop (keeping #f) as soon as a value is #f.
        branch_if_false(result, end_label);
      } else {
        // Stop (keeping the value) as soon as a value is NOT #f.
        int f = emit_imm(kFalse);
        int diff = emit_binop(Op::XOR, result, f);
        int is_f = emit_eqz(diff);  // 1 when result was #f
        emit_branch_zero(is_f, end_label);
      }
    }
    emit_label(end_label);
    return result;
  }

  // (+ a b ...) and n-ary folds with an identity for the 0-arg case.
  int gen_fold(const SExpr& e, Op op, int64_t identity) {
    if (e.list.size() == 1) return emit_imm(identity);
    int acc = gen_expr(e.list[1]);
    for (size_t i = 2; i < e.list.size(); ++i) acc = emit_binop(op, acc, gen_expr(e.list[i]));
    return acc;
  }

  int gen_sub(const SExpr& e) {
    if (e.list.size() < 2) fail("- wants at least 1 argument");
    if (e.list.size() == 2) {
      int zero = emit_imm(tag_fixnum(0));
      return emit_binop(Op::SUB, zero, gen_expr(e.list[1]));
    }
    int acc = gen_expr(e.list[1]);
    for (size_t i = 2; i < e.list.size(); ++i) acc = emit_binop(Op::SUB, acc, gen_expr(e.list[i]));
    return acc;
  }

  // Tagged multiply: (8x)*(8y)/8 = 8xy, done as (a >> 3) * b.
  int gen_mul(const SExpr& e) {
    if (e.list.size() == 1) return emit_imm(tag_fixnum(1));
    int acc = gen_expr(e.list[1]);
    for (size_t i = 2; i < e.list.size(); ++i) {
      int three = emit_imm(3);
      int untagged = emit_binop(Op::SRA, acc, three);
      acc = emit_binop(Op::MUL, untagged, gen_expr(e.list[i]));
    }
    return acc;
  }

  // Tagged quotient: (8x)/(8y) = x/y raw, then retag with << 3.
  int gen_quotient(const SExpr& e) {
    if (e.list.size() != 3) fail("quotient wants 2 arguments");
    int raw = emit_binop(Op::DIV, gen_expr(e.list[1]), gen_expr(e.list[2]));
    int three = emit_imm(3);
    return emit_binop(Op::SLL, raw, three);
  }

  int gen_binary_prim(const SExpr& e, Op op) {
    if (e.list.size() != 3) fail("binary primitive wants 2 arguments");
    return emit_binop(op, gen_expr(e.list[1]), gen_expr(e.list[2]));
  }

  // Tagged fixnum ordering is preserved by the tag (<< 3), so SLT on
  // tagged values gives the right raw 0/1 answer directly.
  int gen_compare(const SExpr& e, bool swap, bool negate) {
    if (e.list.size() != 3) fail("comparison wants 2 arguments");
    int a = gen_expr(e.list[1]);
    int b = gen_expr(e.list[2]);
    int raw = swap ? emit_binop(Op::SLT, b, a) : emit_binop(Op::SLT, a, b);
    if (negate) raw = emit_eqz(raw);
    return tag_raw_bool(raw);
  }

  int gen_eq(const SExpr& e) {
    if (e.list.size() != 3) fail("= / eq? wants 2 arguments");
    int diff = emit_binop(Op::XOR, gen_expr(e.list[1]), gen_expr(e.list[2]));
    return tag_raw_bool(emit_eqz(diff));
  }

  int gen_not(const SExpr& e) {
    if (e.list.size() != 2) fail("not wants 1 argument");
    int f = emit_imm(kFalse);
    int diff = emit_binop(Op::XOR, gen_expr(e.list[1]), f);
    return tag_raw_bool(emit_eqz(diff));
  }

  int gen_call(const SExpr& e) {
    int callee = program.find(e.list[0].sym);
    if (callee < 0) fail("unknown function: " + e.list[0].sym);
    const IRFunction& target = program.functions[callee];
    if (static_cast<int>(e.list.size()) - 1 != target.num_params) {
      fail("arity mismatch calling " + target.name);
    }
    Instr in;
    in.op = Op::CALL;
    in.callee = callee;
    for (size_t i = 1; i < e.list.size(); ++i) in.args.push_back(gen_expr(e.list[i]));
    in.dst = new_vreg();
    emit(in);
    return in.dst;
  }
};

}  // namespace

IRProgram lower(const std::vector<SExpr>& forms) {
  IRProgram program;

  // Pass 1: register every define's name/arity so bodies can reference
  // any function (mutual recursion) before its body is lowered.
  for (const SExpr& form : forms) {
    if (form.kind != SExpr::Kind::List || form.list.size() < 3 ||
        form.list[0].kind != SExpr::Kind::Sym || form.list[0].sym != "define" ||
        form.list[1].kind != SExpr::Kind::List || form.list[1].list.empty() ||
        form.list[1].list[0].kind != SExpr::Kind::Sym) {
      throw std::runtime_error("codegen: every top-level form must be (define (name args...) body...)");
    }
    IRFunction func;
    func.name = form.list[1].list[0].sym;
    func.num_params = static_cast<int>(form.list[1].list.size()) - 1;
    func.num_vregs = func.num_params;
    if (program.find(func.name) >= 0) {
      throw std::runtime_error("codegen: duplicate define: " + func.name);
    }
    program.functions.push_back(std::move(func));
  }

  // Pass 2: lower bodies.
  for (size_t f = 0; f < forms.size(); ++f) {
    const SExpr& form = forms[f];
    IRFunction& func = program.functions[f];
    FnCodegen gen{program, func};
    gen.scopes.emplace_back();
    for (size_t p = 1; p < form.list[1].list.size(); ++p) {
      const SExpr& param = form.list[1].list[p];
      if (param.kind != SExpr::Kind::Sym) gen.fail("parameters must be symbols");
      gen.scopes.back()[param.sym] = static_cast<int>(p) - 1;
    }
    int result = gen.gen_body(form.list, 2);
    Instr ret;
    ret.op = Op::RETURN;
    ret.a = result;
    gen.emit(ret);
  }

  return program;
}

}  // namespace s7
