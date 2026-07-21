// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 0: hand-rolled RISC-V ELF64 executable byte-layout, same
// no-external-`as`/`ld` technique godot-sandbox-gdscript-compiler's
// elf_builder.cpp uses. Produces exactly one PT_LOAD segment (R+X) plus
// a .symtab/.strtab pair so libriscv's `machine.memory.resolve_address(name)`
// can find the compiled function by name.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace s7 {

constexpr uint64_t kBaseAddr = 0x10000;

// Builds a minimal ET_EXEC RISC-V64 ELF containing `code` as the entire
// .text section, exported as one global FUNC symbol named `func_name`.
std::vector<uint8_t> build_elf(const std::vector<uint8_t>& code, const std::string& func_name);

}  // namespace s7
