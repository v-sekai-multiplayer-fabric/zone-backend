// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Checkpoint 3 of the "real content through the interpreted s7 path"
// plan (ADR 0028): the actual correctness+determinism proof. Loads
// riscv-guests/content/loot.scm (hand-ported from
// v-sekai-multiplayer-fabric/loot's Lean4 source) into TWO independent
// libriscv Machine instances and calls loot-roll on both, checking:
// (1) both agree with each other (ADR 0006's determinism proof shape),
// and (2) both agree with the Lean4 reference value, computed
// separately, once, via a throwaway `lake env lean --run` script against
// upstream commit 6c4439441c7ea9ef24b80fc68b6486e97219285b - not kept as
// a live file in this repo (ADR 0032: one source of truth, upstream)
// (`lake env lean --run`), not by hand-calculation.
//
// Golden vector: seed=42, table=[(1,10),(2,20),(3,5)] -> roll = 3
// (Lean4 reference: next32(42)=11355432, totalWeight=35, range=32,
// which lands in item 3's bucket [30,35) since cumulative weights are
// item1:[0,10) item2:[10,30) item3:[30,35)).
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
	std::string lootDefs = readFile("riscv-guests/content/loot.scm");
	if (lootDefs.empty()) {
		fprintf(stderr, "could not read riscv-guests/content/loot.scm\n");
		_exit(1);
	}

	const std::string expr =
		"(begin " + lootDefs + " (loot-roll 42 (list (cons 1 10) (cons 2 20) (cons 3 5))))";

	constexpr int64_t kLeanReference = 3;
	int64_t results[2];
	uint64_t instructionCounts[2];

	for (int i = 0; i < 2; ++i) {
		s7RiscvInitialize();
		results[i] = s7RiscvEvalInt(expr);
		instructionCounts[i] = s7RiscvTotalInstructions();
	}

	printf("machine 0: loot-roll(42, table) = %lld (%llu instructions)\n",
		(long long)results[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: loot-roll(42, table) = %lld (%llu instructions)\n",
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
	if (results[0] != kLeanReference) {
		fprintf(stderr, "FAIL: s7 result %lld does not match Lean4 reference %lld\n",
			(long long)results[0], (long long)kLeanReference);
		_exit(1);
	}

	printf("PASS: s7 matches the Lean4 reference (%lld) deterministically across two independent machines (%llu instructions each)\n",
		(long long)kLeanReference, (unsigned long long)instructionCounts[0]);
	fflush(stdout);
	_exit(0);
}
