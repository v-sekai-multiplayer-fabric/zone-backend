// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "compiler.h"

#include "codegen.h"
#include "elf_builder.h"
#include "reader.h"
#include "riscv_codegen.h"

namespace s7 {

Compiled compile(const std::string& source) {
  Compiled result;
  result.ir = lower(read_all(source));
  result.elf = build_elf(generate_riscv(result.ir));
  return result;
}

}  // namespace s7
