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
// not "pause mid-instruction". See rfd/0002 for the true mid-execution
// resume design this doesn't implement yet.
//
// Scheduling note: these are dirty NIFs (see the FINE_NIF flags
// below) - guest execution is CPU-bound and fuel-bounded but not
// time-bounded, so it must not run on a normal BEAM scheduler thread.
//
// Bindings use Fine (elixir-nx/fine) rather than hand-written erl_nif
// argument/resource marshalling - see rfd/0003 for why: it reuses
// libriscv/s7 as the guest execution substrate unchanged and only
// replaces the binding-layer boilerplate (path/atom decoding, resource
// type registration) with Fine's generated equivalent.
#include <fine.hpp>

#include <cstdint>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <tuple>
#include <variant>
#include <vector>

#include <libriscv/machine.hpp>

namespace {

using Machine64 = riscv::Machine<riscv::RISCV64>;
using gaddr_t = riscv::address_type<riscv::RISCV64>;

struct GuestResult {
	int64_t values[4];
	int32_t count;
};

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

} // namespace

// One Machine per resource, constructed from a guest ELF path. Not in
// the anonymous namespace above - FINE_RESOURCE needs external linkage
// to register this type by name.
class SandboxResource {
public:
	explicit SandboxResource(std::vector<uint8_t> elf) : elfBytes(std::move(elf)) {
		machine = std::make_unique<Machine64>(
			elfBytes, riscv::MachineOptions<riscv::RISCV64>{ .memory_max = 256UL << 20 });
		machine->setup_linux({ "weft_guest" }, { "LC_ALL=C" });
		machine->setup_linux_syscalls();
		machine->simulate<true>(50'000'000ull); // guest_init(): loads loot/combat/progression content
	}

	// Machine's constructor takes the ELF image as a view
	// (std::string_view / span / const vector&), not an owned copy - it
	// keeps pointers into this buffer for the Machine's whole lifetime
	// (zero-copy ELF loading), so the bytes must outlive the Machine.
	// Members destruct in reverse declaration order, so declaring
	// elfBytes first means machine is destroyed first, elfBytes last.
	std::vector<uint8_t> elfBytes;
	std::unique_ptr<Machine64> machine;
};

FINE_RESOURCE(SandboxResource);

namespace {

// Maps a libriscv MachineException to an Elixir-facing reason atom -
// gas_exhausted is the one callers are expected to actually branch on
// (it means "raise the fuel budget and retry"); everything else is a
// real guest fault (illegal instruction, out-of-memory, etc.) that
// retrying with more fuel will not fix.
fine::Atom machineExceptionToAtom(const riscv::MachineException& e) {
	if (dynamic_cast<const riscv::MachineTimeoutException*>(&e) != nullptr) {
		return fine::Atom("gas_exhausted");
	}
	return fine::Atom("guest_trap");
}

// Loads guest ELF at `path`, running guest_init() once.
std::variant<fine::Ok<fine::ResourcePtr<SandboxResource>>, fine::Error<fine::Atom>>
new_sandbox_nif(ErlNifEnv*, std::string path) {
	std::string fileContents = readFile(path);
	if (fileContents.empty()) {
		return fine::Error(fine::Atom("guest_elf_not_found"));
	}

	std::vector<uint8_t> elfBytes(fileContents.begin(), fileContents.end());
	try {
		return fine::Ok(fine::make_resource<SandboxResource>(std::move(elfBytes)));
	} catch (const std::exception&) {
		return fine::Error(fine::Atom("guest_init_failed"));
	}
}

FINE_NIF(new_sandbox_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// Runs one fixed, named guest capability with a fuel (gas) budget.
// `capability` is one of :loot_roll | :combat_replay | :progression_replay -
// never an arbitrary caller-supplied symbol name (see this file's own
// header comment for why: a generic "call this named guest symbol"
// entry point would defeat the whole point of a closed capability set).
//
// Each capability's success shape is a different arity, so this
// returns fine::Term directly (built by hand per branch) rather than a
// single std::variant<Ok<...>, ...> alternative per capability, which
// would need one variant arm per return shape for no real benefit.
fine::Term call_capability_nif(
	ErlNifEnv* env, fine::ResourcePtr<SandboxResource> resource, fine::Atom capability, uint64_t fuel) {
	Machine64& machine = *resource->machine;

	try {
		if (capability == "loot_roll") {
			int64_t result = callScalar(machine, "guest_loot_roll", fuel, 42);
			return fine::encode(env, fine::Ok(result));
		}
		if (capability == "combat_replay") {
			GuestResult r = callStruct(machine, "guest_combat_replay", fuel);
			return fine::encode(env, fine::Ok(std::make_tuple(r.values[0], r.values[1], r.values[2])));
		}
		if (capability == "progression_replay") {
			GuestResult r = callStruct(machine, "guest_progression_replay", fuel);
			return fine::encode(env, fine::Ok(std::make_tuple(r.values[0], r.values[1])));
		}
		return fine::encode(env, fine::Error(fine::Atom("unknown_capability")));
	} catch (const riscv::MachineException& e) {
		return fine::encode(env, fine::Error(machineExceptionToAtom(e)));
	} catch (const std::exception&) {
		return fine::encode(env, fine::Error(fine::Atom("guest_trap")));
	}
}

FINE_NIF(call_capability_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND);

} // namespace

// --- Compiled-program resource + host-call trampoline (RFD 0018) ---
//
// A second machine kind: RISC-V ELFs produced by the in-repo s7 AOT
// compiler (c_src/s7). Unlike the s7-interpreter guest above, these
// programs may ecall the host-math syscall (600, see c_src/s7/value.h)
// mid-execution when fixnum arithmetic overflows or touches a bignum
// handle. The handler cannot compute the answer here - the whole point
// (RFD 0018) is that Elixir's native arbitrary-precision integers do
// the math - so it stops the Machine (state persists in this resource),
// the NIF returns {:host_call, op, a, b} to the owning GenServer, and
// program_resume_nif() injects the result and continues execution.
//
// The exported-function names callable here come from ELFs we compile
// ourselves (never untrusted input); WeftWarpBurrito.Program's API is
// the gate, same trust shape as the fixed-capability set above.
class ProgramResource {
public:
	explicit ProgramResource(std::vector<uint8_t> elf) : elfBytes(std::move(elf)) {
		machine = std::make_unique<Machine64>(
			elfBytes, riscv::MachineOptions<riscv::RISCV64>{ .memory_max = 64UL << 20 });
		machine->set_userdata(this);
	}

