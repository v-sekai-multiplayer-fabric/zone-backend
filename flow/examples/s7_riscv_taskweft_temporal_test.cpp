// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-temporal.shrub against a hand-traced STN
// (schedule/timeline of PlanIDs): stn = (10 20 30) - 10 occurs before
// 20 occurs before 30. metas: ((10 0 5) (20 5 12) (30 12 20)).
//
//   (after 20 10)  -> occursBefore(10, 20) -> true (10 before 20)
//   (before 20 30) -> occursBefore(20, 30) -> true
//   (between 20 10 30) -> occursBefore(10,20) && occursBefore(20,30) -> true
//   (within 20 15) -> meta for 20 has end=12, 12<=15 -> true
//   (within 20 10) -> end=12, 12<=10 -> false
//   (after 10 20)  -> occursBefore(20, 10) -> false (20 is NOT before 10)
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
	std::string temporal = readFile("riscv-guests/shrubbery/taskweft-temporal-generated.scm");
	if (temporal.empty()) {
		fprintf(stderr, "could not read taskweft-temporal-generated.scm\n");
		_exit(1);
	}

	const std::string setup =
		" (define stn (list 10 20 30))"
		" (define metas (list (list 10 0 5) (list 20 5 12) (list 30 12 20)))"
		" (define c1 (list 'after 20 10))"
		" (define c2 (list 'before 20 30))"
		" (define c3 (list 'between 20 10 30))"
		" (define c4 (list 'within 20 15))"
		" (define c5 (list 'within 20 10))"
		" (define c6 (list 'after 10 20))"
		" (define all-good (all-constraints-satisfied stn metas (list c1 c2 c3 c4)))";

	const std::string expr =
		"(begin " + temporal + setup +
		" (+ (if (temporal-constraint-valid stn metas c1) 100000 0)"
		"    (if (temporal-constraint-valid stn metas c2) 10000 0)"
		"    (if (temporal-constraint-valid stn metas c3) 1000 0)"
		"    (if (temporal-constraint-valid stn metas c4) 100 0)"
		"    (if (temporal-constraint-valid stn metas c5) 10 0)"
		"    (if (temporal-constraint-valid stn metas c6) 1 0)"
		"    (if all-good 1000000 0)))";

	constexpr int64_t kExpected = 1111100;  // 1000000+100000+10000+1000+100+0+0
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<10'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-temporal.shrub verified (after/before/between/within all correct)\n");
	fflush(stdout);
	_exit(0);
}
