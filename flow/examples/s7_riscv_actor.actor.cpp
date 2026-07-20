// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// A real Flow actor calling into the libriscv-sandboxed s7 guest
// (s7_riscv_core.h) - proving ADR 0006's scripting tier actually goes
// through the actor-compiler's transform and participates as a genuine
// ACTOR, not a bare host function call dressed up to look like one. The
// vmcall itself is synchronous (it doesn't `wait` mid-flight - see
// s7_riscv_core.h's comment on why that's fine for Flow's determinism
// model: pure computation over actor-local/passed-in state between
// suspension points needs no special handling), so this actor has no
// `wait` of its own either - a real ACTOR doesn't require one.

#include "s7_riscv_core.h"

#include "flow/flow.h"

#include "flow/actorcompiler.h" // This must be the last #include.

ACTOR Future<Void> evalScriptedExpression(std::string expression) {
	s7RiscvEval(expression);
	return Void();
}
