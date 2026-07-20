// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// C declarations for the sketch-core Lean4 kernel's exported functions
// (flow-toolchain/sketch-core/SketchCore/Ffi.lean), plus small C++ helpers
// that hide the lean_object plumbing from the bridge actor. Module
// initialization happens inside fanoutCoreInitialize() (both Lean packages
// share one runtime).

#pragma once

#include <lean/lean.h>
#include <stdint.h>

// lean.h includes C11's <stdnoreturn.h>; see fanout_core_ffi.h.
#ifdef noreturn
#undef noreturn
#endif

#include <string>
#include <vector>

extern "C" {
lean_object* sketch_reset(void);
lean_object* sketch_apply_packet(uint64_t room_id, lean_object* bytes);
lean_object* sketch_history_count(uint64_t room_id);
lean_object* sketch_history_packet(uint64_t room_id, uint32_t i);
lean_object* sketch_graph_json(uint64_t room_id);
}

// Windows-only link shim for non-exported Lean Init data constants; must
// run before initialize_sketchcore_SketchCore. No-op elsewhere.
void sketchCoreShimInit();

// Apply an inbound CSP1 packet to a room. Returns true when the packet is
// valid + fresh (i.e. should be relayed to the room's subscribers).
bool sketchCoreApplyPacket(uint64_t roomId, const uint8_t* data, size_t len);

// The room's accepted packet history, for late-join replay.
std::vector<std::vector<uint8_t>> sketchCoreHistory(uint64_t roomId);

// Canonical sketch-graph JSON for a room (convergence artifact).
std::string sketchCoreGraphJson(uint64_t roomId);
