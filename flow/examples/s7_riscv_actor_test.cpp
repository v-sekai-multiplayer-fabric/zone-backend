// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Drives evalScriptedExpression (s7_riscv_actor.actor.cpp) through the
// real Flow runtime, twice, against two independently-initialized
// libriscv Machine instances - the same "replay" proof
// libriscv_vendor_test.cpp already established for a plain guest binary,
// now through a genuine Flow ACTOR calling into it, not just a bare
// host-side vmcall loop.
#include "s7_riscv_core.h"

#include "flow/Platform.h"
#include "flow/TLSConfig.h"
#include "flow/flow.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

Future<Void> evalScriptedExpression(std::string const& expression);

int main() {
	platformInit();
	Error::init();
	g_network = newNet2(TLSConfig());
	openTraceFile({}, 10 << 20, 100 << 20, ".", "s7_riscv_actor_test");

	const std::vector<std::string> exprs = {
		"(+ 1 2 3)",
		"(* 6 7)",
		"(string-append \"hello\" \" \" \"world\")",
		"(let loop ((n 0) (acc 0)) (if (= n 1000) acc (loop (+ n 1) (+ acc n))))",
	};

	uint64_t totals[2] = { 0, 0 };
	for (int run = 0; run < 2; run++) {
		s7RiscvInitialize();
		for (const auto& expr : exprs) {
			Future<Void> f = evalScriptedExpression(expr);
			if (!f.isReady()) {
				fprintf(stderr, "run %d: actor did not complete synchronously for: %s\n", run, expr.c_str());
				return 1;
			}
		}
		totals[run] = s7RiscvTotalInstructions();
		printf("run %d total instructions through the actor: %llu\n", run, (unsigned long long)totals[run]);
		fflush(stdout);
	}

	if (totals[0] != totals[1]) {
		fprintf(stderr, "NOT DETERMINISTIC: %llu != %llu\n", (unsigned long long)totals[0], (unsigned long long)totals[1]);
		fflush(stderr);
		_exit(1);
	}
	printf("OK: identical fuel cost (%llu instructions) across two independent actor runs\n", (unsigned long long)totals[0]);
	fflush(stdout);
	// _exit(), not return: this process's global state (the libriscv
	// Machine, Flow's g_network, OpenSSL) has cross-library static
	// destructor ordering issues on the way out that are unrelated to
	// (and unstarted work beyond) what this test proves - the same
	// "never return from main normally" reasoning the RISC-V guest
	// itself already follows (riscv-guests/s7_guest_main.c), just on
	// the host side of the boundary this time.
	_exit(0);
}
