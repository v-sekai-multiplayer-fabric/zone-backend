// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 0 top-level entry point: hardcoded `(+ 1 2)` program, no reader/
// parser yet (that's Stage 1). Proves the ir -> riscv_codegen -> elf_builder
// pipeline shape end to end.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace s7 {

// Compiles the fixed Stage-0 program `(+ 1 2)` to a RISC-V ELF exposing
// one function, `func_name`, taking no arguments and returning 3 in a0.
std::vector<uint8_t> compile_stage0(const std::string& func_name);

}  // namespace s7
