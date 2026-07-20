// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-unifiedgtn.shrub (nodeLifecycleStep/extractPlan)
// against hand-traced expected values.
//
// nodeLifecycleStep: an 'open node becomes 'closed with tag "new";
// anything else is unchanged.
// extractPlan: build a 3-node tree - one 'open (task), one already
// 'new-tagged (task), one 'new-tagged but goal_geq content (should be
// dropped). Step the open one first, then extract - expect exactly 2
// action entries (the two task nodes now tagged "new"), 0 from the
// goal_geq node.
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
	std::string types = readFile("riscv-guests/shrubbery/taskweft-types-generated.scm");
	std::string unified = readFile("riscv-guests/shrubbery/taskweft-unifiedgtn-generated.scm");
	if (macros.empty() || types.empty() || unified.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		" (define n1 (make-solution-node 1 (list 'task \"foo\" '()) 'open \"\" '() 0))"
		" (define n2 (make-solution-node 2 (list 'task \"bar\" '()) 'closed \"new\" '() 0))"
		" (define n3 (make-solution-node 3 (list 'goal_geq 5 10) 'closed \"new\" '() 0))"
		" (define n1-stepped (node-lifecycle-step n1))"
		" (define tree (make-solution-tree (list n1-stepped n2 n3) '()))"
		" (define plan (extract-plan tree))";

	const std::string expr =
		"(begin " + macros + types + unified + setup +
		" (+ (if (equal? (solution-node-status n1-stepped) 'closed) 1000 0)"
		"    (if (equal? (solution-node-tag n1-stepped) \"new\") 100 0)"
		"    (length plan)))";

	constexpr int64_t kExpected = 1102;  // 1000 + 100 + 2
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<10'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-unifiedgtn.shrub verified\n");
	fflush(stdout);
	_exit(0);
}
