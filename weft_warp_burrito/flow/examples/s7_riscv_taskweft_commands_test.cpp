// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-commands.shrub against hand-traced expected values
// (Commands.lean is a thin, mostly-string/tag layer - no complex
// arithmetic to cross-check against a Lean reference beyond reading the
// source directly, matching how record-macros.scm's own tests were
// verified). Encoded as one integer:
//   manifold-merge-cmd((1 2)) -> (command "manifold-merge" (1 2))
//   execute-ectgtn-command of that -> (unhandled-command "manifold-merge")
//   execute-plan of a 2-element list (that command + a bad element) ->
//     2-element result list; length check = 2.
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
	std::string commands = readFile("riscv-guests/shrubbery/taskweft-commands-generated.scm");
	if (commands.empty()) {
		fprintf(stderr, "could not read taskweft-commands-generated.scm\n");
		_exit(1);
	}

	const std::string expr =
		"(begin " + commands +
		" (define cmd (manifold-merge-cmd (list 1 2)))"
		" (define result1 (execute-ectgtn-command cmd))"
		" (define plan (list cmd (list 'action \"foo\" '())))"
		" (define results (execute-plan plan))"
		" (+ (if (equal? (car result1) 'unhandled-command) 100 0)"
		"    (if (equal? (cadr result1) (manifold-merge-name)) 10 0)"
		"    (length results)))";

	constexpr int64_t kExpected = 112;  // 100 + 10 + 2
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: taskweft-commands.shrub verified\n");
	fflush(stdout);
	_exit(0);
}
