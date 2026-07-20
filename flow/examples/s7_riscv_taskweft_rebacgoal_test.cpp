// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-rebacgoal.shrub (uniSatisfied/multiSatisfied)
// against the same relationship graph as the Capabilities test:
//   (alice OWNS house1), (alice IS_MEMBER_OF admins),
//   (admins HAS_CAPABILITY delete_anything), (bob DELEGATED_TO alice)
//
// unigoal1: alice (base OWNS) house1 -> satisfied
// unigoal2: alice (base CONTROLS) house1 -> NOT satisfied (no such edge)
// multigoal (unigoal1 unigoal2) -> NOT satisfied (one goal fails)
// multigoal (unigoal1) alone -> satisfied
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
	std::string caps = readFile("riscv-guests/shrubbery/taskweft-capabilities-generated.scm");
	std::string goal = readFile("riscv-guests/shrubbery/taskweft-rebacgoal-generated.scm");
	if (macros.empty() || types.empty() || caps.empty() || goal.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		" (define graph (list (make-relationship 'alice 'OWNS 'house1)"
		"                      (make-relationship 'alice 'IS_MEMBER_OF 'admins)"
		"                      (make-relationship 'admins 'HAS_CAPABILITY 'delete_anything)"
		"                      (make-relationship 'bob 'DELEGATED_TO 'alice)))"
		" (define g1 (make-uni-goal 'alice (list 'base 'OWNS) 'house1))"
		" (define g2 (make-uni-goal 'alice (list 'base 'CONTROLS) 'house1))"
		" (define check1 (uni-satisfied graph 3 g1))"
		" (define check2 (uni-satisfied graph 3 g2))"
		" (define multi-both (multi-satisfied graph 3 (list g1 g2)))"
		" (define multi-one (multi-satisfied graph 3 (list g1)))";

	const std::string expr =
		"(begin " + macros + types + caps + goal + setup +
		" (+ (if check1 1000 0) (if check2 0 100) (if multi-both 0 10) (if multi-one 1 0)))";

	constexpr int64_t kExpected = 1111;  // 1000 + 100 + 10 + 1
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<10'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-rebacgoal.shrub verified\n");
	fflush(stdout);
	_exit(0);
}
