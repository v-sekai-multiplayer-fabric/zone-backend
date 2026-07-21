// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#ifndef FINITE_CHECK_H
#define FINITE_CHECK_H
#include <stdint.h>
#include <string.h>

// Avoids <math.h>'s isnan/isinf -- CBMC's own C parser cannot handle
// this project's mingw math.h (an unrelated GCC-extension syntax
// error, not a determinism concern). Direct IEEE 754 bit inspection
// instead: both NaN and infinity have an all-1s exponent field; NaN
// additionally requires a nonzero mantissa.
static inline int is_nan_or_inf(double d) {
  uint64_t bits;
  memcpy(&bits, &d, sizeof(bits));
  uint64_t exponent = (bits >> 52) & 0x7FFu;
  return exponent == 0x7FFu;
}

#endif
