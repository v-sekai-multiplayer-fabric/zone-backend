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

int64_t run_riscv(const std::vector<uint8_t>& elf, const char* entry,
                  const std::vector<int64_t>& args) {
  Machine64 machine(elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
  switch (args.size()) {
    case 0: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry));
    case 1: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, args[0]));
    case 2: return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, args[0], args[1]));
    default: throw std::runtime_error("test harness: unsupported arg count");
  }
}

}  // namespace

int main() {
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

  if (failures > 0) {
    fprintf(stderr, "FAIL: %d of %zu tests failed\n", failures, tests.size());
    return 1;
  }
  printf("PASS: all %zu Stage 1 tests agree across IR oracle, libriscv execution, and expected values\n",
         tests.size());
  return 0;
}
