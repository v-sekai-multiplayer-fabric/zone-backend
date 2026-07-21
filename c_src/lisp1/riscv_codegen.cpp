// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "riscv_codegen.h"

#include <stdexcept>

namespace lisp1 {

namespace {
void push_u32(std::vector<uint8_t>& code, uint32_t word) {
  code.push_back(static_cast<uint8_t>(word & 0xFF));
  code.push_back(static_cast<uint8_t>((word >> 8) & 0xFF));
  code.push_back(static_cast<uint8_t>((word >> 16) & 0xFF));
  code.push_back(static_cast<uint8_t>((word >> 24) & 0xFF));
}
}  // namespace

std::vector<uint8_t> generate_riscv(const IRFunction& func) {
  std::vector<uint8_t> code;

  for (const Instr& instr : func.instrs) {
    switch (instr.op) {
      case Op::LOAD_IMM: {
        if (instr.imm < -2048 || instr.imm > 2047) {
          throw std::runtime_error("Stage 0 codegen: immediate out of 12-bit range");
        }
        push_u32(code, emit_addi(vreg_to_phys(instr.dst), /*x0*/ 0,
                                  static_cast<int32_t>(instr.imm)));
        break;
      }
      case Op::ADD: {
        push_u32(code, emit_add(vreg_to_phys(instr.dst), vreg_to_phys(instr.a),
                                 vreg_to_phys(instr.b)));
        break;
      }
      case Op::RETURN: {
        uint32_t result_reg = vreg_to_phys(instr.a);
        if (result_reg != 10) {
          // mv a0, result_reg
          push_u32(code, emit_addi(/*a0*/ 10, result_reg, 0));
        }
        push_u32(code, emit_ret());
        break;
      }
    }
  }

  return code;
}

}  // namespace lisp1
