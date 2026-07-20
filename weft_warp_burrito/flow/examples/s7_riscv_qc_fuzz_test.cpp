// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies qc-fuzz.shrub's StdGen/randNat port against hand-computed
// reference values from a plain re-implementation of the exact same
// algorithm (Lean core's Init/Data/Random.lean StdGen + randNat) in
// Python - not against Lean itself (no Lean toolchain in this build),
// but against the same formulas this file's own header comment quotes
// verbatim, computed independently:
//   mk-std-gen(12345) = (12346 1)
//   std-next of that  = 493972152, new gen (494012844 40692)
//   rand-nat(gen, 0, 255) = 183
//   5-trial run (fin-bound=256, num-inst=5, seed=12345):
//     trial 0: size=0  hi=0  w=0
//     trial 1: size=20 hi=20 w=5
//     trial 2: size=40 hi=40 w=11
//     trial 3: size=60 hi=60 w=42
//     trial 4: size=80 hi=80 w=40
#include "s7_riscv_core.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

static std::string readFile(const char* path) {
	std::ifstream stream(path);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

int main() {
	std::string qc = readFile("riscv-guests/shrubbery/qc-fuzz-generated.scm");
	if (qc.empty()) {
		fprintf(stderr, "could not read qc-fuzz-generated.scm\n");
		_exit(1);
	}

	const std::string setup = R"(
	    (define gen0 (qc-mk-std-gen 12345))
	    (define next-result (qc-std-next gen0))
	    (define next-z (car next-result))
	    (define rand-result (qc-rand-nat gen0 0 255))
	    (define rand-v (car rand-result))
	    (define trial-w (list))
	    (define trial-gen gen0)
	    (do ((i 0 (+ i 1))) ((= i 5))
	      (let* ((size-i (quotient (* i 100) 5))
	             (hi-i (min size-i 255))
	             (sample (qc-rand-nat trial-gen 0 hi-i)))
	        (set! trial-w (cons (car sample) trial-w))
	        (set! trial-gen (cadr sample))))
	    (set! trial-w (reverse trial-w))
	)";

	const std::string expr =
		"(begin " + qc + setup +
		R"( (+ (if (equal? (car gen0) 12346) 10000000 0)
		        (if (equal? (cadr gen0) 1) 1000000 0)
		        (if (equal? next-z 493972152) 100000 0)
		        (if (equal? rand-v 183) 10000 0)
		        (if (equal? trial-w (list 0 5 11 42 40)) 1000 0))))";

	constexpr int64_t kExpected = 11111000;  // 10000000+1000000+100000+10000+1000
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<20'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: qc-fuzz.shrub's StdGen/randNat matches the reference algorithm exactly\n");
	fflush(stdout);
	_exit(0);
}
