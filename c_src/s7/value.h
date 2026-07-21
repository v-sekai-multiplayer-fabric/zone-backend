// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// GuestValue tagged 64-bit representation, per the approved roadmap's
// Stage 1 design. In-register layout inside compiled guest code (and at
// the vmcall boundary):
//
//   low 3 bits 000 -> fixnum, value in upper 61 bits (arithmetic works
//                     directly on tagged values for add/sub since the
//                     tag is zero)
//   low 3 bits 110 -> immediate constants: #f = 0x06, #t = 0x0E,
//                     nil = 0x16
//   low 3 bits 010 -> handle: index into the host-side per-call value
//                     table (Atom/Binary/List/Tuple/Map -- host-owned,
//                     godot-sandbox-style; wired up in a later Stage 1
//                     increment, reserved now so the tag space is fixed)
//   low 3 bits 100 -> closure: 8-aligned guest-heap pointer to
//                     [code_addr, captured values...], created by lambda
//                     (captures are by value; set! on a captured variable
//                     is a compile error in this subset)
//
// Scheme truthiness: everything except #f is true.
#pragma once
#include <cstdint>

namespace s7 {

constexpr int64_t kFalse = 0x06;
constexpr int64_t kTrue = 0x0E;
constexpr int64_t kNil = 0x16;

constexpr int64_t kClosureTag = 0x4;
constexpr int64_t kHandleTag = 0x2;

constexpr int64_t tag_fixnum(int64_t v) { return v << 3; }
constexpr int64_t untag_fixnum(int64_t v) { return v >> 3; }
constexpr bool is_fixnum(int64_t v) { return (v & 7) == 0; }
constexpr int64_t tag_bool(bool b) { return b ? kTrue : kFalse; }

// Fixnum range: 61-bit signed payload.
constexpr int64_t kFixnumMin = -(int64_t{1} << 60);
constexpr int64_t kFixnumMax = (int64_t{1} << 60) - 1;

// Host-call ABI (RFD 0018): checked arithmetic traps to this ecall when
// an operand is not a fixnum or the fixnum result overflows. a7 = the
// syscall number, a0 = op, a1/a2 = tagged operands, result in a0.
// Numbered past godot-sandbox's 500-549 block to avoid collision.
constexpr int64_t kSyscallHostMath = 600;

enum HostMathOp : int64_t {
  kHostAdd = 0,
  kHostSub = 1,
  kHostMul = 2,
  kHostQuot = 3,
  kHostRem = 4,
  kHostLt = 5,   // returns raw 0/1
  kHostEq = 6,   // returns raw 0/1
};

// Guest heap ABI (shared by riscv_codegen, elf_builder, and the IR
// interpreter oracle): a zero-initialized RW segment. The first word is
// the bump-allocation offset (zero at load = empty heap); allocations
// start right after it. No GC, no overflow check yet -- 4MB arena.
constexpr uint64_t kHeapBase = 0x400000;
constexpr uint64_t kHeapArena = 4ull * 1024 * 1024;

}  // namespace s7
