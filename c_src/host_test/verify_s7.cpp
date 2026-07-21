// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 1 proof: compile s7-subset Scheme sources through the full
// pipeline (reader -> IR -> riscv_codegen -> elf_builder, no
// riscv-none-elf-gcc involved at all) and cross-check THREE ways per
// test: the IR interpreter oracle, real execution inside
// libriscv::Machine, and the hand-computed expected value. A lowering
// bug and an encoding bug can never masquerade as each other. No
// NIF/Elixir/BEAM involved -- same standalone-proof shape as
// host_test/verify_guest.cpp.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

#include "../s7/compiler.h"
#include "../s7/host_math.h"
#include "../s7/ir_interpreter.h"
#include "../s7/value.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;

namespace {

struct TestCase {
  const char* name;
  const char* source;
  const char* entry;
  std::vector<int64_t> args;  // already tagged
  int64_t expected;           // tagged
};

// The host side of the checked-arithmetic ABI (RFD 0018): the guest
// ecalls with a7=kSyscallHostMath and the host computes with the
// reference __int128 table (the production NIF does the same with
// Elixir's native bignums via the trampoline instead).
void install_host_math() {
  Machine64::install_syscall_handler(
      static_cast<size_t>(s7::kSyscallHostMath), [](Machine64& machine) {
        auto* table = machine.get_userdata<s7::HostBignumTable>();
        auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
        machine.set_result(table->apply(op, a, b));
      });
}

int64_t run_riscv(const std::vector<uint8_t>& elf, const char* entry,
                  const std::vector<int64_t>& args, s7::HostBignumTable* shared = nullptr) {
  Machine64 machine(elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
  s7::HostBignumTable local;
  machine.set_userdata(shared ? shared : &local);
  switch (args.size()) {
    case 0: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry));
    case 1: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, args[0]));
    case 2: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, args[0], args[1]));
    case 3:
      return static_cast<int64_t>(
          machine.vmcall<50'000'000ull>(entry, args[0], args[1], args[2]));
    default: throw std::runtime_error("test harness: unsupported arg count");
  }
}

// Structural print of a tagged result against its table -- handle
// indices differ between the oracle run and the riscv run (each
// allocates independently), so results compare by content, not word.
std::string decode_str(s7::HostBignumTable& table, int64_t tagged) {
  if ((tagged & 7) == 0) return std::to_string(tagged >> 3);
  if (tagged == s7::kTrue) return "#t";
  if (tagged == s7::kFalse) return "#f";
  if (tagged == s7::kNil) return "()";
  if ((tagged & 7) == s7::kHandleTag) {
    const s7::HostValue& v = table.deref(tagged);
    switch (v.kind) {
      case s7::HostValue::Kind::Bignum: return "#<bignum>";
      case s7::HostValue::Kind::List: {
        std::string out = "(";
        for (size_t i = 0; i < v.items.size(); ++i) {
          if (i) out += " ";
          out += decode_str(table, v.items[i]);
        }
        return out + ")";
      }
      case s7::HostValue::Kind::Tuple: return "#<tuple:" + std::to_string(v.items.size()) + ">";
      case s7::HostValue::Kind::Map: return "#<map:" + std::to_string(v.entries.size()) + ">";
      case s7::HostValue::Kind::Binary: return "\"" + v.bytes + "\"";
      case s7::HostValue::Kind::Atom: return "'" + v.bytes;
    }
  }
  return "#<closure-or-unknown>";
}

// Handle-value tests: arguments are built into a host table per
// execution path (the table is stateful -- cdr/cons allocate).
struct ValueTest {
  const char* name;
  const char* source;
  const char* entry;
  std::vector<int64_t> (*build_args)(s7::HostBignumTable&);
  const char* expected;  // decode_str form
};

}  // namespace

