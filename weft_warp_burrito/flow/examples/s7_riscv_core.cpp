// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "s7_riscv_core.h"

#include <fstream>
#include <vector>

std::unique_ptr<riscv::Machine<riscv::RISCV64>> g_s7RiscvMachine;
uint64_t g_s7RiscvTotalInstructions = 0;

// libriscv's Memory keeps only a non-owning std::string_view over the
// buffer passed to the Machine constructor (memory.hpp: "const
// std::string_view m_binary") - it does not copy it. This must outlive
// the Machine, so it's a companion global, not a local in
// s7RiscvInitialize() - a local there was this wrapper's own real bug
// during development: simulate() calls made before the function
// returned worked fine (the vector was still alive), but any call after
// it returned - address_of(), vmcall() - dereferenced freed memory.
static std::vector<uint8_t> g_s7RiscvBinary;

void s7RiscvInitialize() {
	g_s7RiscvTotalInstructions = 0;
	std::ifstream stream("riscv-guests/s7_guest.elf", std::ios::in | std::ios::binary);
	g_s7RiscvBinary.assign((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
	if (g_s7RiscvBinary.empty()) {
		fprintf(stderr, "s7RiscvInitialize: could not read riscv-guests/s7_guest.elf\n");
		abort();
	}

	g_s7RiscvMachine = std::make_unique<riscv::Machine<riscv::RISCV64>>(
		g_s7RiscvBinary, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 256UL << 20});
	g_s7RiscvMachine->setup_linux({"s7_guest"}, {"LC_ALL=C"});
	g_s7RiscvMachine->setup_linux_syscalls();

	try {
		// Runs main(): guest_init() (s7_init()) then _exit(0), leaving
		// the interpreter alive in guest memory for repeated vmcalls.
		g_s7RiscvMachine->simulate<true>(50'000'000ull);
	} catch (const std::exception& e) {
		fprintf(stderr, "s7RiscvInitialize: guest init failed: %s\n", e.what());
		abort();
	}
}

uint64_t s7RiscvTotalInstructions() {
	return g_s7RiscvTotalInstructions;
}