	// Declaration order matters: see SandboxResource's comment.
	std::vector<uint8_t> elfBytes;
	std::unique_ptr<Machine64> machine;

	// Host-call trampoline state, set by the syscall handler.
	bool pending = false;
	int64_t pending_op = 0;
	int64_t pending_a = 0;
	int64_t pending_b = 0;
	gaddr_t pending_pc = 0;
	uint64_t fuel = 0;
};

FINE_RESOURCE(ProgramResource);

namespace {

constexpr size_t kSyscallHostMath = 600; // must match c_src/s7/value.h

// The handler table is static per Machine type; the s7-interpreter
// guest (SandboxResource) never issues syscall 600, so dispatch here
// always means a ProgramResource machine (whose userdata is set).
void install_host_math_handler_once() {
	static bool installed = false;
	if (installed) return;
	installed = true;
	Machine64::install_syscall_handler(kSyscallHostMath, [](Machine64& machine) {
		auto* program = machine.get_userdata<ProgramResource>();
		auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
		program->pending = true;
		program->pending_op = op;
		program->pending_a = a;
		program->pending_b = b;
		program->pending_pc = machine.cpu.pc();
		machine.stop();
	});
}

// Shared tail of call/resume: either the guest finished (result in a0)
// or it stopped at a host-math ecall (trampoline back to Elixir).
fine::Term program_finish(ErlNifEnv* env, ProgramResource& program) {
	Machine64& machine = *program.machine;
	if (program.pending) {
		return fine::encode(env, std::make_tuple(fine::Atom("host_call"), program.pending_op,
		                                          program.pending_a, program.pending_b));
	}
	return fine::encode(env, fine::Ok(static_cast<int64_t>(machine.cpu.reg(riscv::REG_ARG0))));
}

std::variant<fine::Ok<fine::ResourcePtr<ProgramResource>>, fine::Error<fine::Atom>>
new_program_nif(ErlNifEnv*, std::string elf_binary) {
	install_host_math_handler_once();
	std::vector<uint8_t> elfBytes(elf_binary.begin(), elf_binary.end());
	try {
		return fine::Ok(fine::make_resource<ProgramResource>(std::move(elfBytes)));
	} catch (const std::exception&) {
		return fine::Error(fine::Atom("bad_elf"));
	}
}

FINE_NIF(new_program_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Term program_call_nif(ErlNifEnv* env, fine::ResourcePtr<ProgramResource> resource,
                            std::string function, std::vector<int64_t> args, uint64_t fuel) {
	ProgramResource& program = *resource;
	Machine64& machine = *program.machine;
	try {
		if (args.size() > 8) {
			return fine::encode(env, fine::Error(fine::Atom("too_many_args")));
		}
		gaddr_t funcAddr = machine.memory.resolve_address(function.c_str());
		if (funcAddr == 0) {
			return fine::encode(env, fine::Error(fine::Atom("no_such_function")));
		}
		machine.cpu.reset_stack_pointer();
		for (size_t i = 0; i < args.size(); ++i) {
			machine.cpu.reg(riscv::REG_ARG0 + static_cast<int>(i)) =
				static_cast<gaddr_t>(args[i]);
		}
		machine.cpu.reg(riscv::REG_RA) = machine.memory.exit_address();
		program.pending = false;
		program.fuel = fuel;
		machine.simulate_with<true>(fuel, 0u, funcAddr);
		return program_finish(env, program);
	} catch (const riscv::MachineException& e) {
		return fine::encode(env, fine::Error(machineExceptionToAtom(e)));
	} catch (const std::exception&) {
		return fine::encode(env, fine::Error(fine::Atom("guest_trap")));
	}
}

FINE_NIF(program_call_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Term program_resume_nif(ErlNifEnv* env, fine::ResourcePtr<ProgramResource> resource,
                              int64_t result) {
	ProgramResource& program = *resource;
	Machine64& machine = *program.machine;
	try {
		if (!program.pending) {
			return fine::encode(env, fine::Error(fine::Atom("not_pending")));
		}
		program.pending = false;
		// Depending on where libriscv's dispatch loop stopped, the PC may
		// still point AT the ecall (which would re-execute it) - skip past
		// it if so. Robust against either stop-point behavior.
		if (machine.cpu.pc() == program.pending_pc) {
			machine.cpu.jump(program.pending_pc + 4);
		}
		machine.cpu.reg(riscv::REG_ARG0) = static_cast<gaddr_t>(result);
		machine.simulate_with<true>(program.fuel, 0u, machine.cpu.pc());
		return program_finish(env, program);
	} catch (const riscv::MachineException& e) {
		return fine::encode(env, fine::Error(machineExceptionToAtom(e)));
	} catch (const std::exception&) {
		return fine::encode(env, fine::Error(fine::Atom("guest_trap")));
	}
}

FINE_NIF(program_resume_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND);

} // namespace

FINE_INIT("Elixir.WeftWarpBurrito.SandboxNif");
