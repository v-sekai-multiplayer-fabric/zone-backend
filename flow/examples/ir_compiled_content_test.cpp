// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Checkpoint 4 of ADR 0013/0014's compiler PERT plan: load a
// Lean4-compiled-to-RISC-V function (built by
// fanout-core/IrCodegenScratch.lean's codegen, checkpoint 3, then
// linked into a minimal freestanding ELF - no libc, entry point set
// directly to the function itself via `-Wl,-e,<symbol>`, unlike
// s7_guest.elf which needs a real newlib _start/main to run s7_init()
// first) into libriscv and vmcall it, matching ADR 0006's own
// determinism-proof shape: two independent Machine instances given the
// identical call must produce byte-identical instruction counts.
//
// Standalone (no Flow actor) - matching libriscv_vendor_test.cpp's own
// pattern, since this checkpoint is about the VMCALL/ELF-loading
// question, not actor composition (already proven separately by
// s7_riscv_actor_test.cpp for the interpreted s7 guest).

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <vector>

#include <libriscv/machine.hpp>

#ifndef IR_COMPILED_CONTENT_TEST_GUEST_ELF
#error "IR_COMPILED_CONTENT_TEST_GUEST_ELF must be defined to the compiled content ELF path"
#endif

static std::vector<uint8_t> readFile(const char* path) {
	std::ifstream stream(path, std::ios::in | std::ios::binary);
	std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
	return bytes;
}

int main() {
	std::vector<uint8_t> binary = readFile(IR_COMPILED_CONTENT_TEST_GUEST_ELF);
	if (binary.empty()) {
		fprintf(stderr, "could not read %s\n", IR_COMPILED_CONTENT_TEST_GUEST_ELF);
		return 1;
	}

	// hysteresisTicksFor(6) = max 1 (6/2) = max 1 3 = 3 - the exact case
	// hand-traced in IrCodegenScratch.lean's own header comment.
	constexpr uint64_t kInput = 6;
	constexpr uint64_t kExpected = 3;

	uint64_t results[2];
	uint64_t instructionCounts[2];

	for (int i = 0; i < 2; ++i) {
		riscv::Machine<riscv::RISCV64> machine(
			binary, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
		machine.setup_linux({"ir_compiled_content"}, {"LC_ALL=C"});
		machine.setup_linux_syscalls();

		try {
			results[i] = machine.vmcall<2'000'000ull>("Fanoutcore_hysteresisTicksFor", kInput);
		} catch (const std::exception& e) {
			fprintf(stderr, "vmcall failed on machine %d: %s\n", i, e.what());
			return 1;
		}
		instructionCounts[i] = machine.instruction_counter();
	}

	printf("machine 0: result=%llu instructions=%llu\n",
		(unsigned long long)results[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: result=%llu instructions=%llu\n",
		(unsigned long long)results[1], (unsigned long long)instructionCounts[1]);

	if (results[0] != kExpected || results[1] != kExpected) {
		fprintf(stderr, "FAIL: expected %llu, got %llu and %llu\n",
			(unsigned long long)kExpected, (unsigned long long)results[0], (unsigned long long)results[1]);
		return 1;
	}
	if (instructionCounts[0] != instructionCounts[1]) {
		fprintf(stderr, "FAIL: nondeterministic instruction count: %llu vs %llu\n",
			(unsigned long long)instructionCounts[0], (unsigned long long)instructionCounts[1]);
		return 1;
	}

	printf("PASS: both machines returned %llu in %llu instructions, deterministically\n",
		(unsigned long long)kExpected, (unsigned long long)instructionCounts[0]);
	return 0;
}
