// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Proves the vendored libriscv stack compiles, links, and the two
// properties ADR 0006 relies on actually hold for the vendored version:
//   1. fuel metering - machine.simulate<false>(max_instructions) returns
//      false (didn't finish) when the budget is too small, instead of
//      running the guest to completion or hanging.
//   2. deterministic execution - loading and running the same guest ELF
//      with the same fuel budget twice produces the same instruction
//      count and the same return value both times.
// No Flow, no s7, no VMCALL boundary - guest is the prebuilt fib.rv64.elf
// shipped in the vendored examples/embed/ directory, run in full
// setup_linux()/setup_linux_syscalls() mode.

#include <libriscv/machine.hpp>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <vector>

using namespace riscv;

namespace {

std::vector<uint8_t> read_guest_elf(const char *path) {
	std::ifstream stream(path, std::ios::in | std::ios::binary);
	if (!stream) {
		std::fprintf(stderr, "FAIL: could not open guest ELF: %s\n", path);
		std::exit(1);
	}
	return std::vector<uint8_t>(
			(std::istreambuf_iterator<char>(stream)),
			std::istreambuf_iterator<char>());
}

struct RunResult {
	bool completed;
	uint64_t instruction_count;
	long return_value;
};

RunResult run_fib(const std::vector<uint8_t> &binary, uint64_t fuel) {
	Machine<RISCV64> machine{binary, {.memory_max = 64UL << 20}};
	machine.setup_linux({"fib.rv64.elf", "20"}, {"LC_ALL=C"});
	machine.setup_linux_syscalls();

	const bool completed = machine.simulate<false>(fuel);
	RunResult result{};
	result.completed = completed;
	result.instruction_count = machine.instruction_counter();
	result.return_value = completed ? machine.return_value<long>() : 0;
	return result;
}

} // namespace

int main() {
	const std::vector<uint8_t> binary = read_guest_elf(LIBRISCV_VENDOR_TEST_GUEST_ELF);

	// 1. Fuel too small: the guest must not be allowed to finish.
	const RunResult starved = run_fib(binary, 100);
	if (starved.completed) {
		std::fprintf(stderr,
				"FAIL: guest completed fib(20) in <=100 instructions - "
				"fuel metering did not bound execution\n");
		return 1;
	}

	// 2. Generous fuel, run twice: same guest + same fuel must produce the
	// same instruction count and the same return value both times.
	constexpr uint64_t kGenerousFuel = 50'000'000ull;
	const RunResult first = run_fib(binary, kGenerousFuel);
	const RunResult second = run_fib(binary, kGenerousFuel);

	if (!first.completed || !second.completed) {
		std::fprintf(stderr, "FAIL: fib(20) did not complete within %llu instructions\n",
				static_cast<unsigned long long>(kGenerousFuel));
		return 1;
	}
	if (first.instruction_count != second.instruction_count) {
		std::fprintf(stderr,
				"FAIL: instruction count differs between runs (%llu vs %llu) - "
				"not deterministic\n",
				static_cast<unsigned long long>(first.instruction_count),
				static_cast<unsigned long long>(second.instruction_count));
		return 1;
	}
	if (first.return_value != second.return_value) {
		std::fprintf(stderr, "FAIL: return value differs between runs (%ld vs %ld)\n",
				first.return_value, second.return_value);
		return 1;
	}

	std::printf(
			"OK: libriscv fuel-starved run stopped early; two fuel-generous runs of "
			"fib.rv64.elf matched exactly (%llu instructions, return value %ld)\n",
			static_cast<unsigned long long>(first.instruction_count), first.return_value);
	return 0;
}
