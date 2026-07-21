// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "riscv_codegen.h"

#include <stdexcept>
#include <unordered_map>

namespace s7 {

namespace {

// Physical registers used by the stack-slot scheme.
constexpr uint32_t kZero = 0;   // x0
constexpr uint32_t kRa = 1;     // x1
constexpr uint32_t kSp = 2;     // x2
constexpr uint32_t kT0 = 5;     // x5
constexpr uint32_t kT1 = 6;     // x6
constexpr uint32_t kT2 = 7;     // x7
constexpr uint32_t kA0 = 10;    // x10

// --- Raw RV64 instruction encoders (bit-packing, no external assembler) ---

uint32_t r_type(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd,
                uint32_t opcode) {
  return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}

uint32_t i_type(int32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
  return (static_cast<uint32_t>(imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) |
         opcode;
}

uint32_t s_type(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode) {
  uint32_t uimm = static_cast<uint32_t>(imm & 0xFFF);
  return ((uimm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((uimm & 0x1F) << 7) |
         opcode;
}

uint32_t b_type(int32_t offset, uint32_t rs2, uint32_t rs1, uint32_t funct3) {
  uint32_t u = static_cast<uint32_t>(offset);
  return (((u >> 12) & 1) << 31) | (((u >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) |
         (funct3 << 12) | (((u >> 1) & 0xF) << 8) | (((u >> 11) & 1) << 7) | 0b1100011;
}

uint32_t j_type(int32_t offset, uint32_t rd) {
  uint32_t u = static_cast<uint32_t>(offset);
  return (((u >> 20) & 1) << 31) | (((u >> 1) & 0x3FF) << 21) | (((u >> 11) & 1) << 20) |
         (((u >> 12) & 0xFF) << 12) | (rd << 7) | 0b1101111;
}

uint32_t enc_addi(uint32_t rd, uint32_t rs1, int32_t imm) { return i_type(imm, rs1, 0b000, rd, 0b0010011); }
uint32_t enc_sltiu(uint32_t rd, uint32_t rs1, int32_t imm) { return i_type(imm, rs1, 0b011, rd, 0b0010011); }
uint32_t enc_slli(uint32_t rd, uint32_t rs1, uint32_t shamt) {
  return (0b000000u << 26) | (shamt << 20) | (rs1 << 15) | (0b001u << 12) | (rd << 7) | 0b0010011;
}
uint32_t enc_ld(uint32_t rd, uint32_t rs1, int32_t imm) { return i_type(imm, rs1, 0b011, rd, 0b0000011); }
uint32_t enc_sd(uint32_t rs2, uint32_t rs1, int32_t imm) { return s_type(imm, rs2, rs1, 0b011, 0b0100011); }
uint32_t enc_jalr(uint32_t rd, uint32_t rs1, int32_t imm) { return i_type(imm, rs1, 0b000, rd, 0b1100111); }

uint32_t enc_add(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b000, rd, 0b0110011); }
uint32_t enc_sub(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0100000, b, a, 0b000, rd, 0b0110011); }
uint32_t enc_mul(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000001, b, a, 0b000, rd, 0b0110011); }
uint32_t enc_div(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000001, b, a, 0b100, rd, 0b0110011); }
uint32_t enc_rem(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000001, b, a, 0b110, rd, 0b0110011); }
uint32_t enc_and(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b111, rd, 0b0110011); }
uint32_t enc_or(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b110, rd, 0b0110011); }
uint32_t enc_xor(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b100, rd, 0b0110011); }
uint32_t enc_sll(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b001, rd, 0b0110011); }
uint32_t enc_sra(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0100000, b, a, 0b101, rd, 0b0110011); }
uint32_t enc_slt(uint32_t rd, uint32_t a, uint32_t b) { return r_type(0b0000000, b, a, 0b010, rd, 0b0110011); }
uint32_t enc_bne(uint32_t a, uint32_t b, int32_t off) { return b_type(off, b, a, 0b001); }

struct Emitter {
  std::vector<uint8_t>& code;

  size_t offset() const { return code.size(); }

