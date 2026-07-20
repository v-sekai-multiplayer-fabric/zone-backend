// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee

#include "sketch_core_ffi.h"

#include <cstring>

#if defined(_WIN32)
// Lean's generated IR references a handful of Init module-level DATA
// constants (closed terms). Lean's Windows DLLs are MinGW-built; MinGW's
// linker auto-imports data symbols from DLLs, but this project links with
// lld-link (MSVC ABI), which only auto-imports functions - so those data
// references come up unresolved. Define local equivalents here, initialized
// in sketchCoreShimInit() exactly the way Init's own IR initializer builds
// them (single-field structures erase to their field's boxed value).
// If a future Lean-core change trips a new "undefined symbol: l_..." link
// error, extend this list the same way.
extern "C" {
lean_object* l_ByteArray_empty;
lean_object* l_instInhabitedUInt8;
lean_object* l_instInhabitedUInt32;
lean_object* l_instInhabitedUInt64;
lean_object* l_instInhabitedFloat;
}

void sketchCoreShimInit() {
	l_ByteArray_empty = lean_alloc_sarray(1, 0, 0);
	lean_mark_persistent(l_ByteArray_empty);
	l_instInhabitedUInt8 = lean_box(0);
	l_instInhabitedUInt32 = lean_box_uint32(0);
	lean_mark_persistent(l_instInhabitedUInt32);
	l_instInhabitedUInt64 = lean_box_uint64(0);
	lean_mark_persistent(l_instInhabitedUInt64);
	l_instInhabitedFloat = lean_box_float(0.0);
	lean_mark_persistent(l_instInhabitedFloat);
}
#else
void sketchCoreShimInit() {}
#endif

namespace {

lean_object* toLeanBytes(const uint8_t* data, size_t len) {
	lean_object* ba = lean_alloc_sarray(1, len, len);
	if (len > 0) {
		memcpy(lean_sarray_cptr(ba), data, len);
	}
	return ba;
}

} // namespace

bool sketchCoreApplyPacket(uint64_t roomId, const uint8_t* data, size_t len) {
	lean_object* res = sketch_apply_packet(roomId, toLeanBytes(data, len));
	if (!lean_io_result_is_ok(res)) {
		lean_dec_ref(res);
		return false;
	}
	uint8_t accepted = lean_unbox(lean_io_result_get_value(res));
	lean_dec_ref(res);
	return accepted == 1;
}

std::vector<std::vector<uint8_t>> sketchCoreHistory(uint64_t roomId) {
	std::vector<std::vector<uint8_t>> out;
	lean_object* res = sketch_history_count(roomId);
	if (!lean_io_result_is_ok(res)) {
		lean_dec_ref(res);
		return out;
	}
	uint32_t count = lean_unbox_uint32(lean_io_result_get_value(res));
	lean_dec_ref(res);
	out.reserve(count);
	for (uint32_t i = 0; i < count; i++) {
		lean_object* pres = sketch_history_packet(roomId, i);
		if (!lean_io_result_is_ok(pres)) {
			lean_dec_ref(pres);
			continue;
		}
		lean_object* ba = lean_io_result_get_value(pres);
		const uint8_t* p = lean_sarray_cptr(ba);
		size_t n = lean_sarray_size(ba);
		out.emplace_back(p, p + n);
		lean_dec_ref(pres);
	}
	return out;
}

std::string sketchCoreGraphJson(uint64_t roomId) {
	lean_object* res = sketch_graph_json(roomId);
	if (!lean_io_result_is_ok(res)) {
		lean_dec_ref(res);
		return std::string();
	}
	std::string s(lean_string_cstr(lean_io_result_get_value(res)));
	lean_dec_ref(res);
	return s;
}
