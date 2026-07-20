// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-iso8601duration.shrub against Iso8601Duration.lean's
// own 12 `#eval parse "..."` worked examples - real Lean-computed
// reference outputs already in the source, used as golden vectors the
// same way FloydWarshall's own proven theorems were (ADR 0039), not a
// freshly-computed reference.
//
// Each check is one bit in the result; all 12 must pass for the
// expected sum (4095 = 2^12 - 1).
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
	std::string macros = readFile("riscv-guests/content/record-macros.scm");
	std::string iso = readFile("riscv-guests/shrubbery/taskweft-iso8601duration-generated.scm");
	if (macros.empty() || iso.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	// Each `bN` is 0/1 for one doctest, matching Iso8601Duration.lean's
	// own 12 #eval lines in order.
	const std::string checks =
		" (define b0 (let ((r (parse \"P15Y3M2DT1H14M37S\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 6)) 1 0)))"
		" (define b1 (let ((r (parse \"P15Y3M2D\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 3)) 1 0)))"
		" (define b2 (let ((r (parse \"PT3H12M25.001S\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 3) (= (dur-component-frac-milli (caddr (cadr r))) 1)) 1 0)))"
		" (define b3 (let ((r (parse \"P2W\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 1) (equal? (dur-component-unit (car (cadr r))) 'W) (= (dur-component-whole (car (cadr r))) 2)) 1 0)))"
		" (define b4 (let ((r (parse \"P\"))) (if (and (equal? (car r) 'ok) (null? (cadr r))) 1 0)))"
		" (define b5 (let ((r (parse \"P15YT3D\"))) (if (equal? r (list 'error 'dateAfterT)) 1 0)))"
		" (define b6 (let ((r (parse \"\"))) (if (equal? r (list 'error 'empty)) 1 0)))"
		" (define b7 (let ((r (parse \"X1D\"))) (if (equal? r (list 'error 'expectedP)) 1 0)))"
		" (define b8 (let ((r (parse \"P1.5D\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 1) (equal? (dur-component-unit (car (cadr r))) 'D) (= (dur-component-whole (car (cadr r))) 1) (= (dur-component-frac-milli (car (cadr r))) 500)) 1 0)))"
		" (define b9 (let ((r (parse \"PT1.5H\"))) (if (and (equal? (car r) 'ok) (= (length (cadr r)) 1) (equal? (dur-component-unit (car (cadr r))) 'H) (= (dur-component-whole (car (cadr r))) 1) (= (dur-component-frac-milli (car (cadr r))) 500)) 1 0)))"
		" (define b10 (let ((r (parse \"PT1.5H30M\"))) (if (equal? r (list 'error 'fractionNotOnLast)) 1 0)))"
		" (define b11 (let ((r (parse \"P1D1M\"))) (if (equal? r (list 'error 'nonCanonicalOrder)) 1 0)))";

	const std::string expr =
		"(begin " + macros + iso + checks +
		" (+ b0 (* b1 2) (* b2 4) (* b3 8) (* b4 16) (* b5 32) (* b6 64) (* b7 128) (* b8 256) (* b9 512) (* b10 1024) (* b11 2048)))";

	constexpr int64_t kExpected = 4095;  // all 12 bits set
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<20'000'000ull>(expr);
	printf("result = %lld (expected %lld, binary: which doctests failed shows as 0 bits)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL: missing bits = %lld\n", (long long)(kExpected & ~result));
		_exit(1);
	}
	printf("PASS: all 12 of Iso8601Duration.lean's own worked examples match\n");
	fflush(stdout);
	_exit(0);
}
