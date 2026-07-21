// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// The tractable, isolated core of the equivalence claim in
// cbmc_equivalence.c: is (p+q)+r bit-identical to p+(q+r) for IEEE 754
// doubles? Answer: no, in general (addition is commutative but not
// associative), so a "bad" reassociated candidate must NOT verify as
// equivalent, and a "good" same-order candidate must. Isolating just
// the addition (no multiplication) makes this tractable for CBMC's
// default SAT backend in under two minutes, unlike the full 6-variable
// dot product in cbmc_equivalence.c.
//
// Run both directions (see this directory's README.md):
//   cbmc cbmc_associativity.c --gcc --function main
//     -> VERIFICATION SUCCESSFUL (same order, proven equivalent)
//   cbmc cbmc_associativity.c --gcc -DREASSOC_BAD --function main
//     -> finds a counterexample (different association, NOT equivalent)
//     -- in practice this direction did not conclude within a 240s
//     bound during this RFD's own verification; see the RFD for the
//     concrete counterexample found instead via direct testing
//     (1.0, 1.0e16, -1.0e16).
#include <string.h>
#include "finite_check.h"

int main(void) {
  double p = nondet_double();
  double q = nondet_double();
  double r = nondet_double();

  __CPROVER_assume(!is_nan_or_inf(p) && !is_nan_or_inf(q) && !is_nan_or_inf(r));
  __CPROVER_assume(p > -1000.0 && p < 1000.0);
  __CPROVER_assume(q > -1000.0 && q < 1000.0);
  __CPROVER_assume(r > -1000.0 && r < 1000.0);

  double ref = (p + q) + r;
#ifdef REASSOC_BAD
  double candidate = p + (q + r);
#else
  double t = p + q;
  double candidate = t + r;
#endif

  __CPROVER_assert(memcmp(&ref, &candidate, sizeof(double)) == 0,
                    "candidate must be bit-identical to ref");
  return 0;
}
