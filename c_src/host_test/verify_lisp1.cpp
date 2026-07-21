// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 0 proof: compile the fixed program `(+ 1 2)` through
// lisp1::compile_stage0() (ir -> riscv_codegen -> elf_builder, no
// riscv-none-elf-gcc involved at all), load the resulting bytes directly
// into libriscv::Machine, and confirm calling the compiled function
// returns 3. No NIF/Elixir/BEAM involved -- same standalone-proof shape
// as host_test/verify_guest.cpp.
#include <cstdio>
#include <cstdlib>

#include <libriscv/machine.hpp>

#include "../lisp1/compiler.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;

int main() {
  const std::string func_name = "lisp1_add_1_2";
  std::vector<uint8_t> elf_bytes = lisp1::compile_stage0(func_name);

  printf("compiled %s to a %zu-byte ELF\n", func_name.c_str(), elf_bytes.size());

  int64_t result = -1;
  try {
    Machine64 machine(elf_bytes, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
    result = static_cast<int64_t>(machine.vmcall<1'000'000ull>(func_name.c_str()));
  } catch (const std::exception& e) {
    fprintf(stderr, "FAIL: exception: %s\n", e.what());
    return 1;
  }

  printf("%s() = %lld\n", func_name.c_str(), static_cast<long long>(result));

  if (result != 3) {
    fprintf(stderr, "FAIL: expected 3, got %lld\n", static_cast<long long>(result));
    return 1;
  }

  printf("PASS: Stage 0 compiler pipeline (ir -> riscv_codegen -> elf_builder) works end to end\n");
  return 0;
}
