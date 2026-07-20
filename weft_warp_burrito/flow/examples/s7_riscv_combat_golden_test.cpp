// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Golden-vector proof for riscv-guests/content/combat.scm (hand-ported
// from v-sekai-multiplayer-fabric/combat), matching
// s7_riscv_loot_golden_test.cpp's own methodology: correctness against
// a freshly-computed Lean4 reference and determinism across two
// independent libriscv Machine instances, checked at once. The
// reference was computed once via a throwaway `lake env lean --run`
// script against upstream commit
// f9a1964892c6943e120c82bad398646944aaa10e - not kept as a live file in
// this repo (ADR 0032: one source of truth, upstream).
//
// Golden vector: spawn, then 30 ticks, then one opener attack. Lean4
// reference: final enemyHp = 90, final tick = 30.
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
	// guest never does its own (load ...); see combat.scm's own header
	// comment for why (a guest-side load would need a real filesystem
	// syscall from inside libriscv's fuel-metered sandbox).
	std::string macros = readFile("riscv-guests/content/record-macros.scm");
	std::string combatDefs = readFile("riscv-guests/content/combat.scm");
	if (macros.empty() || combatDefs.empty()) {
		fprintf(stderr, "could not read riscv-guests/content/{record-macros,combat}.scm\n");
		_exit(1);
	}
	combatDefs = macros + "\n" + combatDefs;

	// 30 'tick events, matching the golden vector's event sequence
	std::string ticks;
	for (int i = 0; i < 30; ++i) ticks += "'tick ";

	const std::string expr =
		"(begin " + combatDefs +
		" (state-hp (car (combat-replay (list 'spawn " + ticks + "'attack)))))";

	constexpr int64_t kLeanReferenceHp = 90;
	int64_t results[2];
	uint64_t instructionCounts[2];

	for (int i = 0; i < 2; ++i) {
		s7RiscvInitialize();
		results[i] = s7RiscvEvalInt(expr);
		instructionCounts[i] = s7RiscvTotalInstructions();
	}

	printf("machine 0: final enemyHp = %lld (%llu instructions)\n",
		(long long)results[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: final enemyHp = %lld (%llu instructions)\n",
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
	if (results[0] != kLeanReferenceHp) {
		fprintf(stderr, "FAIL: s7 result %lld does not match Lean4 reference %lld\n",
			(long long)results[0], (long long)kLeanReferenceHp);
		_exit(1);
	}

	printf("PASS: s7 matches the Lean4 reference (enemyHp=%lld) deterministically across two independent machines (%llu instructions each)\n",
		(long long)kLeanReferenceHp, (unsigned long long)instructionCounts[0]);
	fflush(stdout);
	_exit(0);
}
