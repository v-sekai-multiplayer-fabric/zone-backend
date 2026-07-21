// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Tree-walking IR interpreter -- the fast correctness oracle (same role
// as the reference compiler's ir_interpreter): validates frontend
// lowering independently of the RISC-V encoder, so an encoding bug and
// a lowering bug can never be confused for each other.
#pragma once
#include <cstdint>
#include <vector>

#include "ir.h"

namespace s7 {

struct HostBignumTable;

// Runs `program.functions[func_index]` with the given (already tagged)
// argument words. Throws std::runtime_error on malformed IR, division
// by zero, or exceeding the step budget (runaway-loop guard).
// `table` lets a harness pass handle arguments (List/Tuple/Map/...)
// pre-registered in a shared host-value table; when null, a private
// empty table is used (fixnum-only programs never notice).
int64_t interpret(const IRProgram& program, int func_index, const std::vector<int64_t>& args,
                  uint64_t max_steps = 50'000'000, HostBignumTable* table = nullptr);

}  // namespace s7
