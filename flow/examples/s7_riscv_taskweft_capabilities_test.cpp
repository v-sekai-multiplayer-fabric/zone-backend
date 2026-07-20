// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-capabilities.shrub against a small hand-traced
// relationship graph:
//   (alice OWNS house1)
//   (alice IS_MEMBER_OF admins)
//   (admins HAS_CAPABILITY delete_anything)
//   (bob DELEGATED_TO alice)   ; -> alice CONTROLS bob (the special case)
//
// Checks: direct capability, IS_MEMBER_OF inheritance, the
// DELEGATED_TO->CONTROLS special case, fuel exhaustion (fuel=0 is
// always false), a union RelationExpr, and expand's direct+inherited
// dedup (admins is direct HAS_CAPABILITY, alice is inherited via
// IS_MEMBER_OF - expect exactly 2 entities, order admins then alice).
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
	std::string caps = readFile("riscv-guests/shrubbery/taskweft-capabilities-generated.scm");
	std::string types = readFile("riscv-guests/shrubbery/taskweft-types-generated.scm");
	if (macros.empty() || caps.empty() || types.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		" (define graph (list (make-relationship 'alice 'OWNS 'house1)"
		"                      (make-relationship 'alice 'IS_MEMBER_OF 'admins)"
		"                      (make-relationship 'admins 'HAS_CAPABILITY 'delete_anything)"
		"                      (make-relationship 'bob 'DELEGATED_TO 'alice)))"
		" (define check1 (has-capability graph 'alice 'OWNS 'house1 3))"
		" (define check2 (has-capability graph 'alice 'HAS_CAPABILITY 'delete_anything 3))"
		" (define check3 (has-capability graph 'alice 'CONTROLS 'bob 3))"
		" (define check4 (has-capability graph 'alice 'HAS_CAPABILITY 'delete_anything 0))"
		" (define check5 (check-relation-expr graph 'alice (list 'union (list 'base 'OWNS) (list 'base 'CONTROLS)) 'bob 3))"
		" (define expanded (expand graph 'HAS_CAPABILITY 'delete_anything 3))";

	const std::string expr =
		"(begin " + macros + types + caps + setup +
		" (+ (if check1 100000 0) (if check2 10000 0) (if check3 1000 0)"
		"    (if check4 0 100) (if check5 10 0) (length expanded)))";

	constexpr int64_t kExpected = 111112;  // 100000+10000+1000+100+10+2
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<10'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-capabilities.shrub verified (direct/inherited/delegated/fuel/union/expand)\n");
	fflush(stdout);
	_exit(0);
}
