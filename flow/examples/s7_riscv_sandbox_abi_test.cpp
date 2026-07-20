// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Task D of the "port s7-Lisp-1-in-libriscv into a fabric-godot-core
// module" plan: proves riscv-guests/s7_sandbox_guest.elf's named entry
// points are correct and deterministic, without building the Godot
// engine at all. Same determinism-proof shape every other
// s7_riscv_*_test.cpp in this repo already uses (two independent
// libriscv::Machine instances, identical call, byte-identical results/
// instruction counts).
//
// Two entry points checked:
//   - guest_loot_roll(int64) -> int64: plain scalar ABI, no marshalling
//     needed at all - packed directly into the standard RV64 calling-
//     convention registers.
//   - guest_combat_replay() -> Variant (a real Array): the first proof
//     that real Array/Dictionary marshalling works end to end. Since
//     this harness is a bare libriscv::Machine (not Godot's real
//     Sandbox class), it has to implement a minimal version of two
//     things Sandbox normally provides: (1) the ECALL_VCREATE (517)
//     syscall handler that allocates a "scoped variant" Array on the
//     host side and copies elements out of guest memory
//     (api_vcreate's real behavior, reverse-engineered from
//     fabric-godot-core/modules/sandbox/src/sandbox_syscalls.cpp this
//     session), and (2) manually setting up the hidden return-pointer
//     argument (register a0) a large (24-byte) struct return needs
//     under the plain riscv64 lp64d C ABI - libriscv's own generic
//     vmcall() only packs Args... into registers, it does not know
//     about this convention; Sandbox::setup_arguments() handles it by
//     hand, and so does this harness.
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