  void u32(uint32_t word) {
    code.push_back(static_cast<uint8_t>(word & 0xFF));
    code.push_back(static_cast<uint8_t>((word >> 8) & 0xFF));
    code.push_back(static_cast<uint8_t>((word >> 16) & 0xFF));
    code.push_back(static_cast<uint8_t>((word >> 24) & 0xFF));
  }

  void patch_u32(size_t at, uint32_t word) {
    code[at] = static_cast<uint8_t>(word & 0xFF);
    code[at + 1] = static_cast<uint8_t>((word >> 8) & 0xFF);
    code[at + 2] = static_cast<uint8_t>((word >> 16) & 0xFF);
    code[at + 3] = static_cast<uint8_t>((word >> 24) & 0xFF);
  }

  // Materialize an arbitrary 64-bit constant. Standard recursive scheme:
  // peel off a sign-extended low 12 bits, build the rest, shift, add.
  void li(uint32_t rd, int64_t imm) {
    if (imm >= -2048 && imm <= 2047) {
      u32(enc_addi(rd, kZero, static_cast<int32_t>(imm)));
      return;
    }
    int64_t lo = ((imm & 0xFFF) ^ 0x800) - 0x800;
    int64_t hi = (imm - lo) >> 12;
    li(rd, hi);
    u32(enc_slli(rd, rd, 12));
    if (lo != 0) u32(enc_addi(rd, rd, static_cast<int32_t>(lo)));
  }
};

// Stack-slot codegen state per function. Frame layout:
//   [sp + i*8]           vreg i
//   [sp + frame - 8]     saved ra
// Slot offsets use 12-bit ld/sd immediates, capping functions at ~250
// vregs -- plenty for Stage 1, revisit alongside the register allocator.
struct FnEmit {
  Emitter& em;
  const IRFunction& func;
  int32_t frame;

  std::unordered_map<int, size_t> label_offsets;
  std::vector<std::pair<size_t, int>> branch_fixups;  // (jal offset, label)

  static int32_t frame_size(const IRFunction& f) {
    int32_t raw = f.num_vregs * 8 + 8;
    return (raw + 15) & ~15;
  }

  int32_t slot(int vreg) const {
    int32_t off = vreg * 8;
    if (off > 2047 - 8) throw std::runtime_error("riscv_codegen: function too large (vreg slots)");
    return off;
  }

  void load(uint32_t rd, int vreg) { em.u32(enc_ld(rd, kSp, slot(vreg))); }
  void store(uint32_t rs, int vreg) { em.u32(enc_sd(rs, kSp, slot(vreg))); }

  // Branches are emitted as an inverted-condition skip over a jal, so
  // every control transfer gets jal's +-1MB range instead of b-type's
  // +-4KB (the verbose stack-slot expansion makes 4KB easy to exceed).
  void emit_jump_to_label(int label) {
    branch_fixups.emplace_back(em.offset(), label);
    em.u32(j_type(0, kZero));  // patched later
  }
};

}  // namespace

