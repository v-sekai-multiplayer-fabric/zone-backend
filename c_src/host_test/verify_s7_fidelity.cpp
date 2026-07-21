// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 3 fidelity: differential testing of the s7 AOT compiler
// (c_src/s7) against the REAL s7 interpreter (c_src/thirdparty/s7),
// built host-side. The interpreter's answer IS the expected value --
// no hand-computed expectations, so a shared misunderstanding of s7
// semantics between test author and compiler cannot hide. Each corpus
// program runs three ways: real s7, our IR oracle, and our compiled
// code under libriscv; all three must agree.
//
// Documented mapping: our subset returns nil (kNil) where s7 returns
// #<unspecified> (e.g. an if with no else-branch taken) -- the compare
// step treats s7 unspecified and s7 () as both matching our nil.
#include <cinttypes>
#include <cstdio>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

#include "../s7/compiler.h"
#include "../s7/host_math.h"
#include "../s7/ir_interpreter.h"
#include "../s7/value.h"

#include "s7.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;

namespace {

struct Value {
  enum class Kind { Int, Bool, Nil, Other } kind = Kind::Other;
  int64_t i = 0;
  bool b = false;

  bool operator==(const Value& other) const {
    if (kind != other.kind) return false;
    if (kind == Kind::Int) return i == other.i;
    if (kind == Kind::Bool) return b == other.b;
    return true;  // Nil == Nil, Other == Other
  }

  std::string str() const {
    switch (kind) {
      case Kind::Int: return std::to_string(i);
      case Kind::Bool: return b ? "#t" : "#f";
      case Kind::Nil: return "nil/unspecified";
      case Kind::Other: return "#<other>";
    }
    return "?";
  }
};

struct TestCase {
  const char* name;
  const char* source;
  const char* entry;
  std::vector<int64_t> args;  // plain integers (tagged for our side, printed for s7)
};

// --- Real s7 interpreter (host-side) ---

Value run_real_s7(const TestCase& test) {
  s7_scheme* sc = s7_init();
  // s7_eval_c_string evaluates one form; wrap multi-define sources.
  std::string wrapped = std::string("(begin ") + test.source + ")";
  s7_eval_c_string(sc, wrapped.c_str());

  std::string call = "(";
  call += test.entry;
  for (int64_t arg : test.args) {
    call += " ";
    call += std::to_string(arg);
  }
  call += ")";
  s7_pointer result = s7_eval_c_string(sc, call.c_str());

  Value v;
  if (s7_is_integer(result)) {
    v.kind = Value::Kind::Int;
    v.i = s7_integer(result);
  } else if (s7_is_boolean(result)) {
    v.kind = Value::Kind::Bool;
    v.b = s7_boolean(sc, result);
  } else if (result == s7_unspecified(sc) || result == s7_nil(sc)) {
    v.kind = Value::Kind::Nil;
  }
  // This s7 version has no s7_free; one leaked interpreter per corpus
  // entry is fine for a short-lived test binary.
  s7_quit(sc);
  return v;
}

// --- Our side (tagged -> Value) ---

Value from_tagged(int64_t tagged) {
  Value v;
  if ((tagged & 7) == 0) {
    v.kind = Value::Kind::Int;
    v.i = tagged >> 3;
  } else if (tagged == s7::kTrue || tagged == s7::kFalse) {
    v.kind = Value::Kind::Bool;
    v.b = tagged == s7::kTrue;
  } else if (tagged == s7::kNil) {
    v.kind = Value::Kind::Nil;
  }
  return v;
}

int64_t run_riscv(const std::vector<uint8_t>& elf, const char* entry,
                  const std::vector<int64_t>& tagged_args) {
  Machine64 machine(elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
  s7::HostBignumTable table;
  machine.set_userdata(&table);
  switch (tagged_args.size()) {
    case 0: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry));
    case 1: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, tagged_args[0]));
    case 2:
      return static_cast<int64_t>(
          machine.vmcall<50'000'000ull>(entry, tagged_args[0], tagged_args[1]));
    default: throw std::runtime_error("fidelity harness: unsupported arg count");
  }
}

}  // namespace

