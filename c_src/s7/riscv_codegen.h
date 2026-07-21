// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 0: raw RV64I instruction encoders (bit-packing, no external
// assembler -- same technique godot-sandbox-gdscript-compiler's
// riscv_codegen.cpp uses) plus a trivial IR-walking codegen. No
// register allocator yet: each vreg gets its own physical register
// (x10+vreg, i.e. a0, a1, a2, ...), valid only because Stage 0's IR
// never has more than a handful of live vregs at once. Stage 1
// reintroduces a real allocator once the IR/codegen need it.
#pragma once
#include <cstdint>
#include <vector>

#include "ir.h"

namespace s7 {

// R-type: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
inline uint32_t encode_r_type(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3,
                               uint32_t rd, uint32_t opcode) {
  return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}

// I-type: imm[31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
inline uint32_t encode_i_type(int32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd,
                               uint32_t opcode) {
  return (static_cast<uint32_t>(imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) |
         opcode;
}

inline uint32_t emit_add(uint32_t rd, uint32_t rs1, uint32_t rs2) {
  return encode_r_type(0b0000000, rs2, rs1, 0b000, rd, 0b0110011);
}

// addi rd, rs1, imm -- also used as `li rd, imm` (rs1=x0) and `mv rd, rs1` (imm=0).
inline uint32_t emit_addi(uint32_t rd, uint32_t rs1, int32_t imm) {
  return encode_i_type(imm, rs1, 0b000, rd, 0b0010011);
}

// jalr x0, ra, 0 == ret
inline uint32_t emit_ret() { return encode_i_type(0, /*rs1=ra*/ 1, 0b000, /*rd=x0*/ 0, 0b1100111); }

// Physical register for vreg i: x10+i (a0, a1, a2, ...). Stage 0 only.
inline uint32_t vreg_to_phys(int vreg) { return 10 + static_cast<uint32_t>(vreg); }

// Compiles one IRFunction to raw RV64 machine code bytes.
std::vector<uint8_t> generate_riscv(const IRFunction& func);

}  // namespace s7
