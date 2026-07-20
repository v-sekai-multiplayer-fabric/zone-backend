// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// C declarations for the fanout-core Lean4 kernel's exported functions
// (flow-toolchain/fanout-core/Fanoutcore/Ffi.lean). Every exported IO
// function returns a `lean_io_result` object; Lean4 elides the IO world
// token at this optimization level, so there is no explicit world argument.

#pragma once

#include <lean/lean.h>
#include <stdint.h>

// lean.h includes C11's <stdnoreturn.h>, which #defines `noreturn` to
// `_Noreturn`. On Windows that macro corrupts every later `__declspec(noreturn)`
// in the UCRT/SDK headers, so drop it once lean.h has been parsed.
#ifdef noreturn
#undef noreturn
#endif

extern "C" {
void lean_initialize_runtime_module(void);
lean_object* initialize_fanoutcore_Fanoutcore(uint8_t builtin);

lean_object* fanout_init(uint32_t capacity);
lean_object* fanout_alloc_room(void);
lean_object* fanout_free_room(uint64_t room_id);
lean_object* fanout_sub(uint64_t room_id, uint64_t conn_id);
lean_object* fanout_unsub(uint64_t room_id, uint64_t conn_id);
lean_object* fanout_pub_targets(uint64_t room_id, uint64_t publisher_conn_id);

// Zone-authority/interest dispatch (ADR 0008, Fanoutcore/Zone.lean +
// ZoneDispatch.lean), additive to the Room/SUB/PUB exports above.
lean_object* fanout_zone_alloc(uint64_t start_idx, uint64_t stop_idx);
lean_object* fanout_zone_free(uint64_t zone_id);
lean_object* fanout_entity_move(uint64_t conn_id, int64_t x, int64_t y, int64_t z);
// Velocity (vx/vy/vz: micrometres/tick, magnitude per axis, direction
// discarded, matching Fanoutcore.EntityRecord's convention) and
// RTT-derived lookahead window (rtt_ticks: 0 means no sample yet, falls
// back to defaultLookaheadTicks) for k-tick ghost expansion
// (Fanoutcore/Zone.lean's withinGhostRange).
lean_object* fanout_entity_move_v(uint64_t conn_id, int64_t x, int64_t y, int64_t z, uint64_t vx, uint64_t vy,
                                   uint64_t vz, uint64_t rtt_ticks);
lean_object* fanout_entity_remove(uint64_t conn_id);
lean_object* fanout_zone_targets(uint64_t publisher_conn_id, int64_t x, int64_t y, int64_t z);
}

constexpr uint64_t FANOUT_CORE_SENTINEL = 0xFFFFFFFFFFFFFFFFULL;

// Runs the fanout-core's init sequence once per process. Aborts the
// process on failure: there is no recovery from the Lean runtime failing
// to initialize.
void fanoutCoreInitialize(uint32_t roomCapacity);
