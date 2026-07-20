// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies riscv-guests/content/record-macros.scm's define-record and
// record-with macros in isolation, before refactoring combat.scm to use
// them - matching this session's "prove it before building on it"
// discipline, the same reason the shrubbery reader was checked against
// real content before anything depended on it.
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
	if (macros.empty()) {
		fprintf(stderr, "could not read riscv-guests/content/record-macros.scm\n");
		_exit(1);
	}

	// define-record thing (a b c); make one (1 2 3); record-with to change
	// only b to 99; check thing-a=1, thing-b=99, thing-c=3 via (+ a*100 b*10 c) = 1093.
	const std::string expr =
		"(begin " + macros +
		" (define-record thing a b c)"
		" (define t (make-thing 1 2 3))"
		" (define t2 (record-with make-thing '(a b c) t (b 99)))"
		" (+ (* (thing-a t2) 100) (* (thing-b t2) 10) (thing-c t2)))";

	constexpr int64_t kExpected = 1093;  // a=1 -> 100, b=99 -> 990, c=3 -> 3
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL: define-record/record-with produced the wrong value\n");
		_exit(1);
	}
	printf("PASS: define-record + record-with work correctly\n");
	fflush(stdout);
	_exit(0);
}
