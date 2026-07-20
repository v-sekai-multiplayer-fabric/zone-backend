// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Golden-vector proof for riscv-guests/content/progression.scm
// (hand-ported from v-sekai-multiplayer-fabric/progression), same
// methodology as s7_riscv_loot_golden_test.cpp /
// s7_riscv_combat_golden_test.cpp.
//
// Golden vector: grant(1), grant(1), sell(1,50), train, buyArt(1).
// Lean4 reference: final credits = 150, affinity = 16, items = [(1,1)],
// arts = [1]. This test checks credits (the field with the most
// arithmetic paths touched: two addItems, a sell's credit gain, a
// buyArt's credit spend).
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
	// Concatenated on the host, matching every other golden test - the
	// guest never does its own (load ...); see combat.scm's header
	// comment for why (a guest-side load would need a real filesystem
	// syscall from inside libriscv's fuel-metered sandbox).
	std::string macros = readFile("riscv-guests/content/record-macros.scm");
	std::string defs = readFile("riscv-guests/content/progression.scm");
	if (macros.empty() || defs.empty()) {
		fprintf(stderr, "could not read riscv-guests/content/{record-macros,progression}.scm\n");
		_exit(1);
	}
	defs = macros + "\n" + defs;

	const std::string expr =
		"(begin " + defs +
		" (profile-credits (car (progression-replay (list (list 'grant 1) (list 'grant 1) (list 'sell 1 50) 'train (list 'buyArt 1))))))";

	constexpr int64_t kLeanReferenceCredits = 150;
	int64_t results[2];
	uint64_t instructionCounts[2];

	for (int i = 0; i < 2; ++i) {
		s7RiscvInitialize();
		results[i] = s7RiscvEvalInt(expr);
		instructionCounts[i] = s7RiscvTotalInstructions();
	}

	printf("machine 0: final credits = %lld (%llu instructions)\n",
		(long long)results[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: final credits = %lld (%llu instructions)\n",
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
	if (results[0] != kLeanReferenceCredits) {
		fprintf(stderr, "FAIL: s7 result %lld does not match Lean4 reference %lld\n",
			(long long)results[0], (long long)kLeanReferenceCredits);
		_exit(1);
	}

	printf("PASS: s7 matches the Lean4 reference (credits=%lld) deterministically across two independent machines (%llu instructions each)\n",
		(long long)kLeanReferenceCredits, (unsigned long long)instructionCounts[0]);
	fflush(stdout);
	_exit(0);
}
