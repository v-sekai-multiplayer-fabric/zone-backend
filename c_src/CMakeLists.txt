# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Standalone verification for guest/weft_guest.elf, plus the actual
# NIF shared library the Elixir GenServer loads. No engine/Godot build
# involved - libriscv::Machine is a pure host-side C++ library, fully
# testable on its own (same principle the weft-warp-loop session this
# was ported from already proved for the fabric-godot-core Sandbox
# port).
cmake_minimum_required(VERSION 3.20)
project(weft_warp_burrito_native CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# libriscv is linked into weft_sandbox_nif, a SHARED library - on ELF/Linux
# (unlike the PE/Windows DLLs this build was originally proved on) every
# object folded into a shared object must be position-independent, or the
# final link fails with "can not be used when making a shared object".
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(RISCV_32I OFF CACHE BOOL "" FORCE)
set(RISCV_64I ON CACHE BOOL "" FORCE)
set(RISCV_BINARY_TRANSLATION OFF CACHE BOOL "" FORCE)
add_subdirectory(thirdparty/libriscv/lib)
# s7_init() alone needs more heap than libriscv's 1MB default - see
# weft-warp-loop/flow-toolchain/CMakeLists.txt's own identical comment
# for the malloc-returns-NULL protection-fault history this fixes.
target_compile_definitions(riscv PUBLIC RISCV_BRK_MEMORY_SIZE=134217728ull)
# The host-math ecall (RFD 0018) lives at 600, past godot-sandbox's
# 500-549 block; libriscv's default syscall table caps at 512. PUBLIC:
# the table size is baked into Machine's layout, so every consumer must
# agree.
target_compile_definitions(riscv PUBLIC RISCV_SYSCALLS_MAX=1024)
if(WIN32)
  target_compile_definitions(riscv PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
endif()

add_executable(verify_guest host_test/verify_guest.cpp)
target_link_libraries(verify_guest PRIVATE riscv)

# Stage 0 of the s7 (Lisp-1) -> RISC-V compiler roadmap (docs/decisions):
# proves the ir -> riscv_codegen -> elf_builder pipeline produces a working
# RISC-V ELF with zero external cross-compiler (no riscv-none-elf-gcc)
# involved. c_src/s7/ is our ahead-of-time compiler for the s7 Scheme
# dialect; c_src/thirdparty/s7/ is the upstream s7 interpreter the guest
# currently embeds -- same language, two execution strategies.
set(S7_COMPILER_SOURCES
  s7/reader.cpp
  s7/codegen.cpp
  s7/ir_interpreter.cpp
  s7/riscv_codegen.cpp
  s7/elf_builder.cpp
  s7/compiler.cpp
)

add_executable(verify_s7 host_test/verify_s7.cpp ${S7_COMPILER_SOURCES})
target_link_libraries(verify_s7 PRIVATE riscv)

# Standalone CLI: compile .scm to a RISC-V ELF (and optionally execute
# it in libriscv) outside the test harness or any BEAM involvement.
add_executable(s7c s7/s7c.cpp ${S7_COMPILER_SOURCES})
target_link_libraries(s7c PRIVATE riscv)

# The actual NIF the Elixir GenServer loads. ERTS_INCLUDE_DIR is passed
# in by c_src/Makefile (elixir_make's entry point) - not hardcoded,
# since it depends on the Erlang install on whatever machine builds
# this. No erl_interface/erts import-lib linkage is needed: on both
# Windows and Unix, a NIF is a plain shared library the BEAM loads via
# dlopen/LoadLibrary and resolves nif_init from by symbol name.
if(DEFINED ERTS_INCLUDE_DIR)
  add_library(weft_sandbox_nif SHARED nif/weft_sandbox_nif.cpp)
  target_include_directories(weft_sandbox_nif PRIVATE ${ERTS_INCLUDE_DIR} ${FINE_INCLUDE_DIR})
  target_link_libraries(weft_sandbox_nif PRIVATE riscv)
  set_target_properties(weft_sandbox_nif PROPERTIES PREFIX "")
  # Fine's own README: hides NIF symbols so this library doesn't clash
  # with other Fine-based NIFs loaded into the same BEAM node.
  if(NOT MSVC)
    target_compile_options(weft_sandbox_nif PRIVATE -fvisibility=hidden)
  endif()
endif()
