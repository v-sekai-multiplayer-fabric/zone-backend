// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Real capability guests for the fabric-godot-core Sandbox port (see
// plan: "Port weft-warp-loop's s7-Lisp-1-in-libriscv scripting system
// into a fabric-godot-core module"). Exposes one named, fixed entry
// point per capability, matching Sandbox::vmcall(function_name,
// args...)'s own convention - deliberately NOT a generic string-eval
// entry point, since that would let any GDScript caller inject
// arbitrary code to run at this guest's trust level.
//
// guest_loot_roll(int64_t) -> int64_t needs zero GuestVariant/Variant
// marshalling: Sandbox::vmcall_internal packs plain integer arguments/
// results directly into the standard RV64 calling-convention registers
// for scalar types.
//
// guest_combat_replay() -> Variant (a real Array) is the first proof
// that real Array/Dictionary marshalling works end to end. The wire
// protocol was reverse-engineered from the module's own real source
// this session (program/cpp/api/variant.{hpp,cpp}, array.cpp,
// syscalls.h, src/sandbox_syscalls.cpp - not guessed):
//   - The guest-side Variant struct is exactly {uint32_t type; union
//     v[16 bytes]} = 24 bytes on the default single-precision build,
//     byte-for-byte identical to the host's own GuestVariant
//     (guest_datatypes.h) - a plain C struct with the same field order
//     needs no special packing.
//   - A scalar Variant (INT etc.) is built entirely in guest stack
//     memory by ordinary assignment - no syscall needed.
//   - A complex Variant (Array/Dictionary/String/Object) requires a
//     host round trip: ECALL_VCREATE (syscall number 517) with
//     type=ARRAY, method=<element count>, data=<pointer to that many
//     contiguous 24-byte Variant structs> asks the host to allocate a
//     real Godot Array in its own "scoped variant" table and copy all
//     elements in one call (api_vcreate's method>=0 path,
//     sandbox_syscalls.cpp) - returning {type=ARRAY, v.i=<scoped
//     index>} into the Variant the guest passed as ECALL_VCREATE's own
//     out-parameter.
//   - A guest function returning a bare `Variant` (24 bytes, >16 so it
//     doesn't fit in a0/a1) uses the plain riscv64 lp64d C ABI's
//     hidden-pointer-return convention automatically - the compiler
//     writes the 24 bytes at the address the caller passed in a0, with
//     zero extra guest code needed to participate in this; it's
//     exactly what Sandbox::setup_arguments()/vmcall_internal() already
//     expect (they allocate the return-value GuestVariant in guest
//     memory themselves and read it back from that same address, never
//     from a register).
#include "s7.h"
#include <stdint.h>
#include <unistd.h>

#define GUEST_PUBLIC __attribute__((used, retain))

static s7_scheme *g_sc = NULL;

// -- Guest-side Variant wire type: matches program/cpp/api/variant.hpp
// and src/guest_datatypes.h's GuestVariant byte-for-byte (24 bytes,
// single-precision real_t build). Only the two type tags this file
// actually uses are named; the enum's real numeric ordering (NIL=0,
// BOOL=1, INT=2, FLOAT=3, STRING=4, ... DICTIONARY=27, ARRAY=28) is
// what the host's Variant::Type expects, confirmed against
// program/cpp/api/variant.hpp's own enum listing.
typedef struct {
	uint32_t type;
	union {
		int64_t i;
		double f;
		float v4f[4];
		int32_t v4i[4];
	} v;
} GuestVariant;

#define VT_INT ((uint32_t)2)
#define VT_ARRAY ((uint32_t)28)

// ECALL_VCREATE = GAME_API_BASE(500) + 17, per program/cpp/api/syscalls.h.
// Raw ecall stub, same shape as syscalls.h's own MAKE_SYSCALL macro
// (li a7, N; ecall; ret) - written by hand since this guest doesn't
// include the C++ syscalls.h header.
__asm__(
	".pushsection .text\n"
	".global sys_vcreate\n"
	"sys_vcreate:\n"
	"\tli a7, 517\n"
	"\tecall\n"
	"\tret\n"
	".popsection\n");
extern void sys_vcreate(GuestVariant *out, uint32_t type, int method, const void *data);

static GuestVariant make_int(int64_t x) {
	GuestVariant v;
	v.type = VT_INT;
	v.v.i = x;
	return v;
}

// Generated from content/record-macros.scm + content/combat.scm by
// gen_scm_embed.py - regenerate if either of those change (this file
// is a pinned snapshot, not a live mirror, same discipline as every
// other ported .scm file in this repo - ADR 0032).
#include "combat_embed.h"

