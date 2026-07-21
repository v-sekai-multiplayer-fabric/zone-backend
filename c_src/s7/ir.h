// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 1 IR: a linear, virtual-register, RV-flavored ALU instruction
// set (modeled on godot-sandbox-gdscript-compiler's ir.h, minus its
// Variant-specific opcode half). Deliberately machine-shaped and
// value-representation-agnostic: GuestValue tagging (value.h) is
// applied by the *frontend* (codegen.cpp) as explicit shifts/masks, so
// this IR -- and its interpreter oracle -- stay language-independent.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace s7 {

enum class Op {
  LOAD_IMM,     // dst <- imm (any 64-bit constant)
  MOVE,         // dst <- a
  ADD,          // dst <- a + b
  SUB,          // dst <- a - b
  MUL,          // dst <- a * b
  DIV,          // dst <- a / b  (signed, truncating)
  REM,          // dst <- a % b  (signed)
  AND,          // dst <- a & b
  OR,           // dst <- a | b
  XOR,          // dst <- a ^ b
  SLL,          // dst <- a << (b & 63)
  SRA,          // dst <- a >> (b & 63)  (arithmetic)
  SLT,          // dst <- (a < b) ? 1 : 0  (signed)
  EQZ,          // dst <- (a == 0) ? 1 : 0
  LABEL,        // label
  JUMP,         // -> label
  BRANCH_ZERO,  // if a == 0 -> label
  CALL,         // dst <- callee(args...)   callee = IRProgram function index
  RETURN,       // return a

  // Heap + closures (Stage 2):
  ALLOC,           // dst <- bump-allocate imm bytes, returns raw 8-aligned addr
  LOAD_MEM,        // dst <- mem[a + imm]
  STORE_MEM,       // mem[a + imm] <- b
  LOAD_FUNC_ADDR,  // dst <- absolute code address of function `callee`
  CALL_INDIRECT,   // dst <- (*a)(args...)   a holds a code address

  // Checked tagged arithmetic (RFD 0018): operands and results are
  // tagged GuestValues. Fast path is inline fixnum machine arithmetic;
  // a non-fixnum operand or a fixnum overflow traps to the host-math
  // ecall (kSyscallHostMath), which may return a bignum handle.
  CHECKED_ADD,   // dst <- a + b            (tagged in, tagged out)
  CHECKED_SUB,   // dst <- a - b            (tagged in, tagged out)
  CHECKED_MUL,   // dst <- a * b            (tagged in, tagged out)
  CHECKED_QUOT,  // dst <- quotient(a, b)   (tagged in, tagged out)
  CHECKED_REM,   // dst <- remainder(a, b)  (tagged in, tagged out)
  CHECKED_LT,    // dst <- a < b            (tagged in, RAW 0/1 out)
  CHECKED_EQ,    // dst <- a == b (numeric) (tagged in, RAW 0/1 out)

  // Unconditional host call (handle-value ops, HostMathOp 16+): unlike
  // CHECKED_* there is no inline fast path -- the value lives host-side,
  // so every structural operation is an ecall. imm = the HostMathOp.
  HOST_OP,       // dst <- host(imm, a, b)  (tagged in, tagged or raw out per op)
};

struct Instr {
  Op op;
  int dst = -1;
  int a = -1;
  int b = -1;
  int64_t imm = 0;
  int label = -1;
  int callee = -1;
  std::vector<int> args;
};

struct IRFunction {
  std::string name;
  int num_params = 0;  // params are vregs 0..num_params-1
  int num_vregs = 0;
  std::vector<Instr> instrs;
};

struct IRProgram {
  std::vector<IRFunction> functions;

  int find(const std::string& name) const {
    for (size_t i = 0; i < functions.size(); ++i) {
      if (functions[i].name == name) return static_cast<int>(i);
    }
    return -1;
  }
};

}  // namespace s7
