// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// The BEAM-facing boundary: an erl_nif wrapping one libriscv::Machine
// per Sandbox resource. This is deliberately thin - all it does is
// (1) construct/destroy a Machine from guest/weft_guest.elf, and
// (2) run one of the guest's three fixed, named capabilities with a
// caller-supplied fuel (gas) budget, catching libriscv's own
// out-of-fuel/trap exceptions and turning them into {error, Reason}
// instead of crashing the calling scheduler thread.
//
// No generic eval entry point exists here either - call_capability
// only accepts the closed set of atoms below, each mapped to one
// fixed guest-exported symbol name. Adding a new capability means
// adding a new guest function *and* a new case here, by hand - never
// a caller-supplied string naming an arbitrary guest symbol.
//
// "Pause" in this design is actor-level, not instruction-level: each
// call is a single fuel-bounded run that either completes or is
// killed by libriscv's own fuel exhaustion (MachineTimeoutException
// below) - there is no guest-side coroutine/yield support, so this NIF
// cannot suspend a call mid-execution and resume it later. What the
// actor model actually buys here is that a WeftWarpBurrito.Sandbox
// GenServer only ever runs one capability call at a time and is fully
// idle (inspectable, restartable by its supervisor, free to process
// other messages) between calls - "pause between gas-metered calls",
// not "pause mid-instruction". If true mid-execution resumability is
// ever needed, it requires guest-side cooperation (an explicit
// step-function the guest yields from), not just a host-side change.
//
// Scheduling note: these are dirty NIFs (see nifFuncs below) - guest
// execution is CPU-bound and fuel-bounded but not time-bounded, so it
// must not run on a normal BEAM scheduler thread.
#include <erl_nif.h>

#include <cstdint>
#include <cstring>
#include <fstream>
#include <memory>
#include <new>
#include <sstream>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

