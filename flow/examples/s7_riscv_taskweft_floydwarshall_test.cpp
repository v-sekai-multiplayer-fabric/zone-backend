// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-floydwarshall.shrub against FloydWarshall.lean's own
// ALREADY-PROVEN theorems (testNegativeCycleDetected,
// testNegativeCycleNodesCaptured - both `by decide`), not a
// freshly-computed reference: run(1, fun _ _ => -1) has
// has_negative_cycle = true and negative_cycle_nodes = [(0, 0)].
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
	std::string fw = readFile("riscv-guests/shrubbery/taskweft-floydwarshall-generated.scm");
	if (macros.empty() || fw.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		" (define result (fw-run 1 (lambda (i j) -1)))"
		" (define nodes (fw-result-negative-cycle-nodes result))";

	const std::string expr =
		"(begin " + macros + fw + setup +
		" (+ (if (fw-result-has-negative-cycle result) 100 0)"
		"    (* (length nodes) 10)"
		"    (if (equal? (car nodes) (cons 0 0)) 1 0)))";

	constexpr int64_t kExpected = 111;  // 100 + 10 + 1
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<10'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-floydwarshall.shrub matches FloydWarshall.lean's own proven theorems\n");
	fflush(stdout);
	_exit(0);
}