CompiledProgram generate_riscv(const IRProgram& program) {
  CompiledProgram out;
  Emitter em{out.code};

  // (call-site offset, callee function index) for cross-function jal patching.
  std::vector<std::pair<size_t, int>> call_fixups;

  for (const IRFunction& func : program.functions) {
    if (func.num_params > 8) {
      throw std::runtime_error("riscv_codegen: more than 8 parameters not supported");
    }

    CompiledFunction meta;
    meta.name = func.name;
    meta.offset = em.offset();

    FnEmit fe{em, func, FnEmit::frame_size(func)};
    if (fe.frame > 2047) throw std::runtime_error("riscv_codegen: frame too large");

    // Prologue.
    em.u32(enc_addi(kSp, kSp, -fe.frame));
    em.u32(enc_sd(kRa, kSp, fe.frame - 8));
    for (int p = 0; p < func.num_params; ++p) fe.store(kA0 + static_cast<uint32_t>(p), p);

    for (const Instr& in : func.instrs) {
      switch (in.op) {
        case Op::LOAD_IMM:
          em.li(kT2, in.imm);
          fe.store(kT2, in.dst);
          break;
        case Op::MOVE:
          fe.load(kT0, in.a);
          fe.store(kT0, in.dst);
          break;
        case Op::ADD:
        case Op::SUB:
        case Op::MUL:
        case Op::DIV:
        case Op::REM:
        case Op::AND:
        case Op::OR:
        case Op::XOR:
        case Op::SLL:
        case Op::SRA:
        case Op::SLT: {
          fe.load(kT0, in.a);
          fe.load(kT1, in.b);
          switch (in.op) {
            case Op::ADD: em.u32(enc_add(kT2, kT0, kT1)); break;
            case Op::SUB: em.u32(enc_sub(kT2, kT0, kT1)); break;
            case Op::MUL: em.u32(enc_mul(kT2, kT0, kT1)); break;
            case Op::DIV: em.u32(enc_div(kT2, kT0, kT1)); break;
            case Op::REM: em.u32(enc_rem(kT2, kT0, kT1)); break;
            case Op::AND: em.u32(enc_and(kT2, kT0, kT1)); break;
            case Op::OR: em.u32(enc_or(kT2, kT0, kT1)); break;
            case Op::XOR: em.u32(enc_xor(kT2, kT0, kT1)); break;
            case Op::SLL: em.u32(enc_sll(kT2, kT0, kT1)); break;
            case Op::SRA: em.u32(enc_sra(kT2, kT0, kT1)); break;
            case Op::SLT: em.u32(enc_slt(kT2, kT0, kT1)); break;
            default: break;
          }
          fe.store(kT2, in.dst);
          break;
        }
        case Op::EQZ:
          fe.load(kT0, in.a);
          em.u32(enc_sltiu(kT2, kT0, 1));
          fe.store(kT2, in.dst);
          break;
        case Op::LABEL:
          fe.label_offsets[in.label] = em.offset();
          break;
        case Op::JUMP:
          fe.emit_jump_to_label(in.label);
          break;
        case Op::BRANCH_ZERO:
          fe.load(kT0, in.a);
          em.u32(enc_bne(kT0, kZero, 8));  // skip the jal when nonzero
          fe.emit_jump_to_label(in.label);
          break;
        case Op::CALL: {
          if (in.args.size() > 8) {
            throw std::runtime_error("riscv_codegen: more than 8 call arguments");
          }
          for (size_t i = 0; i < in.args.size(); ++i) {
            fe.load(kA0 + static_cast<uint32_t>(i), in.args[i]);
          }
          call_fixups.emplace_back(em.offset(), in.callee);
          em.u32(j_type(0, kRa));  // jal ra, callee -- patched later
          fe.store(kA0, in.dst);
          break;
        }
        case Op::RETURN:
          fe.load(kA0, in.a);
          em.u32(enc_ld(kRa, kSp, fe.frame - 8));
          em.u32(enc_addi(kSp, kSp, fe.frame));
          em.u32(enc_jalr(kZero, kRa, 0));
          break;
      }
    }

    // Patch intra-function label jumps.
    for (auto& [at, label] : fe.branch_fixups) {
      auto it = fe.label_offsets.find(label);
      if (it == fe.label_offsets.end()) {
        throw std::runtime_error("riscv_codegen: unresolved label in " + func.name);
      }
      int64_t rel = static_cast<int64_t>(it->second) - static_cast<int64_t>(at);
      if (rel < -(1 << 20) || rel >= (1 << 20)) {
        throw std::runtime_error("riscv_codegen: jump out of jal range in " + func.name);
      }
      em.patch_u32(at, j_type(static_cast<int32_t>(rel), kZero));
    }

    meta.size = em.offset() - meta.offset;
    out.functions.push_back(std::move(meta));
  }

  // Patch cross-function calls.
  for (auto& [at, callee] : call_fixups) {
    int64_t rel = static_cast<int64_t>(out.functions[static_cast<size_t>(callee)].offset) -
                  static_cast<int64_t>(at);
    if (rel < -(1 << 20) || rel >= (1 << 20)) {
      throw std::runtime_error("riscv_codegen: call out of jal range");
    }
    em.patch_u32(at, j_type(static_cast<int32_t>(rel), kRa));
  }

  return out;
}

}  // namespace s7