namespace {

using Machine64 = riscv::Machine<riscv::RISCV64>;
using gaddr_t = riscv::address_type<riscv::RISCV64>;

struct GuestResult {
	int64_t values[4];
	int32_t count;
};

struct SandboxResource {
	// Machine's constructor takes the ELF image as a view
	// (std::string_view / span / const vector&), not an owned copy - it
	// keeps pointers into this buffer for the Machine's whole lifetime
	// (zero-copy ELF loading), so the bytes must outlive the Machine.
	// Members destruct in reverse declaration order, so declaring
	// elfBytes first means machine is destroyed first, elfBytes last.
	std::vector<uint8_t> elfBytes;
	std::unique_ptr<Machine64> machine;
};

ErlNifResourceType* g_sandboxResourceType = nullptr;

void sandboxResourceDestructor(ErlNifEnv*, void* obj) {
	static_cast<SandboxResource*>(obj)->~SandboxResource();
}

std::string readFile(const std::string& path) {
	std::ifstream stream(path, std::ios::binary);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

// Mirrors libriscv's own setup_call()+vmcall() (machine_vmcall.hpp),
// but with a runtime fuel budget instead of a compile-time template
// parameter - vmcall<MAXI>(...) requires MAXI at compile time, which
// can't represent a caller-supplied gas value from Elixir.
int64_t callScalar(Machine64& machine, const char* funcName, uint64_t fuel, int64_t arg) {
	gaddr_t funcAddr = machine.memory.resolve_address(funcName);
	machine.cpu.reset_stack_pointer();
	machine.setup_call(arg); // also sets REG_RA = exit_address()
	machine.simulate_with<true>(fuel, 0u, funcAddr);
	return static_cast<int64_t>(machine.cpu.reg(riscv::REG_ARG0));
}

// Calls a zero-argument guest function returning a >16-byte struct via
// the hidden-pointer riscv64 lp64d ABI convention (automatic under the
// plain C ABI, no guest-side marshalling code needed).
GuestResult callStruct(Machine64& machine, const char* funcName, uint64_t fuel) {
	gaddr_t funcAddr = machine.memory.resolve_address(funcName);
	machine.cpu.reset_stack_pointer();
	gaddr_t retBufAddr = machine.stack_push(GuestResult{});
	machine.cpu.reg(riscv::REG_ARG0) = retBufAddr;
	machine.cpu.reg(riscv::REG_RA) = machine.memory.exit_address();
	machine.simulate_with<true>(fuel, 0u, funcAddr);
	return *machine.memory.memarray<GuestResult>(retBufAddr, 1);
}

ERL_NIF_TERM makeErrorAtom(ErlNifEnv* env, const char* reason) {
	return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_atom(env, reason));
}

// Maps a libriscv MachineException to an Elixir-facing reason atom -
// gas_exhausted is the one callers are expected to actually branch on
// (it means "raise the fuel budget and retry"); everything else is a
// real guest fault (illegal instruction, out-of-memory, etc.) that
// retrying with more fuel will not fix.
ERL_NIF_TERM machineExceptionToTerm(ErlNifEnv* env, const riscv::MachineException& e) {
	if (dynamic_cast<const riscv::MachineTimeoutException*>(&e) != nullptr) {
		return makeErrorAtom(env, "gas_exhausted");
	}
	return makeErrorAtom(env, "guest_trap");
}

ERL_NIF_TERM newSandbox(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
	if (argc != 1) return enif_make_badarg(env);

	unsigned pathLen = 0;
	if (!enif_get_list_length(env, argv[0], &pathLen)) return enif_make_badarg(env);
	// buffer must hold pathLen characters plus enif_get_string's own
	// trailing NUL - sizing it to exactly pathLen (as an earlier version
	// of this function did) writes one byte past the buffer.
	std::vector<char> pathBuf(pathLen + 1, '\0');
	if (enif_get_string(env, argv[0], pathBuf.data(), pathBuf.size(), ERL_NIF_LATIN1) <= 0) {
		return enif_make_badarg(env);
	}
	std::string path(pathBuf.data());

	std::string fileContents = readFile(path);
	if (fileContents.empty()) {
		return makeErrorAtom(env, "guest_elf_not_found");
	}

	void* mem = enif_alloc_resource(g_sandboxResourceType, sizeof(SandboxResource));
	auto* res = new (mem) SandboxResource();
	// Stored on the resource (not a function-local) so it outlives this
	// call - Machine only holds a view into it, per SandboxResource's
	// own field-ordering comment above.
	res->elfBytes.assign(fileContents.begin(), fileContents.end());

	try {
		res->machine = std::make_unique<Machine64>(
			res->elfBytes, riscv::MachineOptions<riscv::RISCV64>{ .memory_max = 256UL << 20 });
		res->machine->setup_linux({ "weft_guest" }, { "LC_ALL=C" });
		res->machine->setup_linux_syscalls();
		res->machine->simulate<true>(50'000'000ull); // guest_init(): loads loot/combat/progression content
	} catch (const std::exception&) {
		res->~SandboxResource();
		enif_release_resource(mem);
		return makeErrorAtom(env, "guest_init_failed");
	}

	ERL_NIF_TERM term = enif_make_resource(env, res);
	enif_release_resource(res); // term now owns the reference
	return enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
}

ERL_NIF_TERM callCapability(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
	if (argc != 3) return enif_make_badarg(env);

	SandboxResource* res = nullptr;
	if (!enif_get_resource(env, argv[0], g_sandboxResourceType, reinterpret_cast<void**>(&res))) {
		return enif_make_badarg(env);
	}

	char capabilityBuf[64];
	if (enif_get_atom(env, argv[1], capabilityBuf, sizeof(capabilityBuf), ERL_NIF_LATIN1) <= 0) {
		return enif_make_badarg(env);
	}
	std::string capability(capabilityBuf);

	ErlNifUInt64 fuel = 0;
	if (!enif_get_uint64(env, argv[2], &fuel)) return enif_make_badarg(env);

	Machine64& machine = *res->machine;

	try {
		if (capability == "loot_roll") {
			int64_t result = callScalar(machine, "guest_loot_roll", fuel, 42);
			return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_int64(env, result));
		}
		if (capability == "combat_replay") {
			GuestResult r = callStruct(machine, "guest_combat_replay", fuel);
			return enif_make_tuple2(
				env, enif_make_atom(env, "ok"),
				enif_make_tuple3(env, enif_make_int64(env, r.values[0]), enif_make_int64(env, r.values[1]),
					enif_make_int64(env, r.values[2])));
		}
		if (capability == "progression_replay") {
			GuestResult r = callStruct(machine, "guest_progression_replay", fuel);
			return enif_make_tuple2(
				env, enif_make_atom(env, "ok"),
				enif_make_tuple2(env, enif_make_int64(env, r.values[0]), enif_make_int64(env, r.values[1])));
		}
		return makeErrorAtom(env, "unknown_capability");
	} catch (const riscv::MachineException& e) {
		return machineExceptionToTerm(env, e);
	} catch (const std::exception&) {
		return makeErrorAtom(env, "guest_trap");
	}
}

int onLoad(ErlNifEnv* env, void**, ERL_NIF_TERM) {
	ErlNifResourceFlags flags = static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER);
	g_sandboxResourceType =
		enif_open_resource_type(env, nullptr, "weft_sandbox", sandboxResourceDestructor, flags, nullptr);
	return g_sandboxResourceType == nullptr ? -1 : 0;
}

ErlNifFunc nifFuncs[] = {
	{"new_sandbox_nif", 1, newSandbox, ERL_NIF_DIRTY_JOB_CPU_BOUND},
	{"call_capability_nif", 3, callCapability, ERL_NIF_DIRTY_JOB_CPU_BOUND},
};

} // namespace

ERL_NIF_INIT(Elixir.WeftWarpBurrito.SandboxNif, nifFuncs, onLoad, nullptr, nullptr, nullptr)
