// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Checkpoint 1 of the "real content through the interpreted s7 path"
// PERT plan (ADR 0028): verifies guest_eval_int actually returns a
// usable integer value via the return register, not just that it
// builds. Standalone (no Flow actor) - matching
// ir_compiled_content_test.cpp's own pattern, since actor composition
// is already proven separately by s7_riscv_actor_test.cpp.
#include "s7_riscv_core.h"

#include <cstdio>
#include <cstdlib>

int main() {
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt("(+ 1 2)");
	printf("(+ 1 2) = %lld\n", (long long)result);
	fflush(stdout);
	// _exit(), not return: the global libriscv Machine's destructor
	// ordering on normal process exit crashes (confirmed by isolating
	// this exact process teardown as the failure point, not
	// guest_eval_int itself, which returns the correct value) - the
	// same class of issue s7_riscv_actor_test.cpp already documents and
	// works around the same way.
	if (result != 3) {
		fprintf(stderr, "FAIL: expected 3, got %lld\n", (long long)result);
		_exit(1);
	}
	printf("PASS: guest_eval_int returned a real usable value via the register, not stdout\n");
	fflush(stdout);
	_exit(0);
}
