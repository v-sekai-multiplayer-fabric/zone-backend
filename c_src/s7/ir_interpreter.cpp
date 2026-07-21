// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "ir_interpreter.h"

#include <stdexcept>
#include <unordered_map>

namespace s7 {

namespace {

struct Interp {
  const IRProgram& program;
  uint64_t steps_left;

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
