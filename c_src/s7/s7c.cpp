// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// s7c: standalone s7-subset -> RISC-V ELF compiler CLI (the same
// pipeline verify_s7 exercises, usable outside the test harness --
// analogous to the reference project's gdscript_to_riscv tool).
//
//   s7c input.scm -o out.elf          compile to a RISC-V ELF
//   s7c input.scm --run main [ints]   compile, execute in libriscv,
//                                     print the decoded result
//   s7c input.scm --dump-ir           print the lowered IR
#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

#include "compiler.h"
#include "host_math.h"
#include "ir_interpreter.h"
#include "value.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;

namespace {

const char* op_name(s7::Op op) {
  switch (op) {
    case s7::Op::LOAD_IMM: return "load_imm";
    case s7::Op::MOVE: return "move";
    case s7::Op::ADD: return "add";
    case s7::Op::SUB: return "sub";
    case s7::Op::MUL: return "mul";
    case s7::Op::DIV: return "div";
    case s7::Op::REM: return "rem";
    case s7::Op::AND: return "and";
    case s7::Op::OR: return "or";
    case s7::Op::XOR: return "xor";
    case s7::Op::SLL: return "sll";
    case s7::Op::SRA: return "sra";
    case s7::Op::SLT: return "slt";
    case s7::Op::EQZ: return "eqz";
    case s7::Op::LABEL: return "label";
    case s7::Op::JUMP: return "jump";
    case s7::Op::BRANCH_ZERO: return "branch_zero";
    case s7::Op::CALL: return "call";
    case s7::Op::RETURN: return "return";
    case s7::Op::ALLOC: return "alloc";
    case s7::Op::LOAD_MEM: return "load_mem";
    case s7::Op::STORE_MEM: return "store_mem";
    case s7::Op::LOAD_FUNC_ADDR: return "load_func_addr";
    case s7::Op::CALL_INDIRECT: return "call_indirect";
    case s7::Op::CHECKED_ADD: return "checked_add";
    case s7::Op::CHECKED_SUB: return "checked_sub";
    case s7::Op::CHECKED_MUL: return "checked_mul";
    case s7::Op::CHECKED_QUOT: return "checked_quot";
    case s7::Op::CHECKED_REM: return "checked_rem";
    case s7::Op::CHECKED_LT: return "checked_lt";
    case s7::Op::CHECKED_EQ: return "checked_eq";
  }
  return "?";
}

void dump_ir(const s7::IRProgram& program) {
  for (const s7::IRFunction& fn : program.functions) {
    printf("%s/%d (%d vregs)\n", fn.name.c_str(), fn.num_params, fn.num_vregs);
    for (const s7::Instr& in : fn.instrs) {
      printf("  %-15s dst=%-3d a=%-3d b=%-3d imm=%" PRId64 " label=%d callee=%d",
             op_name(in.op), in.dst, in.a, in.b, in.imm, in.label, in.callee);
      if (!in.args.empty()) {
        printf(" args=[");
        for (size_t i = 0; i < in.args.size(); ++i) printf("%s%d", i ? " " : "", in.args[i]);
        printf("]");
      }
      printf("\n");
    }
  }
}

void print_value(int64_t tagged) {
  if ((tagged & 7) == 0) {
    printf("%" PRId64 "\n", tagged >> 3);
  } else if (tagged == s7::kTrue) {
    printf("#t\n");
  } else if (tagged == s7::kFalse) {
    printf("#f\n");
  } else if (tagged == s7::kNil) {
    printf("()\n");
  } else if ((tagged & 7) == s7::kHandleTag) {
    printf("#<bignum handle %" PRId64 ">\n", tagged >> 3);
  } else if ((tagged & 7) == s7::kClosureTag) {
    printf("#<closure>\n");
  } else {
    printf("#<unknown %" PRId64 ">\n", tagged);
  }
}

int usage() {
  fprintf(stderr,
          "usage: s7c <input.scm> [-o <out.elf>] [--run <entry> [int-args...]] [--dump-ir]\n");
  return 2;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) return usage();
  std::string input_path = argv[1];
  std::string output_path;
  std::string run_entry;
  std::vector<int64_t> run_args;
  bool want_dump_ir = false;

  for (int i = 2; i < argc; ++i) {
    if (std::strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
      output_path = argv[++i];
    } else if (std::strcmp(argv[i], "--dump-ir") == 0) {
      want_dump_ir = true;
    } else if (std::strcmp(argv[i], "--run") == 0 && i + 1 < argc) {
      run_entry = argv[++i];
      while (i + 1 < argc) run_args.push_back(s7::tag_fixnum(std::atoll(argv[++i])));
    } else {
      return usage();
    }
  }

  std::ifstream in(input_path, std::ios::binary);
  if (!in) {
    fprintf(stderr, "s7c: cannot open %s\n", input_path.c_str());
    return 1;
  }
  std::ostringstream buf;
  buf << in.rdbuf();

  try {
    s7::Compiled compiled = s7::compile(buf.str());

    if (want_dump_ir) dump_ir(compiled.ir);

    if (!output_path.empty()) {
      std::ofstream out(output_path, std::ios::binary);
      out.write(reinterpret_cast<const char*>(compiled.elf.data()),
                static_cast<std::streamsize>(compiled.elf.size()));
      if (!out) {
        fprintf(stderr, "s7c: cannot write %s\n", output_path.c_str());
        return 1;
      }
      fprintf(stderr, "s7c: wrote %zu-byte ELF to %s\n", compiled.elf.size(),
              output_path.c_str());
    }

    if (!run_entry.empty()) {
      Machine64::install_syscall_handler(
          static_cast<size_t>(s7::kSyscallHostMath), [](Machine64& machine) {
            auto* table = machine.get_userdata<s7::HostBignumTable>();
            auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
            machine.set_result(table->apply(op, a, b));
          });
      Machine64 machine(compiled.elf,
                        riscv::MachineOptions<riscv::RISCV64>{.memory_max = 64UL << 20});
      s7::HostBignumTable table;
      machine.set_userdata(&table);
      int64_t result = 0;
      switch (run_args.size()) {
        case 0: result = static_cast<int64_t>(machine.vmcall<500'000'000ull>(run_entry.c_str())); break;
        case 1:
          result = static_cast<int64_t>(
              machine.vmcall<500'000'000ull>(run_entry.c_str(), run_args[0]));
          break;
        case 2:
          result = static_cast<int64_t>(
              machine.vmcall<500'000'000ull>(run_entry.c_str(), run_args[0], run_args[1]));
          break;
        default:
          fprintf(stderr, "s7c: --run supports at most 2 arguments for now\n");
          return 1;
      }
      print_value(result);
    }

    if (output_path.empty() && run_entry.empty() && !want_dump_ir) {
      fprintf(stderr, "s7c: compiled OK (%zu-byte ELF); use -o/--run/--dump-ir\n",
              compiled.elf.size());
    }
    return 0;
  } catch (const std::exception& e) {
    fprintf(stderr, "s7c: %s\n", e.what());
    return 1;
  }
}
