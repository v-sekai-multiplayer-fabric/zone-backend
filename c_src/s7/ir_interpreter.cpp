// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "ir_interpreter.h"

#include <stdexcept>
#include <unordered_map>

#include "host_math.h"
#include "value.h"

namespace s7 {

namespace {

// Sentinel "code addresses" for LOAD_FUNC_ADDR in the oracle: any value
// far outside the simulated heap range, decodable back to a function
// index by CALL_INDIRECT. The riscv backend uses real addresses; the IR
// treats them as opaque words either way, so the two stay equivalent.
constexpr int64_t kOracleFuncBase = 1ll << 40;

struct Interp {
  const IRProgram& program;
  uint64_t steps_left;
  std::unordered_map<int64_t, int64_t> mem;
  int64_t heap_next = static_cast<int64_t>(kHeapBase) + 8;
  HostBignumTable bignums;

  int64_t run(int func_index, const std::vector<int64_t>& args) {
    if (func_index < 0 || func_index >= static_cast<int>(program.functions.size())) {
      throw std::runtime_error("ir_interpreter: bad function index");
    }
    const IRFunction& func = program.functions[func_index];
    if (static_cast<int>(args.size()) != func.num_params) {
      throw std::runtime_error("ir_interpreter: arity mismatch calling " + func.name);
    }

    std::vector<int64_t> vregs(static_cast<size_t>(func.num_vregs), 0);
    for (size_t i = 0; i < args.size(); ++i) vregs[i] = args[i];

    // Pre-scan labels.
    std::unordered_map<int, size_t> labels;
    for (size_t i = 0; i < func.instrs.size(); ++i) {
      if (func.instrs[i].op == Op::LABEL) labels[func.instrs[i].label] = i;
    }

    size_t pc = 0;
    while (pc < func.instrs.size()) {
      if (steps_left-- == 0) {
        throw std::runtime_error("ir_interpreter: step budget exhausted in " + func.name);
      }
      const Instr& in = func.instrs[pc];
      switch (in.op) {
        case Op::LOAD_IMM: vregs[in.dst] = in.imm; break;
        case Op::MOVE: vregs[in.dst] = vregs[in.a]; break;
        case Op::ADD: vregs[in.dst] = vregs[in.a] + vregs[in.b]; break;
        case Op::SUB: vregs[in.dst] = vregs[in.a] - vregs[in.b]; break;
        case Op::MUL: vregs[in.dst] = vregs[in.a] * vregs[in.b]; break;
        case Op::DIV:
          if (vregs[in.b] == 0) throw std::runtime_error("ir_interpreter: division by zero");
          vregs[in.dst] = vregs[in.a] / vregs[in.b];
          break;
        case Op::REM:
          if (vregs[in.b] == 0) throw std::runtime_error("ir_interpreter: remainder by zero");
          vregs[in.dst] = vregs[in.a] % vregs[in.b];
          break;
        case Op::AND: vregs[in.dst] = vregs[in.a] & vregs[in.b]; break;
        case Op::OR: vregs[in.dst] = vregs[in.a] | vregs[in.b]; break;
        case Op::XOR: vregs[in.dst] = vregs[in.a] ^ vregs[in.b]; break;
        case Op::SLL:
          vregs[in.dst] = static_cast<int64_t>(static_cast<uint64_t>(vregs[in.a])
                                               << (vregs[in.b] & 63));
          break;
        case Op::SRA: vregs[in.dst] = vregs[in.a] >> (vregs[in.b] & 63); break;
        case Op::SLT: vregs[in.dst] = (vregs[in.a] < vregs[in.b]) ? 1 : 0; break;
        case Op::EQZ: vregs[in.dst] = (vregs[in.a] == 0) ? 1 : 0; break;
        case Op::LABEL: break;
        case Op::JUMP: {
          auto it = labels.find(in.label);
          if (it == labels.end()) throw std::runtime_error("ir_interpreter: unknown label");
          pc = it->second;
          break;
        }
        case Op::BRANCH_ZERO: {
          if (vregs[in.a] == 0) {
            auto it = labels.find(in.label);
            if (it == labels.end()) throw std::runtime_error("ir_interpreter: unknown label");
            pc = it->second;
          }
          break;
        }
        case Op::CALL: {
          std::vector<int64_t> call_args;
          call_args.reserve(in.args.size());
          for (int vreg : in.args) call_args.push_back(vregs[vreg]);
          vregs[in.dst] = run(in.callee, call_args);
          break;
        }
        case Op::RETURN: return vregs[in.a];
        case Op::ALLOC: {
          int64_t addr = heap_next;
          heap_next += (in.imm + 7) & ~int64_t{7};
          if (heap_next > static_cast<int64_t>(kHeapBase + kHeapArena)) {
            throw std::runtime_error("ir_interpreter: heap arena exhausted");
          }
          vregs[in.dst] = addr;
          break;
        }
        case Op::LOAD_MEM: {
          auto it = mem.find(vregs[in.a] + in.imm);
          vregs[in.dst] = (it == mem.end()) ? 0 : it->second;
          break;
        }
        case Op::STORE_MEM: mem[vregs[in.a] + in.imm] = vregs[in.b]; break;
        case Op::LOAD_FUNC_ADDR: vregs[in.dst] = kOracleFuncBase + in.callee * 8; break;
        case Op::CHECKED_ADD:
          vregs[in.dst] = bignums.apply(kHostAdd, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_SUB:
          vregs[in.dst] = bignums.apply(kHostSub, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_MUL:
          vregs[in.dst] = bignums.apply(kHostMul, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_QUOT:
          vregs[in.dst] = bignums.apply(kHostQuot, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_REM:
          vregs[in.dst] = bignums.apply(kHostRem, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_LT:
          vregs[in.dst] = bignums.apply(kHostLt, vregs[in.a], vregs[in.b]);
          break;
        case Op::CHECKED_EQ:
          vregs[in.dst] = bignums.apply(kHostEq, vregs[in.a], vregs[in.b]);
          break;
        case Op::CALL_INDIRECT: {
          int64_t target = vregs[in.a];
          int64_t idx = (target - kOracleFuncBase) / 8;
          if (target < kOracleFuncBase || (target - kOracleFuncBase) % 8 != 0 || idx < 0 ||
              idx >= static_cast<int64_t>(program.functions.size())) {
            throw std::runtime_error("ir_interpreter: indirect call to a non-function value");
          }
          std::vector<int64_t> call_args;
          call_args.reserve(in.args.size());
          for (int vreg : in.args) call_args.push_back(vregs[vreg]);
          vregs[in.dst] = run(static_cast<int>(idx), call_args);
          break;
        }
      }
      pc++;
    }
    throw std::runtime_error("ir_interpreter: fell off end of " + func.name +
                             " without RETURN");
  }
};

}  // namespace

int64_t interpret(const IRProgram& program, int func_index, const std::vector<int64_t>& args,
                  uint64_t max_steps) {
  Interp interp{program, max_steps};
  return interp.run(func_index, args);
}

}  // namespace s7
