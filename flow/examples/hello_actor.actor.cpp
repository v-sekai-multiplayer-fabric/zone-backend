// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Minimal smoke-test input for the vendored FoundationDB actor-compiler
// (flow-toolchain.yml's transform-only CI check) — modeled on the
// asyncAdd example from the official Flow docs. Not compiled/linked as
// part of the flow runtime build; the picoquic fanout server is that
// project's real example now.

ACTOR Future<int> asyncAdd(Future<int> f, int offset) {
	int value = wait(f);
	return value + offset;
}
