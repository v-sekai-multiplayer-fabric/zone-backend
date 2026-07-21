// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 1 backend: raw RV64IM instruction encoders (bit-packing, no
// external assembler -- same technique godot-sandbox-gdscript-compiler's
// riscv_codegen.cpp uses) plus a stack-slot codegen: every vreg lives in
// a stack slot, each IR op loads operands into t0/t1, computes into t2,
// and stores back. Deliberately allocator-free -- correct by
// construction; the reference project's furthest-next-use register
// allocator is a later optimization, not a Stage 1 requirement.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "ir.h"

namespace s7 {

struct CompiledFunction {
  std::string name;
  uint64_t offset = 0;  // byte offset into the code blob
  uint64_t size = 0;
};

struct CompiledProgram {
  std::vector<uint8_t> code;
  std::vector<CompiledFunction> functions;
};

// Compiles every function in the program into one contiguous code blob,
// resolving inter-function calls internally.
CompiledProgram generate_riscv(const IRProgram& program);

}  // namespace s7
