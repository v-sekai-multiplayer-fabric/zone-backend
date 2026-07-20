// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// C++ declarations for the libriscv-sandboxed s7 guest
// (flow-toolchain/riscv-guests/s7_guest.elf, built from
// riscv-guests/s7_guest_main.c + thirdparty/s7/s7.c - see
// riscv-guests/README.md for the exact cross-compile recipe). This is
// ADR 0006's sandboxed scripting tier, now actually wired: a Flow actor
// calls in synchronously via a fuel-bounded VMCALL, the same shape
// fanout-core's Lean4 FFI already uses (fanout_core_ffi.h) - one
// process-wide Machine instance, called sequentially by a single actor,
// same "no lock needed" justification.

#pragma once

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

#include <libriscv/machine.hpp>

// Runs the guest's own init sequence (loads the ELF, executes main(),
// which calls s7_init() and _exit()s, leaving the interpreter alive for
// repeated vmcalls). Aborts the process on failure - matching
// fanoutCoreInitialize's contract, there is no recovery from the guest
// failing to initialize.
void s7RiscvInitialize();

// Total RISC-V instructions executed across all s7RiscvEval calls so
// far in this process - exposed so a caller (or a test) can verify the
// same call sequence costs the same total fuel every time, the
// determinism property this tier depends on.
uint64_t s7RiscvTotalInstructions();

// Internal: the process-wide Machine instance and running fuel total.
// Not in an anonymous namespace (this is a header) - declared extern
// here, defined once in s7_riscv_core.cpp.
extern std::unique_ptr<riscv::Machine<riscv::RISCV64>> g_s7RiscvMachine;
extern uint64_t g_s7RiscvTotalInstructions;

// Fuel-bounded synchronous call into the guest: evaluates one Scheme
// expression. MaxInstructions bounds the guest's execution cost
// deterministically (RISC-V instructions, not wall-clock - see
// docs/decisions/0006-libriscv-sandboxed-s7-lisp-over-native-janet.md)
// and throws riscv::MachineTimeoutException on exhaustion. A template
// parameter, not a runtime argument, because libriscv's own vmcall()
// takes its instruction limit the same way. The guest prints its result
// through its own stdout (a real Linux write() syscall) rather than
// marshalling a buffer across the host/guest address-space boundary.
template <uint64_t MaxInstructions = 2'000'000ull>
inline void s7RiscvEval(const std::string& expression) {
	if (!g_s7RiscvMachine) {
		fprintf(stderr, "s7RiscvEval: s7RiscvInitialize() was not called\n");
		abort();
	}
	// vmcall() calls simulate_with(MAXI, /*counter=*/0u, pc) internally -
	// the instruction counter restarts at 0 for each vmcall, it does not
	// keep accumulating from wherever a previous call (or the init-time
	// simulate() run) left it. So the counter *after* one vmcall is
	// already "instructions this call used", not a running total to
	// diff against a "before" snapshot - subtracting one broke the fuel
	// accounting during development (looked like nondeterminism; it was
	// actually unsigned wraparound from subtracting across a counter
	// reset boundary).
	g_s7RiscvMachine->template vmcall<MaxInstructions>("guest_eval", expression);
	g_s7RiscvTotalInstructions += g_s7RiscvMachine->instruction_counter();
}

// Fuel-bounded synchronous call into the guest, returning a usable
// integer result directly (no stdout scraping - see guest_eval_int in
// riscv-guests/s7_guest_main.c). For content whose result the host
// needs programmatically (a loot roll's item id, a damage value), not
// just for a human to read off the console.
template <uint64_t MaxInstructions = 2'000'000ull>
inline int64_t s7RiscvEvalInt(const std::string& expression) {
	if (!g_s7RiscvMachine) {
		fprintf(stderr, "s7RiscvEvalInt: s7RiscvInitialize() was not called\n");
		abort();
	}
	int64_t result = (int64_t)g_s7RiscvMachine->template vmcall<MaxInstructions>("guest_eval_int", expression);
	g_s7RiscvTotalInstructions += g_s7RiscvMachine->instruction_counter();
	return result;
}
