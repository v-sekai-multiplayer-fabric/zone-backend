// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "compiler.h"

#include "elf_builder.h"
#include "ir.h"
#include "riscv_codegen.h"

namespace lisp1 {

std::vector<uint8_t> compile_stage0(const std::string& func_name) {
  // (+ 1 2), hand-built IR -- Stage 1 replaces this with a real reader.
  IRFunction func;
  func.name = func_name;
  func.num_vregs = 3;
  func.instrs = {
      {Op::LOAD_IMM, /*dst=*/0, -1, -1, /*imm=*/1},
      {Op::LOAD_IMM, /*dst=*/1, -1, -1, /*imm=*/2},
      {Op::ADD, /*dst=*/2, /*a=*/0, /*b=*/1, 0},
      {Op::RETURN, -1, /*a=*/2, -1, 0},
  };

  std::vector<uint8_t> code = generate_riscv(func);
  return build_elf(code, func_name);
}

}  // namespace lisp1
