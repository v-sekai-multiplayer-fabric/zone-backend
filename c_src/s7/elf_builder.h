// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Hand-rolled RISC-V ELF64 executable byte-layout, same no-external-
// `as`/`ld` technique godot-sandbox-gdscript-compiler's elf_builder.cpp
// uses. Produces exactly one PT_LOAD segment (R+X) plus a .symtab/.strtab
// pair so libriscv's `machine.memory.resolve_address(name)` can find
// every compiled function by name.
#pragma once
#include <cstdint>
#include <vector>

#include "riscv_codegen.h"

namespace s7 {

constexpr uint64_t kBaseAddr = 0x10000;

// Builds a minimal ET_EXEC RISC-V64 ELF containing `program.code` as the
// entire .text section, exporting every function as a global FUNC symbol.
std::vector<uint8_t> build_elf(const CompiledProgram& program);

}  // namespace s7
