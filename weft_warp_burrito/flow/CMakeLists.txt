cmake_minimum_required(VERSION 3.20)
project(weft_warp_burrito_flow_runtime CXX C ASM)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Threads REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
find_package(OpenSSL REQUIRED)
find_package(fmt REQUIRED)

if(WIN32)
  find_package(Boost 1.86.0 REQUIRED
    COMPONENTS filesystem iostreams serialization system program_options url
    CONFIG)
  add_library(boost_target INTERFACE)
  target_link_libraries(boost_target INTERFACE
    Boost::boost Boost::filesystem Boost::iostreams Boost::serialization
    Boost::system Boost::url)
else()
  find_package(Boost 1.86.0 REQUIRED
    COMPONENTS context filesystem iostreams program_options serialization system url
    CONFIG)
  add_library(boost_target INTERFACE)
  target_link_libraries(boost_target INTERFACE
    Boost::boost Boost::context Boost::filesystem Boost::iostreams
    Boost::serialization Boost::system Boost::url)
endif()

# --- contrib sibling libraries (vendored from apple/foundationdb's contrib/) ---
add_subdirectory(contrib/SimpleOpt)
add_subdirectory(contrib/libb64)
add_subdirectory(contrib/stacktrace)
add_subdirectory(contrib/crc32)
if(UNIX AND NOT APPLE)
  add_subdirectory(contrib/folly_memcpy)
endif()

