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

  // Handle-value operations (same trampoline, ops 16+): List / Tuple /
  // Map / Binary / Atom values are host-owned (godot-sandbox
  // CurrentState style); the guest holds opaque handles and reaches
  // back through the ecall for every structural operation. Scheme-side
  // naming: vector-* maps to Elixir tuples, hash-table-ref to maps,
  // string-length to binaries. Accessors return tagged GuestValues;
  // predicates return raw 0/1.
  kHostCar = 16,
  kHostCdr = 17,       // cdr of a 1-element list is nil
  kHostCons = 18,      // second operand must be a list or nil
  kHostLength = 19,    // nil counts as the empty list
  kHostListRef = 20,   // (list-ref l i), 0-based, bounds-checked
  kHostIsPair = 21,    // raw 0/1; never throws on non-handles
  kHostTupleRef = 22,  // (vector-ref t i)
  kHostTupleSize = 23, // (vector-length t)
  kHostMapRef = 24,    // (hash-table-ref m k); missing key -> #f, as in s7
  kHostMapSize = 25,
  kHostBinSize = 26,   // (string-length b), in bytes
  kHostStrEq = 27,     // (string=? a b), byte-content compare; raw 0/1

  // (hash-table-set m k v): functional map insert -- Elixir maps are
  // immutable, so "setting" a key produces a NEW map handle rather than
  // mutating in place. `m` may be #f, treated as an empty map (mirrors
  // hash-table-ref's "missing key -> #f" so a two-level nested lookup/
  // update chain never needs a separate "create empty map" primitive).
  // Generic and reusable -- not planner-specific -- the counterpart to
  // kHostMapRef the same way `cons` is to `car`/`cdr`.
  kHostMapSet = 28,
};

// Guest heap ABI (shared by riscv_codegen, elf_builder, and the IR
// interpreter oracle): a zero-initialized RW segment. The first word is
// the bump-allocation offset (zero at load = empty heap); allocations
// start right after it. No GC, no overflow check yet -- 4MB arena.
constexpr uint64_t kHeapBase = 0x400000;
constexpr uint64_t kHeapArena = 4ull * 1024 * 1024;

}  // namespace s7
