// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-hrr.shrub against the algebraic identity these
// operations exist for: unbind(bind(memory, key), key) recovers memory
// exactly (since bind is +, unbind is -, over integers this always
// holds - no approximation, unlike real circular-convolution HRR).
//
// s7RiscvInitialize() is called exactly once, and every check reuses
// that one warm machine (redefining hrr-bind/memory/key/etc. fresh each
// time, same as every other real-content test in this codebase already
// does). This isn't a style choice: a *cold* interpreter evaluating the
// composed bind-then-unbind round trip (a closure built by applying one
// closure to the result of another) burned through 500,000,000
// instructions without completing, while the identical expression on a
// warm interpreter completes in about 47,000. Isolated by direct A/B
// comparison - content, fuel magnitude, and CRLF stripping were all
// ruled out first. Recorded as ADR 0042; root cause not fully
// explained, but the reliable fix (stay warm, matching how this tier is
// used everywhere else) is.
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

static bool checkOne(const std::string& hrr, const char* label, const std::string& tail, int64_t expected) {
	std::string setup = R"((define memory (lambda (i) (* i 10))) (define key (lambda (i) (+ i 1))) )";
	std::string expr = "(begin " + hrr + setup + tail;
	int64_t result;
	try {
		result = s7RiscvEvalInt(expr);
	} catch (const std::exception& e) {
		printf("%s: EXCEPTION: %s\n", label, e.what());
		return false;
	}
	bool ok = (result == expected);
	printf("%s: %s (got %lld, expected %lld, %llu instructions)\n", label, ok ? "PASS" : "FAIL",
		(long long)result, (long long)expected, (unsigned long long)s7RiscvTotalInstructions());
	return ok;
}

int main() {
	std::string hrr = readFile("riscv-guests/shrubbery/taskweft-hrr-generated.scm");
	if (hrr.empty()) {
		fprintf(stderr, "could not read taskweft-hrr-generated.scm\n");
		_exit(1);
	}

	s7RiscvInitialize();

	// index 3: memory=30, key=4, bound=34, recovered should be 30,
	// bundled=34, diffed=26, negated=-4, zero=0
	bool ok = true;
	ok &= checkOne(hrr, "bind", R"((define bound (hrr-bind memory key)) (bound 3)))", 34);
	ok &= checkOne(hrr, "unbind (round-trip)",
		R"((define bound (hrr-bind memory key)) (define recovered (hrr-unbind bound key)) (recovered 3)))", 30);
	ok &= checkOne(hrr, "bundle", R"((define bundled (hrr-bundle memory key)) (bundled 3)))", 34);
	ok &= checkOne(hrr, "diff", R"((define diffed (hrr-diff memory key)) (diffed 3)))", 26);
	ok &= checkOne(hrr, "neg", R"((define negated (hrr-neg key)) (negated 3)))", -4);
	ok &= checkOne(hrr, "zero", R"((define z (hrr-zero)) (z 3)))", 0);
	ok &= checkOne(hrr, "encodeFact", R"(((hrr-encode-fact memory key) 3)))", 34);

	fflush(stdout);
	if (!ok) {
		fprintf(stderr, "FAIL: one or more taskweft-hrr.shrub checks failed\n");
		_exit(1);
	}
	printf("PASS: taskweft-hrr.shrub verified (bind/unbind round-trip, bundle/diff/neg/zero/encodeFact all correct)\n");
	fflush(stdout);
	_exit(0);
}
