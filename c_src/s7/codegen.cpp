// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "codegen.h"

#include <deque>
#include <set>
#include <stdexcept>
#include <string>
#include <unordered_map>

#include "value.h"

namespace s7 {

namespace {

bool is_special_form(const std::string& s) {
  return s == "if" || s == "let" || s == "let*" || s == "begin" || s == "set!" || s == "and" ||
         s == "or" || s == "lambda" || s == "define" || s == "cond";
}

bool is_primitive(const std::string& s) {
  return s == "+" || s == "-" || s == "*" || s == "quotient" || s == "remainder" || s == "<" ||
         s == ">" || s == ">=" || s == "<=" || s == "=" || s == "eq?" || s == "not" ||
         s == "car" || s == "cdr" || s == "cons" || s == "list" || s == "length" ||
         s == "list-ref" || s == "pair?" || s == "null?" || s == "vector-ref" ||
         s == "vector-length" || s == "hash-table-ref" || s == "hash-table-set" ||
         s == "string-length" || s == "string=?" || s == "logand" || s == "logxor" || s == "ash";
}

// Lowering context: functions live in a deque so references stay stable
// while lambdas append lifted functions mid-lowering.
struct LowerCtx {
  std::deque<IRFunction> fns;
  std::unordered_map<std::string, int> by_name;
  int lambda_counter = 0;
  int named_let_counter = 0;

  int find(const std::string& name) const {
    auto it = by_name.find(name);
    return it == by_name.end() ? -1 : it->second;
  }

  int add_function(const std::string& name, int num_params) {
    IRFunction fn;
    fn.name = name;
    fn.num_params = num_params;
    fn.num_vregs = num_params;
    fns.push_back(std::move(fn));
    int idx = static_cast<int>(fns.size()) - 1;
    by_name[name] = idx;
    return idx;
  }
};

struct FnCodegen {
  LowerCtx& ctx;
  IRFunction& func;
  std::vector<std::unordered_map<std::string, int>> scopes;
  std::set<std::string> captured_names;  // set! on these is a compile error
  int next_label = 0;

  // Named-let support (RFD 0025): a call to `named_let_alias` inside this
  // function's own body resolves directly to `named_let_target_idx`,
  // bypassing the normal top-level name lookup (the loop's real
  // registered name is mangled/unique, never typed by the user). Not
  // forwarded into nested lambdas/named-lets -- calling the loop name
  // from a nested closure is not supported in this subset.
  std::string named_let_alias;
  int named_let_target_idx = -1;

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

  int emit_alloc(int64_t bytes) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::ALLOC;
    in.dst = dst;
    in.imm = bytes;
    emit(in);
    return dst;
  }

  int emit_load_mem(int base, int64_t offset) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::LOAD_MEM;
    in.dst = dst;
    in.a = base;
    in.imm = offset;
    emit(in);
    return dst;
  }

  void emit_store_mem(int base, int64_t offset, int value) {
    Instr in;
    in.op = Op::STORE_MEM;
    in.a = base;
    in.b = value;
    in.imm = offset;
    emit(in);
  }

