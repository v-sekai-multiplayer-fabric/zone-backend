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

// Runs `program.functions[func_index]` with the given (already tagged)
// argument words. Throws std::runtime_error on malformed IR, division
// by zero, or exceeding the step budget (runaway-loop guard).
int64_t interpret(const IRProgram& program, int func_index, const std::vector<int64_t>& args,
                  uint64_t max_steps = 50'000'000);

}  // namespace s7