// Verbatim from riscv-guests/content/loot.scm (LootCore.Rng.range,
// LootCore.totalWeight, LootCore.pick, LootCore.roll) - not
// reinterpreted, the same line-for-line translation already verified
// against v-sekai-multiplayer-fabric/loot's Lean spec this session.
// s7_eval_c_string reads and evaluates exactly one datum from the
// string - multiple top-level defines need an explicit (begin ...)
// wrapper, the same pattern every other s7_riscv_*_test.cpp in this
// repo already uses (a first version of this file omitted it, and
// only the first define - u32 - actually landed).
static const char *k_loot_scm =
	"(begin"
	"(define (u32 x) (logand x #xFFFFFFFF))"
	"(define (xorshift32-next32 s)"
	"  (let* ((s (u32 (logxor s (u32 (ash s 13)))))"
	"         (s (u32 (logxor s (ash s -17))))"
	"         (s (u32 (logxor s (u32 (ash s 5))))))"
	"    s))"
	"(define (rng-range seed bound)"
	"  (if (= bound 0) 0 (modulo (xorshift32-next32 seed) bound)))"
	"(define (total-weight table)"
	"  (let loop ((t table) (acc 0))"
	"    (if (null? t) acc (loop (cdr t) (+ acc (cdr (car t)))))))"
	"(define (pick table r acc)"
	"  (if (null? table)"
	"      0"
	"      (let* ((entry (car table))"
	"             (item (car entry))"
	"             (w (cdr entry))"
	"             (new-acc (+ acc w)))"
	"        (if (< r new-acc) item (pick (cdr table) r new-acc)))))"
	"(define (loot-roll seed table)"
	"  (let ((tot (total-weight table)))"
	"    (if (= tot 0) 0 (pick table (rng-range seed tot) 0)))))";

void guest_init(void) {
	g_sc = s7_init();
	s7_eval_c_string(g_sc, k_loot_scm);
	s7_eval_c_string(g_sc, k_combat_scm);
}

// The loot table itself is not yet a guest-callable argument (that
// needs real Array marshalling on the *input* side too - a further
// increment) - this capability proves the ABI/loading mechanism
// against a fixed table, matching the existing golden test's own real
// reference vector (loot-roll(42, [(1.10),(2.20),(3.5)]) = 3,
// s7_riscv_loot_golden_test.cpp:45, itself checked against a
// Lean-proven value).
GUEST_PUBLIC
long long guest_loot_roll(long long seed) {
	char expr[160];
	snprintf(expr, sizeof(expr),
		"(loot-roll %lld (list (cons 1 10) (cons 2 20) (cons 3 5)))", seed);
	s7_pointer result = s7_eval_c_string(g_sc, expr);
	return (long long)s7_integer(result);
}

// Runs the exact event sequence s7_riscv_combat_golden_test.cpp's own
// Lean4-verified golden vector uses (spawn, 30 ticks, one opener
// attack -> final enemyHp=90, tick=30) and returns [tick, hp, alive]
// as a real Godot Array Variant - the first proof that real Array
// marshalling works end to end, not just scalars.
GUEST_PUBLIC
GuestVariant guest_combat_replay(void) {
	s7_pointer result = s7_eval_c_string(g_sc,
		"(car (combat-replay (list 'spawn"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'attack)))");

	// result is the final `state` record (a plain vector, per
	// record-macros.scm's define-record: (vector tick combo
	// last-attack hp spawn alive)) - pull out tick/hp/alive by field
	// index, matching define-record's own field order in combat.scm's
	// (define-record state tick combo last-attack hp spawn alive).
	s7_pointer tickV = s7_vector_ref(g_sc, result, 0);
	s7_pointer hpV = s7_vector_ref(g_sc, result, 3);
	s7_pointer aliveV = s7_vector_ref(g_sc, result, 5);

	int64_t tick = s7_integer(tickV);
	int64_t hp = s7_integer(hpV);
	int64_t alive = s7_boolean(g_sc, aliveV) ? 1 : 0;

	GuestVariant elems[3];
	elems[0] = make_int(tick);
	elems[1] = make_int(hp);
	elems[2] = make_int(alive);

	GuestVariant out;
	sys_vcreate(&out, VT_ARRAY, 3, elems);
	return out;
}

int main(void) {
	guest_init();
	// Never `return` from main() - see s7_guest_main.c's own
	// documented libriscv/Flow/OpenSSL global-destructor-ordering
	// crash; _exit() sidesteps it, leaving the interpreter alive in
	// guest memory for repeat vmcalls.
	_exit(0);
}
