// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Minimal end-to-end proof that the vendored Flow actor runtime (RFD 5:
// the Godot-embeddable server core) actually builds and runs standalone
// in this repo - not just transforms cleanly under the actor-compiler
// (examples/hello_actor.actor.cpp is CI transform-only, never linked;
// see its own header comment). Modeled on the same asyncAdd example
// from Flow's own docs, but actually driven through a real g_network
// event loop, same boilerplate shape as weft-warp-loop's own
// s7_riscv_actor_test.cpp.
#include "flow/Platform.h"
#include "flow/TLSConfig.h"
#include "flow/flow.h"

#include <cstdio>
#include <cstdlib>

ACTOR Future<int> asyncAdd(Future<int> f, int offset) {
	int value = wait(f);
	return value + offset;
}

int main() {
	platformInit();
	Error::init();
	g_network = newNet2(TLSConfig());
	openTraceFile({}, 10 << 20, 100 << 20, ".", "weft_flow_hello");

	Future<int> result = asyncAdd(Future<int>(5), 3);
	if (!result.isReady()) {
		fprintf(stderr, "FAIL: actor did not complete synchronously\n");
		_exit(1);
	}
	if (result.get() != 8) {
		fprintf(stderr, "FAIL: expected 8, got %d\n", result.get());
		_exit(1);
	}
	printf("OK: Flow actor runtime works standalone in weft-warp-burrito (5 + 3 = %d)\n", result.get());
	fflush(stdout);
	// _exit(), not return: cross-library static destructor ordering on the
	// way out (g_network/OpenSSL) is unrelated to what this proves - same
	// rule s7_riscv_actor_test.cpp and the guest-side code already follow.
	_exit(0);
}