static std::string readFile(const char* path) {
	std::ifstream stream(path, std::ios::binary);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

// -- Mirrors s7_sandbox_guest.c's own GuestVariant / program/cpp/api/
// variant.hpp's Variant: {uint32_t type; union[16 bytes]} = 24 bytes.
struct HostVariant {
	uint32_t type;
	uint32_t _pad;
	union {
		int64_t i;
		double f;
		float v4f[4];
		int32_t v4i[4];
	} v;
};
static_assert(sizeof(HostVariant) == 24, "HostVariant size mismatch");

constexpr uint32_t VT_ARRAY = 28;
constexpr size_t ECALL_VCREATE = 517;

// Per-runOnce "scoped variant" table, reset before every call - a
// deliberately minimal stand-in for Sandbox's own per-Sandbox-instance
// scoped variant storage (this harness only ever needs to resolve one
// Array result per run).
static std::vector<std::vector<int64_t>> g_scopedArrays;

// Replicates api_vcreate's real Array-creation path (method >= 0: copy
// `method` contiguous 24-byte Variant structs from guest memory) -
// simplified to INT-only elements, since that's all guest_combat_replay
// ever constructs.
static void sysVcreateHandler(Machine64& machine) {
	auto [outAddr, type, method, dataAddr] =
		machine.sysargs<gaddr_t, uint32_t, int, gaddr_t>();
	if (type == VT_ARRAY && method >= 0) {
		HostVariant* elems = machine.memory.memarray<HostVariant>(dataAddr, (size_t)method);
		std::vector<int64_t> arr;
		arr.reserve((size_t)method);
		for (int i = 0; i < method; ++i) {
			arr.push_back(elems[i].v.i);
		}
		g_scopedArrays.push_back(std::move(arr));
		uint32_t newIdx = (uint32_t)(g_scopedArrays.size() - 1);
		HostVariant* out = machine.memory.memarray<HostVariant>(outAddr, 1);
		out->type = VT_ARRAY;
		out->v.i = newIdx;
	} else {
		fprintf(stderr, "sysVcreateHandler: unsupported type=%u method=%d\n", type, method);
	}
}

// Calls a zero-Scheme-argument guest function that returns a large
// (>16 byte) struct via the hidden-pointer riscv64 lp64d ABI
// convention - libriscv's own vmcall(name) (zero args) does NOT set
// this up, so it's done by hand here, the same way
// Sandbox::setup_arguments() does it for real Variant-returning
// vmcalls.
static bool callReturningVariant(Machine64& machine, const char* funcName, uint64_t fuel,
                                  HostVariant* outResult) {
	gaddr_t funcAddr = machine.memory.resolve_address(funcName);
	machine.cpu.reset_stack_pointer();
	gaddr_t retBufAddr = machine.stack_push(HostVariant{});
	machine.cpu.reg(riscv::REG_ARG0) = retBufAddr;
	machine.cpu.reg(riscv::REG_RA) = machine.memory.exit_address();
	try {
		machine.simulate_with<true>(fuel, 0u, funcAddr);
	} catch (const std::exception& e) {
		fprintf(stderr, "%s failed: %s\n", funcName, e.what());
		return false;
	}
	HostVariant* result = machine.memory.memarray<HostVariant>(retBufAddr, 1);
	*outResult = *result;
	return true;
}

static bool runOnce(const std::vector<uint8_t>& binary, int64_t lootSeed, int64_t* outLootResult,
                     int64_t* outCombatTick, int64_t* outCombatHp, int64_t* outCombatAlive,
                     uint64_t* outInstructions) {
	g_scopedArrays.clear();
	try {
		Machine64 machine(binary, riscv::MachineOptions<riscv::RISCV64>{ .memory_max = 256UL << 20 });
		machine.setup_linux({ "s7_sandbox_guest" }, { "LC_ALL=C" });
		machine.setup_linux_syscalls();
		Machine64::install_syscall_handler(ECALL_VCREATE, sysVcreateHandler);
		machine.simulate<true>(50'000'000ull);

		*outLootResult = static_cast<int64_t>(machine.vmcall<2'000'000ull>("guest_loot_roll", lootSeed));

		HostVariant combatResult{};
		if (!callReturningVariant(machine, "guest_combat_replay", 20'000'000ull, &combatResult)) {
			return false;
		}
		if (combatResult.type != VT_ARRAY) {
			fprintf(stderr, "guest_combat_replay: expected an Array result, got type=%u\n", combatResult.type);
			return false;
		}
		uint32_t idx = (uint32_t)combatResult.v.i;
		if (idx >= g_scopedArrays.size() || g_scopedArrays[idx].size() != 3) {
			fprintf(stderr, "guest_combat_replay: malformed scoped array (idx=%u)\n", idx);
			return false;
		}
		*outCombatTick = g_scopedArrays[idx][0];
		*outCombatHp = g_scopedArrays[idx][1];
		*outCombatAlive = g_scopedArrays[idx][2];

		*outInstructions = machine.instruction_counter();
		return true;
	} catch (const std::exception& e) {
		fprintf(stderr, "runOnce: EXCEPTION: %s\n", e.what());
		fflush(stderr);
		return false;
	} catch (...) {
		fprintf(stderr, "runOnce: unknown exception\n");
		fflush(stderr);
		return false;
	}
}

int main() {
	std::string elfBytes = readFile("riscv-guests/s7_sandbox_guest.elf");
	if (elfBytes.empty()) {
		fprintf(stderr, "could not read riscv-guests/s7_sandbox_guest.elf\n");
		_exit(1);
	}
	std::vector<uint8_t> binary(elfBytes.begin(), elfBytes.end());

	constexpr int64_t kSeed = 42;
	constexpr int64_t kLootReference = 3; // same reference s7_riscv_loot_golden_test.cpp uses
	// Same golden vector as s7_riscv_combat_golden_test.cpp: spawn, 30
	// ticks, one opener attack -> final enemyHp=90, tick=30 (Lean4
	// reference).
	constexpr int64_t kCombatTickReference = 30;
	constexpr int64_t kCombatHpReference = 90;
	constexpr int64_t kCombatAliveReference = 1;

	int64_t lootResults[2] = { 0, 0 };
	int64_t combatTicks[2] = { 0, 0 };
	int64_t combatHps[2] = { 0, 0 };
	int64_t combatAlives[2] = { 0, 0 };
	uint64_t instructionCounts[2] = { 0, 0 };

	for (int i = 0; i < 2; ++i) {
		if (!runOnce(binary, kSeed, &lootResults[i], &combatTicks[i], &combatHps[i], &combatAlives[i],
		             &instructionCounts[i])) {
			_exit(1);
		}
	}

	printf("machine 0: guest_loot_roll(%lld)=%lld  guest_combat_replay()=[tick=%lld hp=%lld alive=%lld]  "
	       "(%llu instructions)\n",
		(long long)kSeed, (long long)lootResults[0], (long long)combatTicks[0], (long long)combatHps[0],
		(long long)combatAlives[0], (unsigned long long)instructionCounts[0]);
	printf("machine 1: guest_loot_roll(%lld)=%lld  guest_combat_replay()=[tick=%lld hp=%lld alive=%lld]  "
	       "(%llu instructions)\n",
		(long long)kSeed, (long long)lootResults[1], (long long)combatTicks[1], (long long)combatHps[1],
		(long long)combatAlives[1], (unsigned long long)instructionCounts[1]);
	fflush(stdout);

	bool ok = true;
	if (lootResults[0] != lootResults[1] || combatTicks[0] != combatTicks[1] || combatHps[0] != combatHps[1] ||
	    combatAlives[0] != combatAlives[1] || instructionCounts[0] != instructionCounts[1]) {
		fprintf(stderr, "FAIL: nondeterministic across two independent machines\n");
		ok = false;
	}
	if (lootResults[0] != kLootReference) {
		fprintf(stderr, "FAIL: guest_loot_roll result %lld does not match reference %lld\n",
			(long long)lootResults[0], (long long)kLootReference);
		ok = false;
	}
	if (combatTicks[0] != kCombatTickReference || combatHps[0] != kCombatHpReference ||
	    combatAlives[0] != kCombatAliveReference) {
		fprintf(stderr,
			"FAIL: guest_combat_replay result [tick=%lld hp=%lld alive=%lld] does not match Lean4 "
			"reference [tick=%lld hp=%lld alive=%lld]\n",
			(long long)combatTicks[0], (long long)combatHps[0], (long long)combatAlives[0],
			(long long)kCombatTickReference, (long long)kCombatHpReference, (long long)kCombatAliveReference);
		ok = false;
	}
	if (!ok) {
		_exit(1);
	}

	printf("PASS: guest_loot_roll (scalar ABI) and guest_combat_replay (real Array ABI) both match their "
	       "Lean4 references deterministically across two independent machines (%llu instructions each)\n",
		(unsigned long long)instructionCounts[0]);
	fflush(stdout);
	_exit(0);
}