int main() {
  Machine64::install_syscall_handler(
      static_cast<size_t>(s7::kSyscallHostMath), [](Machine64& machine) {
        auto* table = machine.get_userdata<s7::HostBignumTable>();
        auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
        machine.set_result(table->apply(op, a, b));
      });

  // Every program stays within int64-safe arithmetic: the default
  // (non-GMP) s7 build wraps silently past int64, so bignum-promotion
  // behavior is out of scope here (covered by verify_s7's own tests
  // against the reference host instead).
  const std::vector<TestCase> corpus = {
      {"add", "(define (main) (+ 1 2))", "main", {}},
      {"add-identity", "(define (main) (+))", "main", {}},
      {"mul-identity", "(define (main) (*))", "main", {}},
      {"unary-minus", "(define (main) (- 5))", "main", {}},
      {"sub-chain", "(define (main) (- 100 20 3))", "main", {}},
      {"mul-chain", "(define (main) (* 2 3 4))", "main", {}},
      {"arith-mix", "(define (main) (- (* 6 7) (quotient 100 7) (remainder 100 7)))", "main", {}},
      {"quotient-neg-dividend", "(define (main) (quotient -7 2))", "main", {}},
      {"quotient-neg-divisor", "(define (main) (quotient 7 -2))", "main", {}},
      {"remainder-neg-dividend", "(define (main) (remainder -7 2))", "main", {}},
      {"remainder-neg-divisor", "(define (main) (remainder 7 -2))", "main", {}},
      {"fact", "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1))))) (define (main) (fact 12))",
       "main", {}},
      {"fib",
       "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (define (main) (fib 15))",
       "main", {}},
      {"let-shadowing", "(define (main) (let ((x 1)) (let ((x 2)) x)))", "main", {}},
      {"let-set-begin",
       "(define (main) (let ((x 10) (y 20)) (begin (set! x (+ x y)) (* x 2))))", "main", {}},
      {"let-star", "(define (main) (let* ((x 5) (y (* x x))) (- y x)))", "main", {}},
      {"set-returns-value", "(define (main) (let ((x 1)) (set! x 42)))", "main", {}},
      {"compare-lt", "(define (main) (< 1 2))", "main", {}},
      {"compare-chain",
       "(define (main) (and (< 1 2) (> 3 2) (= 4 4) (not (< 5 4)) (>= 4 4) (<= 3 4)))", "main",
       {}},
      {"and-empty", "(define (main) (and))", "main", {}},
      {"or-empty", "(define (main) (or))", "main", {}},
      {"and-returns-last", "(define (main) (and 1 2 3))", "main", {}},
      {"and-stops-at-false", "(define (main) (and 1 #f 3))", "main", {}},
      {"or-returns-first-truthy", "(define (main) (or #f 5 6))", "main", {}},
      {"if-no-else", "(define (main) (if #f 1))", "main", {}},
      {"eq-bools", "(define (main) (eq? #t #t))", "main", {}},
      {"numeric-eq", "(define (main) (= 7 7))", "main", {}},
      {"zero-truthy", "(define (main) (if 0 1 2))", "main", {}},
      {"args-2", "(define (add2 a b) (+ a b))", "add2", {20, 22}},
      {"lambda-immediate", "(define (main) ((lambda (x y) (* x y)) 6 7))", "main", {}},
      {"make-adder",
       "(define (make-adder n) (lambda (x) (+ x n)))"
       "(define (main) (let ((add5 (make-adder 5))) (add5 37)))",
       "main", {}},
      {"compose",
       "(define (compose f g) (lambda (x) (f (g x))))"
       "(define (main) (let ((inc (lambda (x) (+ x 1))) (dbl (lambda (x) (* x 2))))"
       "  ((compose inc dbl) 20)))",
       "main", {}},
      {"nested-capture",
       "(define (main) (let ((a 10)) (let ((f (lambda (b) (lambda (c) (+ a (+ b c))))))"
       "  ((f 20) 12))))",
       "main", {}},
      {"closure-in-branch",
       "(define (pick which) (if which (lambda (x) (+ x 1)) (lambda (x) (- x 1))))"
       "(define (main) (+ ((pick #t) 10) ((pick #f) 10)))",
       "main", {}},
      // Handle-value ops (lists only here: real s7 shares list/car/cdr
      // spelling with our subset; tuple/map/binary spellings diverge
      // and are covered by verify_s7 + the Elixir tests instead).
      {"list-sum",
       "(define (sum l) (if (null? l) 0 (+ (car l) (sum (cdr l)))))"
       "(define (main) (sum (list 1 2 3 4 5)))",
       "main", {}},
      {"list-length", "(define (main) (length (list 1 2 3)))", "main", {}},
      {"list-length-empty", "(define (main) (length (list)))", "main", {}},
      {"list-ref", "(define (main) (list-ref (list 10 20 30) 1))", "main", {}},
      {"cons-car", "(define (main) (car (cons 99 (list 1))))", "main", {}},
      {"pair-true", "(define (main) (pair? (list 1)))", "main", {}},
      {"pair-false", "(define (main) (pair? 7))", "main", {}},
      {"null-of-cdr", "(define (main) (null? (cdr (list 1))))", "main", {}},
  };

  int failures = 0;
  for (const TestCase& test : corpus) {
    try {
      Value real = run_real_s7(test);

      s7::Compiled compiled = s7::compile(test.source);
      int func_index = compiled.ir.find(test.entry);
      if (func_index < 0) throw std::runtime_error("entry function not found");

      std::vector<int64_t> tagged_args;
      for (int64_t arg : test.args) tagged_args.push_back(s7::tag_fixnum(arg));

      Value oracle = from_tagged(s7::interpret(compiled.ir, func_index, tagged_args));
      Value machine = from_tagged(run_riscv(compiled.elf, test.entry, tagged_args));

      if (!(oracle == real) || !(machine == real)) {
        fprintf(stderr, "FAIL %-24s real-s7=%s oracle=%s riscv=%s\n", test.name,
                real.str().c_str(), oracle.str().c_str(), machine.str().c_str());
        failures++;
      } else {
        printf("ok   %-24s -> %s (real s7 == oracle == riscv)\n", test.name, real.str().c_str());
      }
    } catch (const std::exception& e) {
      fprintf(stderr, "FAIL %-24s exception: %s\n", test.name, e.what());
      failures++;
    }
  }

  if (failures > 0) {
    fprintf(stderr, "FAIL: %d of %zu fidelity tests diverged\n", failures, corpus.size());
    return 1;
  }
  printf("PASS: all %zu programs agree between the real s7 interpreter, the IR oracle, and compiled RISC-V execution\n",
         corpus.size());
  return 0;
}