int main() {
  install_host_math();

  const std::vector<TestCase> tests = {
      {"add", "(define (main) (+ 1 2))", "main", {}, s7::tag_fixnum(3)},
      {"arith-mix",
       "(define (main) (- (* 6 7) (quotient 100 7) (remainder 100 7)))",
       "main", {}, s7::tag_fixnum(26)},
      {"big-constants", "(define (main) (+ 123456789 987654321))", "main", {},
       s7::tag_fixnum(1111111110)},
      {"negative", "(define (main) (- 5 12))", "main", {}, s7::tag_fixnum(-7)},
      {"fact",
       "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))\n"
       "(define (main) (fact 12))",
       "main", {}, s7::tag_fixnum(479001600)},
      {"fib",
       "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))\n"
       "(define (main) (fib 15))",
       "main", {}, s7::tag_fixnum(610)},
      {"let-set-begin",
       "(define (main) (let ((x 10) (y 20)) (begin (set! x (+ x y)) (* x 2))))",
       "main", {}, s7::tag_fixnum(60)},
      {"let-star", "(define (main) (let* ((x 5) (y (* x x))) (- y x)))", "main", {},
       s7::tag_fixnum(20)},
      {"compare-true", "(define (main) (< 1 2))", "main", {}, s7::kTrue},
      {"compare-chain",
       "(define (main) (and (< 1 2) (> 3 2) (= 4 4) (not (< 5 4)) (>= 4 4) (<= 3 4)))",
       "main", {}, s7::kTrue},
      {"or-first-truthy", "(define (main) (or #f #f 7))", "main", {}, s7::tag_fixnum(7)},
      {"if-no-else", "(define (main) (if #f 1))", "main", {}, s7::kNil},
      {"eq-bools", "(define (main) (eq? #t #t))", "main", {}, s7::kTrue},
      {"args-2", "(define (add2 a b) (+ a b))", "add2",
       {s7::tag_fixnum(20), s7::tag_fixnum(22)}, s7::tag_fixnum(42)},
      // --- Stage 2: closures ---
      {"lambda-immediate", "(define (main) ((lambda (x y) (* x y)) 6 7))", "main", {},
       s7::tag_fixnum(42)},
      {"make-adder",
       "(define (make-adder n) (lambda (x) (+ x n)))\n"
       "(define (main) (let ((add5 (make-adder 5))) (add5 37)))",
       "main", {}, s7::tag_fixnum(42)},
      {"compose",
       "(define (compose f g) (lambda (x) (f (g x))))\n"
       "(define (main)\n"
       "  (let ((inc (lambda (x) (+ x 1)))\n"
       "        (dbl (lambda (x) (* x 2))))\n"
       "    ((compose inc dbl) 20)))",
       "main", {}, s7::tag_fixnum(41)},
      {"nested-capture",
       "(define (main)\n"
       "  (let ((a 10))\n"
       "    (let ((f (lambda (b) (lambda (c) (+ a (+ b c))))))\n"
       "      ((f 20) 12))))",
       "main", {}, s7::tag_fixnum(42)},
      {"closure-as-branch-value",
       "(define (pick which) (if which (lambda (x) (+ x 1)) (lambda (x) (- x 1))))\n"
       "(define (main) (+ ((pick #t) 10) ((pick #f) 10)))",
       "main", {}, s7::tag_fixnum(20)},
      {"two-closures-independent",
       "(define (make-adder n) (lambda (x) (+ x n)))\n"
       "(define (main) (+ ((make-adder 100) 1) ((make-adder 200) 2)))",
       "main", {}, s7::tag_fixnum(303)},
      // --- Checked arithmetic / bignums (RFD 0018) ---
      {"overflow-roundtrip",
       "(define (main) (- (+ 1152921504606846975 5) 10))",
       "main", {}, s7::tag_fixnum(1152921504606846970)},
      {"fixnum-min-exact",
       "(define (main) (- 0 (+ 1152921504606846975 1)))",
       "main", {}, s7::tag_fixnum(-1152921504606846976)},
      {"bignum-fact-ratio",
       "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))\n"
       "(define (main) (quotient (fact 25) (fact 24)))",
       "main", {}, s7::tag_fixnum(25)},
      {"bignum-remainder",
       "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))\n"
       "(define (main) (remainder (fact 25) 1000000))",
       "main", {}, s7::tag_fixnum(0)},
      {"bignum-lt",
       "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))\n"
       "(define (main) (< (fact 20) (fact 21)))",
       "main", {}, s7::kTrue},
      {"bignum-numeric-eq",
       "(define (main) (= (+ 1152921504606846975 1) (+ 1152921504606846975 1)))",
       "main", {}, s7::kTrue},
      // --- RFD 0024: bitwise primitives ---
      {"logand-basic", "(define (main) (logand 12 10))", "main", {}, s7::tag_fixnum(8)},
      {"logxor-basic", "(define (main) (logxor 12 10))", "main", {}, s7::tag_fixnum(6)},
      {"ash-left", "(define (main) (ash 1 4))", "main", {}, s7::tag_fixnum(16)},
      {"ash-right", "(define (main) (ash 256 -4))", "main", {}, s7::tag_fixnum(16)},
      {"ash-right-zero", "(define (main) (ash 5 0))", "main", {}, s7::tag_fixnum(5)},
      {"xorshift32-like",
       // 4294967295 = #xFFFFFFFF -- the reader has no hex literal syntax.
       "(define (u32 x) (logand x 4294967295))\n"
       "(define (main s)\n"
       "  (let* ((s (u32 (logxor s (u32 (ash s 13)))))\n"
       "         (s (u32 (logxor s (ash s -17))))\n"
       "         (s (u32 (logxor s (u32 (ash s 5))))))\n"
       "    s))",
       "main", {s7::tag_fixnum(42)}, s7::tag_fixnum(11355432)},
      // --- RFD 0025: cond ---
      {"cond-first-match", "(define (main) (cond (#t 1) (#t 2)))", "main", {}, s7::tag_fixnum(1)},
      {"cond-second-match", "(define (main) (cond (#f 1) (#t 2)))", "main", {}, s7::tag_fixnum(2)},
      {"cond-else", "(define (main) (cond (#f 1) (else 3)))", "main", {}, s7::tag_fixnum(3)},
      {"cond-no-match", "(define (main) (cond (#f 1) (#f 2)))", "main", {}, s7::kNil},
      {"cond-damage-of",
       "(define (damage-of stage) (cond ((= stage 0) 10) ((= stage 1) 15) (else 25)))\n"
       "(define (main) (+ (damage-of 0) (+ (damage-of 1) (damage-of 2))))",
       "main", {}, s7::tag_fixnum(50)},
      // --- RFD 0025: named let ---
      {"named-let-sum",
       "(define (main)\n"
       "  (let loop ((i 0) (acc 0))\n"
       "    (if (= i 5) acc (loop (+ i 1) (+ acc i)))))",
       "main", {}, s7::tag_fixnum(10)},
      {"named-let-two-in-one-program",
       "(define (f) (let loop ((i 0)) (if (= i 3) i (loop (+ i 1)))))\n"
       "(define (g) (let loop ((i 0)) (if (= i 7) i (loop (+ i 1)))))\n"
       "(define (main) (+ (f) (g)))",
       "main", {}, s7::tag_fixnum(10)},
  };

  const std::vector<ValueTest> value_tests = {
      {"sum-list",
       "(define (sum l) (if (null? l) 0 (+ (car l) (sum (cdr l)))))",
       "sum",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{t.make_list({s7::tag_fixnum(1), s7::tag_fixnum(2),
                                                  s7::tag_fixnum(3), s7::tag_fixnum(4),
                                                  s7::tag_fixnum(5)})};
       },
       "15"},
      {"length-and-ref",
       "(define (main l) (+ (length l) (list-ref l 1)))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{
             t.make_list({s7::tag_fixnum(10), s7::tag_fixnum(20), s7::tag_fixnum(30)})};
       },
       "23"},
      {"pair-predicates",
       "(define (main l) (and (pair? l) (not (pair? 5)) (null? (cdr (cons 1 (list))))))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{t.make_list({s7::tag_fixnum(1)})};
       },
       "#t"},
      {"list-ctor-roundtrip",
       "(define (main a b) (cons a (list b 3)))",
       "main",
       [](s7::HostBignumTable&) {
         return std::vector<int64_t>{s7::tag_fixnum(1), s7::tag_fixnum(2)};
       },
       "(1 2 3)"},
      {"tuple-ops",
       "(define (main t) (+ (vector-ref t 1) (vector-length t)))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{
             t.make_tuple({s7::tag_fixnum(7), s7::tag_fixnum(40), s7::tag_fixnum(9)})};
       },
       "43"},
      {"map-hit-and-miss",
       "(define (main m k) (if (hash-table-ref m k) (hash-table-ref m k) -1))",
       "main",
       [](s7::HostBignumTable& t) {
         int64_t m = t.make_map({{t.make_atom("hp"), s7::tag_fixnum(100)},
                                 {t.make_atom("mp"), s7::tag_fixnum(30)}});
         return std::vector<int64_t>{m, t.make_atom("hp")};
       },
       "100"},
      {"map-miss-is-false",
       "(define (main m k) (hash-table-ref m k))",
       "main",
       [](s7::HostBignumTable& t) {
         int64_t m = t.make_map({{t.make_atom("hp"), s7::tag_fixnum(100)}});
         return std::vector<int64_t>{m, t.make_atom("armor")};
       },
       "#f"},
      {"binary-size",
       "(define (main b) (string-length b))",
       "main",
       [](s7::HostBignumTable& t) { return std::vector<int64_t>{t.make_binary("hello")}; },
       "5"},
      {"string-eq-content",
       "(define (main a b) (string=? a b))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{t.make_binary("alice"), t.make_binary("alice")};
       },
       "#t"},
      {"string-eq-mismatch",
       "(define (main a b) (string=? a b))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{t.make_binary("alice"), t.make_binary("bob")};
       },
       "#f"},
      {"atom-eq-interned",
       "(define (main a b c) (and (eq? a b) (not (eq? a c))))",
       "main",
       [](s7::HostBignumTable& t) {
         return std::vector<int64_t>{t.make_atom("fire"), t.make_atom("fire"),
                                     t.make_atom("water")};
       },
       "#t"},
  };

  int failures = 0;
  for (const TestCase& test : tests) {
    try {
      s7::Compiled compiled = s7::compile(test.source);

      int func_index = compiled.ir.find(test.entry);
      if (func_index < 0) throw std::runtime_error("entry function not found");
      int64_t oracle = s7::interpret(compiled.ir, func_index, test.args);
      int64_t machine = run_riscv(compiled.elf, test.entry, test.args);

      if (oracle != test.expected || machine != test.expected) {
        fprintf(stderr, "FAIL %-16s expected=%lld oracle=%lld riscv=%lld\n", test.name,
                (long long)test.expected, (long long)oracle, (long long)machine);
        failures++;
      } else {
        printf("ok   %-16s -> %lld (oracle == riscv == expected)\n", test.name,
               (long long)test.expected);
      }
    } catch (const std::exception& e) {
      fprintf(stderr, "FAIL %-16s exception: %s\n", test.name, e.what());
      failures++;
    }
  }

  for (const ValueTest& test : value_tests) {
    try {
      s7::Compiled compiled = s7::compile(test.source);
      int func_index = compiled.ir.find(test.entry);
      if (func_index < 0) throw std::runtime_error("entry function not found");

      // Each execution path gets its own table: handle indices diverge
      // as the run allocates, so results compare structurally.
      s7::HostBignumTable oracle_table;
      std::vector<int64_t> oracle_args = test.build_args(oracle_table);
      int64_t oracle =
          s7::interpret(compiled.ir, func_index, oracle_args, 50'000'000, &oracle_table);
      std::string oracle_str = decode_str(oracle_table, oracle);

      s7::HostBignumTable machine_table;
      std::vector<int64_t> machine_args = test.build_args(machine_table);
      int64_t machine = run_riscv(compiled.elf, test.entry, machine_args, &machine_table);
      std::string machine_str = decode_str(machine_table, machine);

      if (oracle_str != test.expected || machine_str != test.expected) {
        fprintf(stderr, "FAIL %-20s expected=%s oracle=%s riscv=%s\n", test.name, test.expected,
                oracle_str.c_str(), machine_str.c_str());
        failures++;
      } else {
        printf("ok   %-20s -> %s (oracle == riscv == expected)\n", test.name, test.expected);
      }
    } catch (const std::exception& e) {
      fprintf(stderr, "FAIL %-20s exception: %s\n", test.name, e.what());
      failures++;
    }
  }

  size_t total = tests.size() + value_tests.size();
  if (failures > 0) {
    fprintf(stderr, "FAIL: %d of %zu tests failed\n", failures, total);
    return 1;
  }
  printf("PASS: all %zu s7-compiler tests agree across IR oracle, libriscv execution, and expected values\n",
         total);
  return 0;
}
