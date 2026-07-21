// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Sanity-checks softfloat_mini.h against native hardware double
// arithmetic before it's trusted for the cross-platform comparison in
// verify_alt_strategies.cpp -- run with -O0 (see README.md): at -O2,
// a compiler can constant-fold the literal-double "native" expressions
// at compile time using higher-than-double precision, which is not a
// genuine runtime double computation and produced a false mismatch
// here during this RFD's own verification (see docs/decisions/0043-*.md).
#include <stdio.h>
#include "softfloat_mini.h"

static void check_mul(double a, double b) {
  double expect = a * b;
  double got = sf_to_double(soft_mul(sf_from_double(a), sf_from_double(b)));
  const char* ok = (expect == got) ? "OK" : "MISMATCH";
  printf("mul %.10g * %.10g = %.17g (expect %.17g) %s\n", a, b, got, expect, ok);
}
static void check_add(double a, double b) {
  double expect = a + b;
  double got = sf_to_double(soft_add(sf_from_double(a), sf_from_double(b)));
  const char* ok = (expect == got) ? "OK" : "MISMATCH";
  printf("add %.10g + %.10g = %.17g (expect %.17g) %s\n", a, b, got, expect, ok);
}

int main(void) {
  check_mul(2.0, 3.0);
  check_mul(0.1, 0.3);
  check_mul(1.5, -2.5);
  check_mul(1.0e10, 1.0e10);
  check_mul(0.1, 0.11);
  check_mul(1234.5678, 0.0001234);
  check_add(1.0, 2.0);
  check_add(0.1, 0.2);
  check_add(1.0e16, 1.0);
  check_add(1.0e16, -1.0e16);
  check_add(100.0, -99.9999);
  check_add(1.5, 2.5);
  check_add(-1.5, 1.5);
  check_add(0.213, 0.0);

  // Full dot-product comparisons (the actual thing being tested).
  double ax=0.1, ay=0.3, az=0.7, bx=0.11, by=0.37, bz=0.13;
  double native_ref = (ax*bx + ay*by) + az*bz;
  double native_bad = ax*bx + (ay*by + az*bz);
  sf64 sax=sf_from_double(ax), say=sf_from_double(ay), saz=sf_from_double(az);
  sf64 sbx=sf_from_double(bx), sby=sf_from_double(by), sbz=sf_from_double(bz);
  double soft_ref = sf_to_double(soft_dot_ref(sax,say,saz,sbx,sby,sbz));
  double soft_bad = sf_to_double(soft_dot_bad(sax,say,saz,sbx,sby,sbz));
  printf("\ndot_ref native=%.17g soft=%.17g %s\n", native_ref, soft_ref,
         native_ref == soft_ref ? "OK" : "MISMATCH");
  printf("dot_bad native=%.17g soft=%.17g %s\n", native_bad, soft_bad,
         native_bad == soft_bad ? "OK" : "MISMATCH");
  return 0;
}
