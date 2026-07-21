// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Reference host-side implementation of the checked-arithmetic host-call
// ABI (RFD 0018): bignums are host-owned handles, computed here with
// __int128 and demoted back to fixnums when they fit 61 bits. Used by
// the IR interpreter oracle and the standalone C++ verify harness; the
// production BEAM/NIF trampoline implements the same ABI with Elixir's
// native arbitrary-precision integers instead (this reference is
// therefore capped at 128 bits -- wide enough for every test vector,
// documented, and not shipped as the production math).
#pragma once
#include <cstdint>
#include <stdexcept>
#include <vector>

#include "value.h"

namespace s7 {

// 128-bit divmod without compiler-rt libcalls (__divti3/__modti3 are
// missing on MSVC-target clang): plain shift-subtract long division.
// Truncating semantics, remainder takes the dividend's sign -- matching
// C, RISC-V div/rem, and Scheme quotient/remainder.
inline void divmod_i128(__int128 a, __int128 b, __int128& q, __int128& r) {
  bool neg_q = (a < 0) != (b < 0);
  bool neg_r = a < 0;
  unsigned __int128 ua =
      a < 0 ? ~static_cast<unsigned __int128>(a) + 1 : static_cast<unsigned __int128>(a);
  unsigned __int128 ub =
      b < 0 ? ~static_cast<unsigned __int128>(b) + 1 : static_cast<unsigned __int128>(b);
  unsigned __int128 uq = 0, ur = 0;
  for (int i = 127; i >= 0; --i) {
    ur = (ur << 1) | ((ua >> i) & 1);
    if (ur >= ub) {
      ur -= ub;
      uq |= static_cast<unsigned __int128>(1) << i;
    }
  }
  q = neg_q ? -static_cast<__int128>(uq) : static_cast<__int128>(uq);
  r = neg_r ? -static_cast<__int128>(ur) : static_cast<__int128>(ur);
}

struct HostBignumTable {
  std::vector<__int128> values;

  __int128 unbox(int64_t tagged) {
    if ((tagged & 7) == 0) return static_cast<__int128>(tagged >> 3);
    if ((tagged & 7) == kHandleTag) {
      int64_t idx = tagged >> 3;
      if (idx < 0 || idx >= static_cast<int64_t>(values.size())) {
        throw std::runtime_error("host_math: bad bignum handle");
      }
      return values[static_cast<size_t>(idx)];
    }
    throw std::runtime_error("host_math: arithmetic on a non-number");
  }

  int64_t box(__int128 v) {
    if (v >= static_cast<__int128>(kFixnumMin) && v <= static_cast<__int128>(kFixnumMax)) {
      return static_cast<int64_t>(v) << 3;  // demote to fixnum
    }
    values.push_back(v);
    int64_t idx = static_cast<int64_t>(values.size()) - 1;
    return (idx << 3) | kHandleTag;
  }

  int64_t apply(int64_t op, int64_t a_tagged, int64_t b_tagged) {
    __int128 a = unbox(a_tagged);
    __int128 b = unbox(b_tagged);
    switch (op) {
      case kHostAdd: return box(a + b);
      case kHostSub: return box(a - b);
      case kHostMul: return box(a * b);
      case kHostQuot: {
        if (b == 0) throw std::runtime_error("host_math: division by zero");
        __int128 q, r;
        divmod_i128(a, b, q, r);
        return box(q);
      }
      case kHostRem: {
        if (b == 0) throw std::runtime_error("host_math: remainder by zero");
        __int128 q, r;
        divmod_i128(a, b, q, r);
        return box(r);
      }
      case kHostLt: return (a < b) ? 1 : 0;
      case kHostEq: return (a == b) ? 1 : 0;
      default: throw std::runtime_error("host_math: unknown op");
    }
  }
};

}  // namespace s7