  int emit_load_func_addr(int callee) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::LOAD_FUNC_ADDR;
    in.dst = dst;
    in.callee = callee;
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
        if (vreg < 0) {
          if (ctx.find(e.sym) >= 0) {
            fail("named functions are not first-class values yet -- wrap in a lambda: " + e.sym);
          }
          fail("unbound variable: " + e.sym);
        }
        return vreg;
      }
      case SExpr::Kind::List: return gen_list(e);
    }
    fail("unreachable");
  }

  int gen_list(const SExpr& e) {
    if (e.list.empty()) fail("cannot evaluate ()");
    const SExpr& head = e.list[0];

    // ((lambda ...) args...) and other computed heads: closure call.
    if (head.kind == SExpr::Kind::List) return gen_closure_call(gen_expr(head), e);
    if (head.kind != SExpr::Kind::Sym) fail("operator must be a symbol or lambda form");
    const std::string& op = head.sym;

    // Local bindings shadow special forms and primitives (Scheme
    // semantics: a bound variable in operator position is a closure call).
    int local = lookup(op);
    if (local >= 0) return gen_closure_call(local, e);

    if (op == "lambda") return gen_lambda(e);
    if (op == "if") return gen_if(e);
    if (op == "cond") return gen_cond(e);
    if (op == "let") {
      // Named let (loop keyword): (let name ((v init)...) body...) --
      // distinguished from ordinary let by e.list[1] being a symbol.
      if (e.list.size() >= 2 && e.list[1].kind == SExpr::Kind::Sym) return gen_named_let(e);
      return gen_let(e, /*sequential=*/false);
    }
    if (op == "let*") return gen_let(e, /*sequential=*/true);
    if (op == "begin") return gen_body(e.list, 1);
    if (op == "set!") return gen_set(e);
    if (op == "and") return gen_and_or(e, /*is_and=*/true);
    if (op == "or") return gen_and_or(e, /*is_and=*/false);

    if (op == "+") return gen_fold(e, Op::CHECKED_ADD, tag_fixnum(0));
    if (op == "-") return gen_sub(e);
    if (op == "*") return gen_fold(e, Op::CHECKED_MUL, tag_fixnum(1));
    if (op == "quotient") return gen_binary_prim(e, Op::CHECKED_QUOT);
    if (op == "remainder") return gen_binary_prim(e, Op::CHECKED_REM);
    if (op == "<") return gen_compare(e, /*swap=*/false, /*negate=*/false);
    if (op == ">") return gen_compare(e, /*swap=*/true, /*negate=*/false);
    if (op == ">=") return gen_compare(e, /*swap=*/false, /*negate=*/true);
    if (op == "<=") return gen_compare(e, /*swap=*/true, /*negate=*/true);
    if (op == "=") return gen_numeric_eq(e);
    if (op == "eq?") return gen_identity_eq(e);
    if (op == "not") return gen_not(e);

    // Handle-value primitives (host-owned List/Tuple/Map/Binary/Atom):
    // every structural operation goes through the trampoline, except
    // null? which is a pure tag test (nil is an immediate).
    if (op == "car") return gen_host_prim(e, kHostCar, 1, /*raw_bool=*/false);
    if (op == "cdr") return gen_host_prim(e, kHostCdr, 1, false);
    if (op == "cons") return gen_host_prim(e, kHostCons, 2, false);
    if (op == "list") return gen_list_ctor(e);
    if (op == "length") return gen_host_prim(e, kHostLength, 1, false);
    if (op == "list-ref") return gen_host_prim(e, kHostListRef, 2, false);
    if (op == "pair?") return gen_host_prim(e, kHostIsPair, 1, /*raw_bool=*/true);
    if (op == "null?") return gen_null_p(e);
    if (op == "vector-ref") return gen_host_prim(e, kHostTupleRef, 2, false);
    if (op == "vector-length") return gen_host_prim(e, kHostTupleSize, 1, false);
    if (op == "hash-table-ref") return gen_host_prim(e, kHostMapRef, 2, false);
    if (op == "string-length") return gen_host_prim(e, kHostBinSize, 1, false);
    if (op == "string=?") return gen_host_prim(e, kHostStrEq, 2, /*raw_bool=*/true);
    if (op == "hash-table-set") return gen_hash_table_set(e);
    if (op == "logand") return gen_binary_prim(e, Op::AND);
    if (op == "logxor") return gen_binary_prim(e, Op::XOR);
    if (op == "ash") return gen_ash(e);

    return gen_call(e);
  }

  // --- Lambda / closures ---

  // Collects free variables of a lambda body: symbols not bound inside
  // the lambda that resolve to a local in THIS (enclosing) function.
  void collect_free(const SExpr& e, std::set<std::string>& bound,
                    std::vector<std::string>& order, std::set<std::string>& seen) {
    switch (e.kind) {
      case SExpr::Kind::Int:
      case SExpr::Kind::Bool: return;
      case SExpr::Kind::Sym: {
        if (bound.count(e.sym) || seen.count(e.sym)) return;
        if (lookup(e.sym) >= 0) {
          seen.insert(e.sym);
          order.push_back(e.sym);
        }
        return;
      }
      case SExpr::Kind::List: break;
    }
    if (e.list.empty()) return;
    const SExpr& head = e.list[0];

    if (head.kind == SExpr::Kind::Sym) {
      const std::string& op = head.sym;
      if (op == "lambda" && e.list.size() >= 3 && e.list[1].kind == SExpr::Kind::List) {
        std::set<std::string> inner_bound = bound;
        for (const SExpr& p : e.list[1].list) {
          if (p.kind == SExpr::Kind::Sym) inner_bound.insert(p.sym);
        }
        for (size_t i = 2; i < e.list.size(); ++i) {
          collect_free(e.list[i], inner_bound, order, seen);
        }
        return;
      }
      if ((op == "let" || op == "let*") && e.list.size() >= 3 &&
          e.list[1].kind == SExpr::Kind::List) {
        std::set<std::string> inner_bound = bound;
        for (const SExpr& binding : e.list[1].list) {
          if (binding.kind != SExpr::Kind::List || binding.list.size() != 2) continue;
          // let: inits see the outer bindings; let*: progressive.
          collect_free(binding.list[1], op == "let*" ? inner_bound : bound, order, seen);
          if (binding.list[0].kind == SExpr::Kind::Sym) inner_bound.insert(binding.list[0].sym);
        }
        for (size_t i = 2; i < e.list.size(); ++i) {
          collect_free(e.list[i], inner_bound, order, seen);
        }
        return;
      }
      if (is_special_form(op) || is_primitive(op)) {
        for (size_t i = 1; i < e.list.size(); ++i) collect_free(e.list[i], bound, order, seen);
        return;
      }
      // Head symbol: a top-level define is a direct call (not free); a
      // bound/enclosing local in operator position is a closure ref.
      if (ctx.find(op) < 0) collect_free(head, bound, order, seen);
      for (size_t i = 1; i < e.list.size(); ++i) collect_free(e.list[i], bound, order, seen);
      return;
    }
    for (const SExpr& child : e.list) collect_free(child, bound, order, seen);
  }

  // (lambda (params...) body...) -> lifted top-level function taking the
  // closure itself as a hidden first argument, plus a heap closure record
  // [code_addr, captures...] built at the point of the lambda expression.
  int gen_lambda(const SExpr& e) {
    if (e.list.size() < 3 || e.list[1].kind != SExpr::Kind::List) {
      fail("lambda wants (lambda (params...) body...)");
    }
    std::set<std::string> bound;
    for (const SExpr& p : e.list[1].list) {
      if (p.kind != SExpr::Kind::Sym) fail("lambda parameters must be symbols");
      bound.insert(p.sym);
    }
    std::vector<std::string> captures;
    std::set<std::string> seen;
    for (size_t i = 2; i < e.list.size(); ++i) collect_free(e.list[i], bound, captures, seen);

    int num_declared = static_cast<int>(e.list[1].list.size());
    int lifted_idx =
        ctx.add_function("lambda$" + std::to_string(ctx.lambda_counter++), 1 + num_declared);

    {
      FnCodegen inner{ctx, ctx.fns[lifted_idx]};
      inner.scopes.emplace_back();
      for (int p = 0; p < num_declared; ++p) {
        inner.scopes.back()[e.list[1].list[static_cast<size_t>(p)].sym] = 1 + p;
      }
      // Unpack captures from the closure record (hidden arg, vreg 0).
      int mask = inner.emit_imm(-8);
      int raw = inner.emit_binop(Op::AND, 0, mask);
      for (size_t c = 0; c < captures.size(); ++c) {
        int slot = inner.emit_load_mem(raw, 8 * static_cast<int64_t>(1 + c));
        inner.scopes.back()[captures[c]] = slot;
        inner.captured_names.insert(captures[c]);
      }
      int result = inner.gen_body(e.list, 2);
      Instr ret;
      ret.op = Op::RETURN;
      ret.a = result;
      inner.emit(ret);
    }

    // Build the closure record here, in the enclosing function.
    int record = emit_alloc(8 * static_cast<int64_t>(1 + captures.size()));
    emit_store_mem(record, 0, emit_load_func_addr(lifted_idx));
    for (size_t c = 0; c < captures.size(); ++c) {
      int vreg = lookup(captures[c]);
      if (vreg < 0) fail("internal: capture vanished: " + captures[c]);
      emit_store_mem(record, 8 * static_cast<int64_t>(1 + c), vreg);
    }
    int tag = emit_imm(kClosureTag);
    return emit_binop(Op::OR, record, tag);
  }

  // (let name ((v1 init1) (v2 init2)...) body...) -- named let (RFD
  // 0025). Lifts to a top-level function (mangled name, so multiple
  // `(let loop ...)` forms across a program don't collide), called
  // recursively by direct CALL, not through a closure: no capture of
  // enclosing free variables is supported (only the loop's own
  // parameters and globals) -- narrower than lambda's semantics, but
  // matches every named-let this compiler's ported content actually
  // uses. Init expressions are evaluated in the CALLING scope, before
  // the new function is entered.
  int gen_named_let(const SExpr& e) {
    if (e.list.size() < 4 || e.list[2].kind != SExpr::Kind::List) {
      fail("named let wants (let name ((v init)...) body...)");
    }
    const std::string& loop_name = e.list[1].sym;
    const SExpr& bindings = e.list[2];

    std::vector<std::string> param_names;
    std::vector<int> init_vregs;
    for (const SExpr& b : bindings.list) {
      if (b.kind != SExpr::Kind::List || b.list.size() != 2 || b.list[0].kind != SExpr::Kind::Sym) {
        fail("named let binding must be (name expr)");
      }
      param_names.push_back(b.list[0].sym);
      init_vregs.push_back(gen_expr(b.list[1]));
    }

    std::string mangled = loop_name + "$" + std::to_string(ctx.named_let_counter++);
    int fn_idx = ctx.add_function(mangled, static_cast<int>(param_names.size()));

    {
      FnCodegen inner{ctx, ctx.fns[static_cast<size_t>(fn_idx)]};
      inner.named_let_alias = loop_name;
      inner.named_let_target_idx = fn_idx;
      inner.scopes.emplace_back();
      for (size_t p = 0; p < param_names.size(); ++p) {
        inner.scopes.back()[param_names[p]] = static_cast<int>(p);
      }
      int result = inner.gen_body(e.list, 3);
      Instr ret;
      ret.op = Op::RETURN;
      ret.a = result;
      inner.emit(ret);
    }

    Instr in;
    in.op = Op::CALL;
    in.callee = fn_idx;
    in.args = init_vregs;
    in.dst = new_vreg();
    emit(in);
    return in.dst;
  }

  int gen_closure_call(int closure_vreg, const SExpr& e) {
    Instr in;
    in.op = Op::CALL_INDIRECT;
    in.args.push_back(closure_vreg);  // hidden self argument
    for (size_t i = 1; i < e.list.size(); ++i) in.args.push_back(gen_expr(e.list[i]));
    int mask = emit_imm(-8);
    int raw = emit_binop(Op::AND, closure_vreg, mask);
    in.a = emit_load_mem(raw, 0);  // code address
    in.dst = new_vreg();
    emit(in);
    return in.dst;
  }

  // --- Core forms ---

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

  // (cond (test1 body1...) (test2 body2...) ... (else bodyN...)) --
  // desugars to nested if at codegen time (RFD 0025), no IR changes.
  // Each clause needs a non-empty body (a bodyless clause returning the
  // test's own truthy value, legal in real Scheme, isn't supported here
  // -- nothing in this compiler's ported content needs it). No clause
  // matching falls through to nil, matching gen_if's own "no else" rule.
  int gen_cond(const SExpr& e) {
    if (e.list.size() < 2) fail("cond wants at least one clause");
    int result = new_vreg();
    int end_label = new_label();

    for (size_t i = 1; i < e.list.size(); ++i) {
      const SExpr& clause = e.list[i];
      if (clause.kind != SExpr::Kind::List || clause.list.size() < 2) {
        fail("cond clause must be (test body...)");
      }
      bool is_else = clause.list[0].kind == SExpr::Kind::Sym && clause.list[0].sym == "else";
      if (is_else) {
        emit_move(result, gen_body(clause.list, 1));
        emit_jump(end_label);
        break;
      }
      int next_label = new_label();
      branch_if_false(gen_expr(clause.list[0]), next_label);
      emit_move(result, gen_body(clause.list, 1));
      emit_jump(end_label);
      emit_label(next_label);
    }

    emit_move(result, emit_imm(kNil));
    emit_label(end_label);
    return result;
  }

  int gen_let(const SExpr& e, bool sequential) {
    if (e.list.size() < 3) fail("let wants bindings + body");
    const SExpr& bindings = e.list[1];
    if (bindings.kind != SExpr::Kind::List) fail("let bindings must be a list");

    scopes.emplace_back();
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
    if (captured_names.count(e.list[1].sym)) {
      fail("set! on a captured variable is not supported (captures are by value): " +
           e.list[1].sym);
    }
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
        branch_if_false(result, end_label);
      } else {
        int f = emit_imm(kFalse);
        int diff = emit_binop(Op::XOR, result, f);
        int is_f = emit_eqz(diff);  // 1 when result was #f
        emit_branch_zero(is_f, end_label);
      }
    }
    emit_label(end_label);
    return result;
  }

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
      return emit_binop(Op::CHECKED_SUB, zero, gen_expr(e.list[1]));
    }
    int acc = gen_expr(e.list[1]);
    for (size_t i = 2; i < e.list.size(); ++i) {
      acc = emit_binop(Op::CHECKED_SUB, acc, gen_expr(e.list[i]));
    }
    return acc;
  }

  int gen_binary_prim(const SExpr& e, Op op) {
    if (e.list.size() != 3) fail("binary primitive wants 2 arguments");
    return emit_binop(op, gen_expr(e.list[1]), gen_expr(e.list[2]));
  }

  // (ash value shift): arithmetic shift, positive = left, negative =
  // right (RFD 0024). Left shift works directly on the TAGGED value
  // (shifting left never disturbs the tag's zero low bits regardless of
  // shift amount); right shift does NOT commute with the tag the same
  // way and must untag -> shift -> retag, or tag bits leak into the
  // result. The shift amount itself is always untagged first.
  int gen_ash(const SExpr& e) {
    if (e.list.size() != 3) fail("ash wants 2 arguments");
    int value = gen_expr(e.list[1]);
    int shift_tagged = gen_expr(e.list[2]);
    int three = emit_imm(3);
    int shift_raw = emit_binop(Op::SRA, shift_tagged, three);
    int sign = emit_binop(Op::SRA, shift_raw, emit_imm(63));  // 0 if >=0, -1 if <0

    int result = new_vreg();
    int positive_label = new_label();
    int end_label = new_label();

    emit_branch_zero(sign, positive_label);

    // Negative: right shift by -shift_raw, untag/shift/retag.
    int neg_shift = emit_binop(Op::SUB, emit_imm(0), shift_raw);
    int untagged = emit_binop(Op::SRA, value, three);
    int shifted = emit_binop(Op::SRA, untagged, neg_shift);
    emit_move(result, emit_binop(Op::SLL, shifted, three));
    emit_jump(end_label);

    // Non-negative: left shift the tagged value directly.
    emit_label(positive_label);
    emit_move(result, emit_binop(Op::SLL, value, shift_raw));

    emit_label(end_label);
    return result;
  }

  // Bignum-correct ordering via CHECKED_LT (raw 0/1), then bool-tag.
  int gen_compare(const SExpr& e, bool swap, bool negate) {
    if (e.list.size() != 3) fail("comparison wants 2 arguments");
    int a = gen_expr(e.list[1]);
    int b = gen_expr(e.list[2]);
    int raw = swap ? emit_binop(Op::CHECKED_LT, b, a) : emit_binop(Op::CHECKED_LT, a, b);
    if (negate) raw = emit_eqz(raw);
    return tag_raw_bool(raw);
  }

  // Numeric equality (=): bignum-correct, via the host on slow paths.
  int gen_numeric_eq(const SExpr& e) {
    if (e.list.size() != 3) fail("= wants 2 arguments");
    int raw = emit_binop(Op::CHECKED_EQ, gen_expr(e.list[1]), gen_expr(e.list[2]));
    return tag_raw_bool(raw);
  }

  // Identity equality (eq?): raw word comparison -- correct for fixnums,
  // booleans, and nil; unspecified for bignum handles (as in s7).
  int gen_identity_eq(const SExpr& e) {
    if (e.list.size() != 3) fail("eq? wants 2 arguments");
    int diff = emit_binop(Op::XOR, gen_expr(e.list[1]), gen_expr(e.list[2]));
    return tag_raw_bool(emit_eqz(diff));
  }

  // --- Handle-value primitives ---

  int emit_host_op(int64_t host_op, int a, int b) {
    int dst = new_vreg();
    Instr in;
    in.op = Op::HOST_OP;
    in.dst = dst;
    in.a = a;
    in.b = b;
    in.imm = host_op;
    emit(in);
    return dst;
  }

  int gen_host_prim(const SExpr& e, int64_t host_op, size_t arity, bool raw_bool) {
    if (e.list.size() != arity + 1) {
      fail(e.list[0].sym + " wants " + std::to_string(arity) + " argument(s)");
    }
    int a = gen_expr(e.list[1]);
    // Unary ops still ship two operands (fixed trampoline ABI); nil pads.
    int b = arity == 2 ? gen_expr(e.list[2]) : emit_imm(kNil);
    int result = emit_host_op(host_op, a, b);
    return raw_bool ? tag_raw_bool(result) : result;
  }

  // (list a b ...) -> right-folded cons chain ending in nil. (list) is nil.
  int gen_list_ctor(const SExpr& e) {
    std::vector<int> elems;
    for (size_t i = 1; i < e.list.size(); ++i) elems.push_back(gen_expr(e.list[i]));
    int acc = emit_imm(kNil);
    for (size_t i = elems.size(); i-- > 0;) acc = emit_host_op(kHostCons, elems[i], acc);
    return acc;
  }

  // (hash-table-set m k v): functional insert, packed as (list k v) --
  // NOT (cons k v): kHostCons requires its second operand to already be
  // a list or nil, so a raw dotted pair of two arbitrary values isn't
  // constructible that way. A proper 2-element list is (nesting ends in
  // nil, satisfying kHostCons at every step), and the host destructures
  // it as [k, v]. Keeps the existing 2-operand HOST_OP ABI unchanged.
  int gen_hash_table_set(const SExpr& e) {
    if (e.list.size() != 4) fail("hash-table-set wants 3 arguments");
    int map = gen_expr(e.list[1]);
    int key = gen_expr(e.list[2]);
    int value = gen_expr(e.list[3]);
    int nil = emit_imm(kNil);
    int tail = emit_host_op(kHostCons, value, nil);
    int packed = emit_host_op(kHostCons, key, tail);
    return emit_host_op(kHostMapSet, map, packed);
  }

  // (null? x): nil is an immediate, so this never leaves the guest.
  int gen_null_p(const SExpr& e) {
    if (e.list.size() != 2) fail("null? wants 1 argument");
    int n = emit_imm(kNil);
    int diff = emit_binop(Op::XOR, gen_expr(e.list[1]), n);
    return tag_raw_bool(emit_eqz(diff));
  }

  int gen_not(const SExpr& e) {
    if (e.list.size() != 2) fail("not wants 1 argument");
    int f = emit_imm(kFalse);
    int diff = emit_binop(Op::XOR, gen_expr(e.list[1]), f);
    return tag_raw_bool(emit_eqz(diff));
  }

  int gen_call(const SExpr& e) {
    int callee = (!named_let_alias.empty() && e.list[0].sym == named_let_alias)
                     ? named_let_target_idx
                     : ctx.find(e.list[0].sym);
    if (callee < 0) fail("unknown function: " + e.list[0].sym);
    const IRFunction& target = ctx.fns[static_cast<size_t>(callee)];
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
  LowerCtx ctx;

  // Pass 1: register every define's name/arity so bodies can reference
  // any function (mutual recursion) before its body is lowered.
  for (const SExpr& form : forms) {
    if (form.kind != SExpr::Kind::List || form.list.size() < 3 ||
        form.list[0].kind != SExpr::Kind::Sym || form.list[0].sym != "define" ||
        form.list[1].kind != SExpr::Kind::List || form.list[1].list.empty() ||
        form.list[1].list[0].kind != SExpr::Kind::Sym) {
      throw std::runtime_error(
          "codegen: every top-level form must be (define (name args...) body...)");
    }
    const std::string& name = form.list[1].list[0].sym;
    if (ctx.find(name) >= 0) throw std::runtime_error("codegen: duplicate define: " + name);
    ctx.add_function(name, static_cast<int>(form.list[1].list.size()) - 1);
  }

  // Pass 2: lower bodies (lambdas append lifted functions to ctx.fns).
  for (size_t f = 0; f < forms.size(); ++f) {
    const SExpr& form = forms[f];
    FnCodegen gen{ctx, ctx.fns[f]};
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

  IRProgram program;
  program.functions.assign(ctx.fns.begin(), ctx.fns.end());
  return program;
}

}  // namespace s7