# --- codegen: ApiVersion.h / SourceVersion.h / config.h ---
set(CODEGEN_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/include")
file(MAKE_DIRECTORY "${CODEGEN_INCLUDE_DIR}/flow")

include(flow/ApiVersions.cmake)
set(CURRENT_GIT_VERSION "weft-warp-loop-extraction")
# config.h.cmake defines _WIN32_WINNT/WINVER from this; an unset value leaves
# both macros defined-but-empty, which breaks every "#if _WIN32_WINNT >= ..."
# check in the Windows SDK headers. 0x0600 = Vista, matching upstream FDB.
set(WINDOWS_TARGET 0x0600)
# The same values as command-line defines - see the target_compile_definitions
# comment below for why config.h alone is not enough on Windows.
set(WINDOWS_TARGET_DEFS _WIN32_WINNT=${WINDOWS_TARGET} WINVER=${WINDOWS_TARGET} NTDDI_VERSION=0x06000000)
include(CheckSymbolExists)
check_symbol_exists(aligned_alloc "stdlib.h" HAS_ALIGNED_ALLOC)
configure_file(flow/ApiVersion.h.cmake "${CODEGEN_INCLUDE_DIR}/flow/ApiVersion.h")
configure_file(flow/SourceVersion.h.cmake "${CODEGEN_INCLUDE_DIR}/flow/SourceVersion.h")
configure_file(flow/config.h.cmake "${CODEGEN_INCLUDE_DIR}/flow/config.h")

# --- codegen: ProtocolVersion.h (Python + Jinja2) ---
set(PROTOCOL_VERSION_HEADER "${CODEGEN_INCLUDE_DIR}/flow/ProtocolVersion.h")
add_custom_command(
  OUTPUT "${PROTOCOL_VERSION_HEADER}"
  COMMAND ${Python3_EXECUTABLE}
          "${CMAKE_CURRENT_SOURCE_DIR}/flow/protocolversion/protocol_version.py"
          --source "${CMAKE_CURRENT_SOURCE_DIR}/flow/ProtocolVersions.cmake"
          --generator cpp
          --output "${PROTOCOL_VERSION_HEADER}"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/flow/protocolversion/protocol_version.py"
          "${CMAKE_CURRENT_SOURCE_DIR}/flow/ProtocolVersions.cmake"
  COMMENT "Generating ProtocolVersion.h")
add_custom_target(ProtocolVersion DEPENDS "${PROTOCOL_VERSION_HEADER}")

# --- actor-compiler: transform .actor.cpp -> .g.cpp (our vendored Python port) ---
set(ACTORCOMPILER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/actorcompiler")
set(ACTOR_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/actor-gen")
file(MAKE_DIRECTORY "${ACTOR_GEN_DIR}")

function(compile_actor_file actor_src out_var)
  get_filename_component(actor_name "${actor_src}" NAME_WE)
  set(generated "${ACTOR_GEN_DIR}/${actor_name}.g.cpp")
  add_custom_command(
    OUTPUT "${generated}"
    COMMAND ${Python3_EXECUTABLE} -m actorcompiler "${actor_src}" "${generated}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS "${actor_src}"
            "${ACTORCOMPILER_DIR}/__main__.py"
            "${ACTORCOMPILER_DIR}/actor_compiler.py"
            "${ACTORCOMPILER_DIR}/actor_parser.py"
            "${ACTORCOMPILER_DIR}/parse_tree.py"
            "${ACTORCOMPILER_DIR}/errors.py"
    COMMENT "actorcompiler: ${actor_name}.actor.cpp -> ${actor_name}.g.cpp")
  set(${out_var} "${generated}" PARENT_SCOPE)
endfunction()

compile_actor_file("${CMAKE_CURRENT_SOURCE_DIR}/flow/ActorCollection.actor.cpp" ACTOR_COLLECTION_GEN)
compile_actor_file("${CMAKE_CURRENT_SOURCE_DIR}/flow/genericactors.actor.cpp" GENERIC_ACTORS_GEN)

# genericactors.actor.h (a header, not a .cpp) has its own raw ACTOR/state/choose
# syntax; anything compiled with POST_ACTOR_COMPILER set (i.e. every actor-
# generated .g.cpp above) needs the transformed flow/genericactors.actor.g.h
# this header's own #include falls back to, or the untransformed syntax fails
# to parse - actorcompiler.h's IDE-only fallback macros are deliberately
# suppressed whenever POST_ACTOR_COMPILER is set.
set(GENERICACTORS_H_GEN_DIR "${ACTOR_GEN_DIR}/include/flow")
file(MAKE_DIRECTORY "${GENERICACTORS_H_GEN_DIR}")
set(GENERICACTORS_H_GEN "${GENERICACTORS_H_GEN_DIR}/genericactors.actor.g.h")
add_custom_command(
  OUTPUT "${GENERICACTORS_H_GEN}"
  COMMAND ${Python3_EXECUTABLE} -m actorcompiler
          "${CMAKE_CURRENT_SOURCE_DIR}/flow/include/flow/genericactors.actor.h" "${GENERICACTORS_H_GEN}"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/flow/include/flow/genericactors.actor.h"
          "${ACTORCOMPILER_DIR}/__main__.py"
          "${ACTORCOMPILER_DIR}/actor_compiler.py"
          "${ACTORCOMPILER_DIR}/actor_parser.py"
          "${ACTORCOMPILER_DIR}/parse_tree.py"
          "${ACTORCOMPILER_DIR}/errors.py"
  COMMENT "actorcompiler: genericactors.actor.h -> genericactors.actor.g.h")
add_custom_target(GenericActorsHeader DEPENDS "${GENERICACTORS_H_GEN}")

# --- flow library sources (plain .cpp, actor-generated files added separately) ---
file(GLOB FLOW_SRCS CONFIGURE_DEPENDS "flow/*.cpp")
list(REMOVE_ITEM FLOW_SRCS
  "${CMAKE_CURRENT_SOURCE_DIR}/flow/ActorCollection.actor.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/flow/genericactors.actor.cpp")
list(APPEND FLOW_SRCS "${ACTOR_COLLECTION_GEN}" "${GENERIC_ACTORS_GEN}")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
  list(APPEND FLOW_SRCS flow/aarch64/memcmp.S flow/aarch64/memcpy.S)
endif()

add_library(flow STATIC ${FLOW_SRCS})
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  # clang's optimizer segfaults (ICE in the jump-threading pass) on the
  # UDPSocket::connect coroutine in Net2.cpp: clang 22 at /O2, clang 20 (the
  # GitHub runner's LLVM) even at /O1. Compile just this TU at -O0 - the
  # later option wins, so appending is enough. weft-warp-loop's own copy
  # of this rule uses "/Od" (cl-style), which assumes a clang-cl driver;
  # this repo's toolchain is llvm-mingw's plain GNU-style clang++, which
  # doesn't understand "/Od" (errors as "no such file or directory: '/Od'"
  # since it's parsed as a positional arg, not a flag) - -O0 is the same
  # thing under the GNU-style command-line clang++ actually uses here.
  set_source_files_properties(flow/Net2.cpp PROPERTIES COMPILE_OPTIONS "-O0")
endif()
add_dependencies(flow ProtocolVersion GenericActorsHeader)

target_include_directories(flow PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/flow/include"
  "${CODEGEN_INCLUDE_DIR}"
  "${ACTOR_GEN_DIR}/include"
  PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/flow")

# genericactors.actor.h's raw ACTOR/state/choose syntax only compiles two
# ways: actorcompiler.h's IDE-only no-op macros (raw source, no
# POST_ACTOR_COMPILER), or the actor-compiler-generated genericactors.actor.g.h
# above (real build). NO_INTELLISENSE selects the latter unconditionally, so
# every flow consumer - not just the two actor-generated .g.cpp files that
# define POST_ACTOR_COMPILER themselves - gets the same, real, transformed code.
target_compile_definitions(flow PUBLIC NO_INTELLISENSE)

target_link_libraries(flow
  PUBLIC boost_target OpenSSL::SSL fmt::fmt Threads::Threads SimpleOpt crc32 libb64
  PRIVATE stacktrace)

if(UNIX AND NOT APPLE)
  target_link_libraries(flow PRIVATE folly_memcpy)
  target_compile_definitions(flow PRIVATE WITH_FOLLY_MEMCPY)
endif()

if(WIN32)
  target_link_libraries(flow PUBLIC winmm.lib psapi.lib)
elseif(NOT APPLE)
  target_link_libraries(flow PUBLIC rt)
endif()

if(APPLE)
  find_library(IO_KIT IOKit)
  find_library(CORE_FOUNDATION CoreFoundation)
  target_link_libraries(flow PUBLIC ${IO_KIT} ${CORE_FOUNDATION})
endif()

target_compile_definitions(flow PUBLIC BOOST_ERROR_CODE_HEADER_ONLY BOOST_SYSTEM_NO_DEPRECATED)
if(WIN32)
  # MSVC's <cmath> only exposes M_E/M_PI/etc. when this is defined before the
  # first inclusion; a header-level #define is unreliable since fmt or Boost
  # headers can pull in <cmath> before flow's own headers are ever reached.
  #
  # _WIN32_WINNT must come from the command line, not flow/config.h: TUs like
  # Net2.cpp include boost/asio headers *before* any flow header, and Boost.Asio
  # self-defaults _WIN32_WINNT (to 0x0601) when unset. flow/config.h sets 0x0600
  # for TUs that include flow first (e.g. IThreadPool.cpp), so the same asio
  # inline code gets instantiated under two different Windows targets, and the
  # linker folds the incompatible copies - at runtime the io_context service
  # registry then rejects its own services with "Invalid service owner".
  target_compile_definitions(flow PUBLIC _USE_MATH_DEFINES ${WINDOWS_TARGET_DEFS})
endif()

# --- weft_flow_hello: minimal standalone proof the vendored Flow actor
# runtime actually builds and runs here (RFD 5) - not linked against
# libriscv/s7/fanout-core/picoquic, none of which this minimal vendoring
# copied. See examples/weft_flow_hello.actor.cpp for what it proves.
compile_actor_file("${CMAKE_CURRENT_SOURCE_DIR}/examples/weft_flow_hello.actor.cpp" WEFT_FLOW_HELLO_GEN)
add_executable(weft_flow_hello "${WEFT_FLOW_HELLO_GEN}")
target_link_libraries(weft_flow_hello PRIVATE flow)

# --- weft_flow_cnode: RFD 5's other half - proves an erl_interface/ei C
# Node can register as a real peer on the Erlang distribution protocol
# and exchange messages with a live BEAM node, the bridge mechanism a
# BEAM consumer (e.g. taskweft) uses to reach the independently-running
# Flow core (a NIF can't be a persistent run loop; see RFD 5). Not
# linked against `flow` itself yet - this only proves the C Node
# mechanism; wiring Flow's own run loop behind it is later work.
if(WIN32)
  execute_process(
    COMMAND erl -eval "io:format(\"~s\", [code:lib_dir(erl_interface)])" -s init stop -noshell
    OUTPUT_VARIABLE ERL_INTERFACE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(ERL_INTERFACE_DIR)
    add_executable(weft_flow_cnode examples/cnode/weft_flow_cnode.cpp)
    target_include_directories(weft_flow_cnode PRIVATE "${ERL_INTERFACE_DIR}/include")
    # __WIN32__ (not the standard _WIN32/WIN32 clang/mingw already define):
    # erl_interface's own ei.h gates its ssize_t typedef and winsock includes
    # on this exact macro, which only Erlang's own (MSVC-based) build system
    # defines by default - clang/llvm-mingw never sets it, so without this
    # define ei.h fails with "unknown type name 'ssize_t'".
    target_compile_definitions(weft_flow_cnode PRIVATE __WIN32__)
    target_link_libraries(weft_flow_cnode PRIVATE "${ERL_INTERFACE_DIR}/lib/ei.lib" ws2_32)
  endif()
endif()
