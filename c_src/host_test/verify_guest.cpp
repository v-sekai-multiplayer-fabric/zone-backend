// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Standalone proof that guest/weft_guest.elf's three named entry
// points (guest_loot_roll, guest_combat_replay, guest_progression_replay)
// are correct and deterministic, with no NIF/Elixir/BEAM involved -
// same determinism-proof shape as every s7_riscv_*_test.cpp in
// weft-warp-loop this was ported from (two independent
// libriscv::Machine instances, identical call sequence, byte-identical
// results/instruction counts).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

using Machine64 = riscv::Machine<riscv::RISCV64>;
using gaddr_t = riscv::address_type<riscv::RISCV64>;

struct GuestResult {
	int64_t values[4];
	int32_t count;
};

static std::string readFile(const char* path) {
	std::ifstream stream(path, std::ios::binary);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

// Calls a zero-argument guest function returning a >16-byte struct via
// the hidden-pointer riscv64 lp64d ABI convention - libriscv's own
// vmcall(name) (zero args) does not set this up, so it's done by hand,
// same pattern already proven in weft-warp-loop's
// s7_riscv_sandbox_abi_test.cpp callReturningVariant().
static bool callReturningStruct(Machine64& machine, const char* funcName, uint64_t fuel,
                                 GuestResult* outResult) {
	gaddr_t funcAddr = machine.memory.resolve_address(funcName);
	machine.cpu.reset_stack_pointer();
	gaddr_t retBufAddr = machine.stack_push(GuestResult{});
	machine.cpu.reg(riscv::REG_ARG0) = retBufAddr;
	machine.cpu.reg(riscv::REG_RA) = machine.memory.exit_address();
	try {
		machine.simulate_with<true>(fuel, 0u, funcAddr);
	} catch (const std::exception& e) {
		fprintf(stderr, "%s failed: %s\n", funcName, e.what());
		return false;
	}
	GuestResult* result = machine.memory.memarray<GuestResult>(retBufAddr, 1);
	*outResult = *result;
	return true;
}

struct RunResult {
	int64_t lootResult;
	GuestResult combat;
	GuestResult progression;
	uint64_t instructions;
	bool ok;
};

static RunResult runOnce(const std::vector<uint8_t>& binary, int64_t lootSeed) {
	RunResult r{};
	try {
		Machine64 machine(binary, riscv::MachineOptions<riscv::RISCV64>{ .memory_max = 256UL << 20 });
		machine.setup_linux({ "weft_guest" }, { "LC_ALL=C" });
		machine.setup_linux_syscalls();
		machine.simulate<true>(50'000'000ull);

		r.lootResult = static_cast<int64_t>(machine.vmcall<2'000'000ull>("guest_loot_roll", lootSeed));

		if (!callReturningStruct(machine, "guest_combat_replay", 20'000'000ull, &r.combat)) {
			return r;
		}
		if (!callReturningStruct(machine, "guest_progression_replay", 20'000'000ull, &r.progression)) {
			return r;
		}

		r.instructions = machine.instruction_counter();
		r.ok = true;
		return r;
	} catch (const std::exception& e) {
		fprintf(stderr, "runOnce: EXCEPTION: %s\n", e.what());
		return r;
	} catch (...) {
		fprintf(stderr, "runOnce: unknown exception\n");
		return r;
	}
}

int main() {
	std::string elfBytes = readFile("guest/weft_guest.elf");
	if (elfBytes.empty()) {
		fprintf(stderr, "could not read guest/weft_guest.elf\n");
		_exit(1);
	}
	std::vector<uint8_t> binary(elfBytes.begin(), elfBytes.end());

	constexpr int64_t kSeed = 42;
	constexpr int64_t kLootReference = 3;
	constexpr int64_t kCombatTickReference = 30;
	constexpr int64_t kCombatHpReference = 90;
	constexpr int64_t kCombatAliveReference = 1;
	constexpr int64_t kProgressionCreditsReference = 150;
	constexpr int64_t kProgressionAffinityReference = 16;

	RunResult results[2];
	for (int i = 0; i < 2; ++i) {
		results[i] = runOnce(binary, kSeed);
		if (!results[i].ok) {
			fprintf(stderr, "FAIL: run %d did not complete\n", i);
			_exit(1);
		}
	}

	printf("machine 0: loot=%lld combat=[tick=%lld hp=%lld alive=%lld] progression=[credits=%lld affinity=%lld] (%llu instructions)\n",
		(long long)results[0].lootResult,
		(long long)results[0].combat.values[0], (long long)results[0].combat.values[1], (long long)results[0].combat.values[2],
		(long long)results[0].progression.values[0], (long long)results[0].progression.values[1],
		(unsigned long long)results[0].instructions);
	printf("machine 1: loot=%lld combat=[tick=%lld hp=%lld alive=%lld] progression=[credits=%lld affinity=%lld] (%llu instructions)\n",
		(long long)results[1].lootResult,
		(long long)results[1].combat.values[0], (long long)results[1].combat.values[1], (long long)results[1].combat.values[2],
		(long long)results[1].progression.values[0], (long long)results[1].progression.values[1],
		(unsigned long long)results[1].instructions);
	fflush(stdout);

	bool ok = true;
	if (results[0].lootResult != results[1].lootResult ||
	    results[0].combat.values[0] != results[1].combat.values[0] ||
	    results[0].combat.values[1] != results[1].combat.values[1] ||
	    results[0].combat.values[2] != results[1].combat.values[2] ||
	    results[0].progression.values[0] != results[1].progression.values[0] ||
	    results[0].progression.values[1] != results[1].progression.values[1] ||
	    results[0].instructions != results[1].instructions) {
		fprintf(stderr, "FAIL: nondeterministic across two independent machines\n");
		ok = false;
	}
	if (results[0].lootResult != kLootReference) {
		fprintf(stderr, "FAIL: guest_loot_roll %lld != reference %lld\n",
			(long long)results[0].lootResult, (long long)kLootReference);
		ok = false;
	}
	if (results[0].combat.values[0] != kCombatTickReference ||
	    results[0].combat.values[1] != kCombatHpReference ||
	    results[0].combat.values[2] != kCombatAliveReference) {
		fprintf(stderr, "FAIL: guest_combat_replay does not match Lean4 reference\n");
		ok = false;
	}
	if (results[0].progression.values[0] != kProgressionCreditsReference ||
	    results[0].progression.values[1] != kProgressionAffinityReference) {
		fprintf(stderr, "FAIL: guest_progression_replay does not match Lean4 reference\n");
		ok = false;
	}
	if (!ok) {
		_exit(1);
	}

	printf("PASS: weft_guest.elf matches all three Lean4 references deterministically across two independent machines (%llu instructions each)\n",
		(unsigned long long)results[0].instructions);
	fflush(stdout);
	_exit(0);
}
