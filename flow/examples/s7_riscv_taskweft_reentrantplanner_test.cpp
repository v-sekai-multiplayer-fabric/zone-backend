// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-reentrantplanner.shrub (markVerified/replan)
// against hand-traced expected values: start with verified=(1 2),
// mark-verified 3 -> verified=(1 2 3), length 3. Then replan with a new
// tree symbol 'new-tree-marker and check failure-node cleared (was 'x,
// now #f) and complete-tree updated.
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
	std::string record_macros = readFile("riscv-guests/content/record-macros.scm");
	std::string reentrant = readFile("riscv-guests/shrubbery/taskweft-reentrantplanner-generated.scm");
	if (record_macros.empty() || reentrant.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		" (define st0 (make-plan-solution-tree 'old-tree 'x #f (list 1 2)))"
		" (define st1 (mark-verified st0 3))"
		" (define st2 (replan st1 'new-tree-marker))";

	const std::string expr =
		"(begin " + record_macros + reentrant + setup +
		" (+ (length (plan-solution-tree-verified st1))"
		"    (if (eq? (plan-solution-tree-complete-tree st2) 'new-tree-marker) 10 0)"
		"    (if (eq? (plan-solution-tree-failure-node st2) #f) 100 0)))";

	constexpr int64_t kExpected = 113;  // 3 + 10 + 100
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-reentrantplanner.shrub verified\n");
	fflush(stdout);
	_exit(0);
}
