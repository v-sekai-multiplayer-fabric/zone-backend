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
//
// Scheme truthiness: everything except #f is true.
#pragma once
#include <cstdint>

namespace s7 {

constexpr int64_t kFalse = 0x06;
constexpr int64_t kTrue = 0x0E;
constexpr int64_t kNil = 0x16;

constexpr int64_t tag_fixnum(int64_t v) { return v << 3; }
constexpr int64_t untag_fixnum(int64_t v) { return v >> 3; }
constexpr bool is_fixnum(int64_t v) { return (v & 7) == 0; }
constexpr int64_t tag_bool(bool b) { return b ? kTrue : kFalse; }

}  // namespace s7
