// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies qc-fuzz.shrub + taskweft-witnessdag.shrub against three
// hand-traced escalation paths (deliberately using always-true/
// always-false predicates so the outcome doesn't depend on which
// values qc-fuzz's real Plausible-derived StdGen stream actually
// samples - only the escalation control flow is under test here, not
// qc-fuzz's own sampling distribution, which s7_riscv_qc_fuzz_test.cpp
// verifies separately against a hand-computed reference):
//   r1: always-true candidate -> resolves at rung 0 as provablyNone
//       (every sampled w "is a witness", so qc-certify finds one on
//       its first sample; certifyWitness's own priority order treats
//       that as outcome=provablyNone, bool=#f).
//   r2: always-false candidate, default (never-found) readback ->
//       exhausts all 3 rungs, budgetHit at the last one (idx=2),
//       bool=#t.
//   r3: always-false candidate, but a readback stub that reports
//       found=#t immediately -> short-circuits at rung 0 regardless of
//       the candidate predicate, bool=#t, outcome=(found 42).
// Plus a determinism check: the same seed fed to qc-certify twice must
// produce the same result (the property this whole tier depends on,
// same as every other RNG-touching piece of content here).
#include "s7_riscv_core.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

static std::string readFile(const char* path) {
	std::ifstream stream(path);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

int main() {
	std::string macros = readFile("riscv-guests/content/record-macros.scm");
	std::string qc = readFile("riscv-guests/shrubbery/qc-fuzz-generated.scm");
	std::string wd = readFile("riscv-guests/shrubbery/taskweft-witnessdag-generated.scm");
	if (macros.empty() || qc.empty() || wd.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string setup =
		R"( (define always-true (lambda (lvl w) #t))
		    (define always-false (lambda (lvl w) #f))
		    (define found-readback (lambda (steps) (make-readback (list) #t 42 #f)))
		    (define always-true-1 (lambda (w) #t))
		    (define r1 (certify-witness always-true default-readback (default-ladder) 12345))
		    (define r2 (certify-witness always-false default-readback (default-ladder) 67890))
		    (define r3 (certify-witness always-false found-readback (default-ladder) 111))
		    (define r3-outcome (caddr (caddr r3)))
		    (define det-a (qc-certify always-true-1 256 200 999))
		    (define det-b (qc-certify always-true-1 256 200 999)) )";

	const std::string expr =
		"(begin " + macros + qc + wd + setup +
		R"( (+ (if (equal? (car r1) #f) 1000000 0)
		        (if (equal? (cadr r1) 0) 100000 0)
		        (if (equal? (car r2) #t) 10000 0)
		        (if (equal? (cadr r2) 2) 1000 0)
		        (if (equal? (car r3) #t) 100 0)
		        (if (equal? (cadr r3) 0) 10 0)
		        (if (equal? (car r3-outcome) 'found) 1 0)
		        (if (equal? det-a det-b) 10000000 0))))";

	constexpr int64_t kExpected = 11111111;  // 10000000+1000000+100000+10000+1000+100+10+1
	s7RiscvInitialize();
	int64_t result;
	try {
		result = s7RiscvEvalInt<200'000'000ull>(expr);
	} catch (const std::exception& e) {
		fprintf(stderr, "EXCEPTION: %s\n", e.what());
		_exit(1);
	}
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: qc-fuzz.shrub + taskweft-witnessdag.shrub verified (provablyNone/budgetHit/found escalation, determinism)\n");
	fflush(stdout);
	_exit(0);
}
