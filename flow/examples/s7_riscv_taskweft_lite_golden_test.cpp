// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Golden-vector proof for taskweft-lite.shrub's find-plan, against this
// repo's own real domain, plan/bootstrap-domain.json - not a synthetic
// example. That domain (hand-encoded below as s7 data, matching its
// JSON-LD structure field-for-field):
//
//   variables: milestone.stack = "flow_toolchain_ready"
//   actions:
//     vendor_picoquic_stack: set milestone.stack = "picoquic_vendored_standalone"
//     bridge_fanout_via_lean_core: set milestone.stack = "picoquic_fanout_server_bridged"
//   methods:
//     bootstrap -> alternative "next": subtasks [[bridge_fanout_via_lean_core]]
//   todo_list: [[bootstrap]]
//
// Expected plan: (bridge_fanout_via_lean_core) - the method "bootstrap"
// has exactly one alternative, decomposing directly to the one action
// that reaches the "bridged" milestone; vendor_picoquic_stack is never
// selected (not reachable from this todo_list, matching the real
// domain's own bootstrap.lean's single "next" alternative).
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
	std::string algo = readFile("riscv-guests/shrubbery/taskweft-lite-generated.scm");
	if (algo.empty()) {
		fprintf(stderr, "could not read riscv-guests/shrubbery/taskweft-lite-generated.scm "
			"(run: python3 riscv-guests/shrubbery/shrubbery_to_scheme.py "
			"riscv-guests/shrubbery/taskweft-lite.shrub > riscv-guests/shrubbery/taskweft-lite-generated.scm)\n");
		_exit(1);
	}

	const std::string domain =
		" (define state (list (cons \"/milestone/stack\" \"flow_toolchain_ready\")))"
		" (define actions (list"
		"   (cons \"vendor_picoquic_stack\" (list (cons \"/milestone/stack\" \"picoquic_vendored_standalone\")))"
		"   (cons \"bridge_fanout_via_lean_core\" (list (cons \"/milestone/stack\" \"picoquic_fanout_server_bridged\")))))"
		" (define methods (list"
		"   (cons \"bootstrap\" (list (cons \"next\" (list (list \"bridge_fanout_via_lean_core\")))))))"
		" (define todo (list (list \"bootstrap\")))";

	const std::string expr =
		"(begin " + algo + domain +
		" (let ((result (find-plan state todo actions methods)))"
		"   (if (and result (equal? (car (cdr result)) (list \"bridge_fanout_via_lean_core\")))"
		"       1 0)))";

	constexpr int64_t kExpected = 1;
	int64_t results[2];
	uint64_t instructionCounts[2];

	for (int i = 0; i < 2; ++i) {
		s7RiscvInitialize();
		results[i] = s7RiscvEvalInt(expr);
		instructionCounts[i] = s7RiscvTotalInstructions();
	}

	printf("machine 0: plan-matches = %lld (%llu instructions)\n",
		(long long)results[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: plan-matches = %lld (%llu instructions)\n",
		(long long)results[1], (unsigned long long)instructionCounts[1]);
	fflush(stdout);

	if (results[0] != results[1]) {
		fprintf(stderr, "FAIL: nondeterministic result: %lld vs %lld\n",
			(long long)results[0], (long long)results[1]);
		_exit(1);
	}
	if (instructionCounts[0] != instructionCounts[1]) {
		fprintf(stderr, "FAIL: nondeterministic instruction count: %llu vs %llu\n",
			(unsigned long long)instructionCounts[0], (unsigned long long)instructionCounts[1]);
		_exit(1);
	}
	if (results[0] != kExpected) {
		fprintf(stderr, "FAIL: expected plan (bridge_fanout_via_lean_core), got a mismatch\n");
		_exit(1);
	}

	printf("PASS: find-plan produced the expected plan deterministically across two independent machines (%llu instructions each)\n",
		(unsigned long long)instructionCounts[0]);
	fflush(stdout);
	_exit(0);
}
