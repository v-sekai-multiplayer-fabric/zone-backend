// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Top-level pipeline (same 5-stage shape as the reference compiler,
// with the s-expression reader replacing lexer+parser):
//   read_all -> lower (s-exprs -> IR) -> [optimizer: identity for now]
//   -> generate_riscv -> build_elf
// The IRProgram is exposed alongside the ELF so callers can run the IR
// interpreter as an independent correctness oracle against the same
// lowering that produced the machine code.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "ir.h"

namespace s7 {

struct Compiled {
  IRProgram ir;
  std::vector<uint8_t> elf;
};

// Compiles s7-subset Scheme source (top-level defines) to a RISC-V ELF.
// Throws std::runtime_error with a stage-prefixed message on any error.
Compiled compile(const std::string& source);

}  // namespace s7
