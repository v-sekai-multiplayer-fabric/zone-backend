// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 4 proof: c_src/s7/fixtures/rebac.scm (compiled through the full
// s7 pipeline) against a hand-written reference oracle mirroring
// standalone/tw_rebac.hpp's check_base -- direct edge match,
// transitive IS_MEMBER_OF, and CONTROLS-via-DELEGATED_TO inversion.
// Every case runs three ways: the reference oracle, the IR interpreter
// oracle, and real libriscv execution. This is the C++-side half of
// RFD 0022's differential testing; test/uro/re_bac_sandbox_test.exs
// covers the Elixir SandboxAdapter vs TaskweftAdapter side.
#include <cstdio>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

#include "../s7/compiler.h"
#include "../s7/host_math.h"
#include "../s7/ir_interpreter.h"
#include "../s7/value.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;

namespace {

struct Edge {
  const char* subj;
  const char* obj;
  const char* rel;
};

// Reference oracle: a direct C++ transcription of tw_rebac.hpp's
// check_base, over the same edge-list shape the compiled program
// walks (so a bug shared between "how we built the .scm" and "how we
// built this oracle" is the only thing that could hide -- the actual
// arithmetic/logic path is independent).
bool ref_check_base(const std::vector<Edge>& edges, const std::string& subj,
                    const std::string& rel, const std::string& obj, int fuel) {
  if (fuel < 1) return false;
  for (const Edge& e : edges) {
    if (subj == e.subj && rel == e.rel && obj == e.obj) return true;
  }
  for (const Edge& e : edges) {
    if (subj == e.subj && std::string(e.rel) == "IS_MEMBER_OF") {
      if (ref_check_base(edges, e.obj, rel, obj, fuel - 1)) return true;
    }
  }
  if (rel == "CONTROLS") {
    for (const Edge& e : edges) {
      if (obj == e.subj && std::string(e.rel) == "DELEGATED_TO" && subj == e.obj) return true;
    }
  }
  return false;
}

int64_t make_graph(s7::HostBignumTable& table, const std::vector<Edge>& edges) {
  std::vector<int64_t> tagged_edges;
  for (const Edge& e : edges) {
    tagged_edges.push_back(
        table.make_list({table.make_binary(e.subj), table.make_binary(e.obj),
                         table.make_binary(e.rel)}));
  }
  return table.make_list(tagged_edges);
}

bool decode_bool(int64_t tagged) {
  if (tagged == s7::kTrue) return true;
  if (tagged == s7::kFalse) return false;
  throw std::runtime_error("verify_rebac: check-rel did not return a boolean");
}

int64_t run_riscv(const std::vector<uint8_t>& elf, const char* entry,
                  const std::vector<int64_t>& args, s7::HostBignumTable& table) {
  Machine64 machine(elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
  machine.set_userdata(&table);
  return static_cast<int64_t>(machine.vmcall<50'000'000ull>(entry, args[0], args[1], args[2],
                                                            args[3], args[4]));
}

// The three relation-name constants the algorithm recognizes -- not
// embeddable as guest literals (the subset has no string literals), so
// passed in as a boxed 3-element list, exactly as the real
// Uro.ReBAC.SandboxAdapter does.
int64_t make_rel_consts(s7::HostBignumTable& table) {
  return table.make_list({table.make_binary("IS_MEMBER_OF"), table.make_binary("CONTROLS"),
                          table.make_binary("DELEGATED_TO")});
}

struct TestCase {
  const char* name;
  std::vector<Edge> edges;
  const char* subj;
  const char* rel;
  const char* obj;
};

}  // namespace

int main() {
  Machine64::install_syscall_handler(
      static_cast<size_t>(s7::kSyscallHostMath), [](Machine64& machine) {
        auto* table = machine.get_userdata<s7::HostBignumTable>();
        auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
        machine.set_result(table->apply(op, a, b));
      });

  const std::vector<TestCase> tests = {
      {"direct-edge-hit", {{"alice", "zone1", "OWNS"}}, "alice", "OWNS", "zone1"},
      {"direct-edge-miss", {{"alice", "zone1", "OWNS"}}, "bob", "OWNS", "zone1"},
      {"wrong-relation", {{"alice", "zone1", "OWNS"}}, "alice", "CAN_ENTER", "zone1"},
      {"member-transitive-hit",
       {{"alice", "avatar_uploaders", "IS_MEMBER_OF"},
        {"avatar_uploaders", "uploads", "HAS_CAPABILITY"}},
       "alice", "HAS_CAPABILITY", "uploads"},
      {"member-transitive-miss",
       {{"alice", "avatar_uploaders", "IS_MEMBER_OF"},
        {"avatar_uploaders", "uploads", "HAS_CAPABILITY"}},
       "bob", "HAS_CAPABILITY", "uploads"},
      {"member-chain-two-deep",
       {{"alice", "group_a", "IS_MEMBER_OF"},
        {"group_a", "group_b", "IS_MEMBER_OF"},
        {"group_b", "zone1", "CAN_ENTER"}},
       "alice", "CAN_ENTER", "zone1"},
      {"controls-via-delegation",
       {{"zone1", "alice", "DELEGATED_TO"}}, "alice", "CONTROLS", "zone1"},
      {"controls-without-delegation", {}, "alice", "CONTROLS", "zone1"},
      {"empty-graph-is-false", {}, "alice", "OWNS", "zone1"},
      {"member-does-not-imply-other-rel",
       {{"alice", "group_a", "IS_MEMBER_OF"}}, "alice", "OWNS", "zone1"},
  };

  int failures = 0;
  s7::Compiled compiled = s7::compile(R"SCM(
(define (edge-subj e) (car e))
(define (edge-obj e) (car (cdr e)))
(define (edge-rel e) (car (cdr (cdr e))))
(define (rc-member rc) (car rc))
(define (rc-controls rc) (car (cdr rc)))
(define (rc-delegated rc) (car (cdr (cdr rc))))
(define (find-direct edges subj rel obj)
  (if (null? edges) #f
      (if (and (string=? (edge-subj (car edges)) subj)
               (string=? (edge-rel (car edges)) rel)
               (string=? (edge-obj (car edges)) obj))
          #t
          (find-direct (cdr edges) subj rel obj))))
(define (find-member-transitive edges all-edges subj rel obj fuel rc)
  (if (null? edges) #f
      (if (and (string=? (edge-subj (car edges)) subj)
               (string=? (edge-rel (car edges)) (rc-member rc)))
          (if (check-base all-edges (edge-obj (car edges)) rel obj (- fuel 1) rc)
              #t
              (find-member-transitive (cdr edges) all-edges subj rel obj fuel rc))
          (find-member-transitive (cdr edges) all-edges subj rel obj fuel rc))))
(define (find-controls-delegation edges subj obj rc)
  (if (null? edges) #f
      (if (and (string=? (edge-subj (car edges)) obj)
               (string=? (edge-rel (car edges)) (rc-delegated rc))
               (string=? (edge-obj (car edges)) subj))
          #t
          (find-controls-delegation (cdr edges) subj obj rc))))
(define (check-base edges subj rel obj fuel rc)
  (if (< fuel 1) #f
      (if (find-direct edges subj rel obj) #t
          (if (find-member-transitive edges edges subj rel obj fuel rc) #t
              (if (string=? rel (rc-controls rc))
                  (find-controls-delegation edges subj obj rc)
                  #f)))))
(define (check-rel graph subj rel obj rc) (check-base graph subj rel obj 8 rc))
)SCM");
  int func_index = compiled.ir.find("check-rel");
  if (func_index < 0) {
    fprintf(stderr, "FAIL: check-rel not found in compiled program\n");
    return 1;
  }

  for (const TestCase& test : tests) {
    try {
      bool expected = ref_check_base(test.edges, test.subj, test.rel, test.obj, 8);

      s7::HostBignumTable oracle_table;
      int64_t graph_o = make_graph(oracle_table, test.edges);
      std::vector<int64_t> args_o = {graph_o, oracle_table.make_binary(test.subj),
                                     oracle_table.make_binary(test.rel),
                                     oracle_table.make_binary(test.obj),
                                     make_rel_consts(oracle_table)};
      bool oracle =
          decode_bool(s7::interpret(compiled.ir, func_index, args_o, 50'000'000, &oracle_table));

      s7::HostBignumTable machine_table;
      int64_t graph_m = make_graph(machine_table, test.edges);
      std::vector<int64_t> args_m = {graph_m, machine_table.make_binary(test.subj),
                                     machine_table.make_binary(test.rel),
                                     machine_table.make_binary(test.obj),
                                     make_rel_consts(machine_table)};
      bool machine = decode_bool(run_riscv(compiled.elf, "check-rel", args_m, machine_table));

      if (oracle != expected || machine != expected) {
        fprintf(stderr, "FAIL %-28s expected=%d oracle=%d riscv=%d\n", test.name, expected,
                oracle, machine);
        failures++;
      } else {
        printf("ok   %-28s -> %s (ref == oracle == riscv)\n", test.name,
               expected ? "#t" : "#f");
      }
    } catch (const std::exception& e) {
      fprintf(stderr, "FAIL %-28s exception: %s\n", test.name, e.what());
      failures++;
    }
  }

  if (failures > 0) {
    fprintf(stderr, "FAIL: %d of %zu rebac tests diverged\n", failures, tests.size());
    return 1;
  }
  printf("PASS: all %zu rebac tests agree between the reference oracle, the IR oracle, and "
         "compiled RISC-V execution\n",
         tests.size());
  return 0;
}
