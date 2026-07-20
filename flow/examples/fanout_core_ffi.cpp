// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee

#include "fanout_core_ffi.h"

#include <cstdio>
#include <cstdlib>

// Second Lean package linked into the same process; its module initializer
// must run inside the same runtime-initialization window as fanoutcore's
// (before lean_io_mark_end_initialization), so it is registered here.
extern "C" lean_object* initialize_sketchcore_SketchCore(uint8_t builtin);
void sketchCoreShimInit(); // see sketch_core_ffi.cpp

void fanoutCoreInitialize(uint32_t roomCapacity) {
	lean_initialize_runtime_module();
	lean_object* res = initialize_fanoutcore_Fanoutcore(1);
	if (!lean_io_result_is_ok(res)) {
		lean_io_result_show_error(res);
		fprintf(stderr, "fanout-core: Lean module initialization failed\n");
		abort();
	}
	lean_dec_ref(res);
	sketchCoreShimInit();
	res = initialize_sketchcore_SketchCore(1);
	if (!lean_io_result_is_ok(res)) {
		lean_io_result_show_error(res);
		fprintf(stderr, "sketch-core: Lean module initialization failed\n");
		abort();
	}
	lean_dec_ref(res);
	lean_init_task_manager();
	lean_io_mark_end_initialization();

	res = fanout_init(roomCapacity);
	if (!lean_io_result_is_ok(res)) {
		lean_io_result_show_error(res);
		fprintf(stderr, "fanout-core: fanout_init failed\n");
		abort();
	}
	lean_dec_ref(res);

	// One starting zone spanning the *entire real Hilbert curve range* at
	// this project's quantization depth (Fanoutcore.lean's `zoneBits = 21`
	// interleaves to 3*21 = 63 curve-index bits, i.e. [0, 2^63)) - not the
	// full uint64 range: `2^63` is itself a genuine octree cell (depth 0,
	// the root, per Partition.lean's `zoneRangeDepth`/`octreeChildren`),
	// while 2^64-1 is not a power of 8 at all, which silently made
	// `maybeSplitZone`/`maybeMergeSiblings` treat this bootstrap zone as
	// un-splittable (a real bug: `octreeChildren` returns `none` for any
	// non-octree-aligned range, so this default zone would never split in
	// production regardless of population). AV1-style split/merge
	// (ZoneDispatch.lean's `maybeSplitZone`/`maybeMergeSiblings`, wired
	// into `fanout_entity_move`/`fanout_entity_remove`) partitions this
	// starting zone as population accumulates, bounding each zone's live
	// population by cost (Partition.lean's `splitIsCheaper`) rather than
	// leaving every entity in one ever-growing zone regardless of count -
	// this single starting zone is the only *fixed* one; how many exist
	// after that is dynamic.
	res = fanout_zone_alloc(0, 1ULL << 63);
	if (!lean_io_result_is_ok(res)) {
		lean_io_result_show_error(res);
		fprintf(stderr, "fanout-core: fanout_zone_alloc (default zone) failed\n");
		abort();
	}
	lean_dec_ref(res);
}
