// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 0 skeleton IR, per docs/decisions (Lisp-1 -> RISC-V compiler
// roadmap). Deliberately tiny: enough opcodes to compile `(+ 1 2)` and
// nothing else yet. Stage 1 replaces this with a real vreg-based IR
// (arithmetic/comparison/branch/call/return core, modeled on
// godot-sandbox-gdscript-compiler's ir.h, minus its Variant-specific
// opcodes) plus GuestValue as the value model.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace lisp1 {

enum class Op {
  LOAD_IMM,  // vregs[dst] = imm
  ADD,       // vregs[dst] = vregs[a] + vregs[b]
  RETURN,    // return vregs[a]
};

struct Instr {
  Op op;
  int dst = -1;
  int a = -1;
  int b = -1;
  int64_t imm = 0;
};

struct IRFunction {
  std::string name;
  int num_vregs = 0;
  std::vector<Instr> instrs;
};

}  // namespace lisp1
