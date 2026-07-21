// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// The libriscv guest: an s7 interpreter preloaded with weft-warp-loop's
// already-ported loot/combat/progression content (content_embed.S,
// compile-time .incbin - no runtime "load arbitrary source" entry
// point exists in this binary at all). Exposes one named, fixed
// function per real capability - never a generic eval - matching the
// standing "no generic eval/eval_int, ever" security rule: an actor
// wrapping this guest only ever gets pause (fuel-limited, resumable
// simulate_with) and gas (the fuel budget itself) around a fixed,
// audited set of entry points, never an arbitrary-code channel.
#include "s7.h"
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#define GUEST_PUBLIC __attribute__((used, retain))

extern char g_record_macros_scm[];
extern char g_loot_scm[];
extern char g_combat_scm[];
extern char g_progression_scm[];

static s7_scheme *g_sc = NULL;
static char g_source_buf[20000];

// Struct-return capability results: >16 bytes, so the plain riscv64
// lp64d C ABI passes a hidden pointer in a0 automatically - no manual
// marshalling code needed on either side (same convention already
// proven this session for the fabric-godot-core Sandbox port, just
// with our own struct shape instead of Godot's Variant).
typedef struct {
	int64_t values[4];
	int32_t count;
} GuestResult;

void guest_init(void) {
	g_sc = s7_init();
	size_t n = 0;
	n += (size_t)snprintf(g_source_buf + n, sizeof(g_source_buf) - n, "(begin ");
	n += (size_t)snprintf(g_source_buf + n, sizeof(g_source_buf) - n, "%s", g_record_macros_scm);
	n += (size_t)snprintf(g_source_buf + n, sizeof(g_source_buf) - n, "%s", g_loot_scm);
	n += (size_t)snprintf(g_source_buf + n, sizeof(g_source_buf) - n, "%s", g_combat_scm);
	n += (size_t)snprintf(g_source_buf + n, sizeof(g_source_buf) - n, "%s", g_progression_scm);
	snprintf(g_source_buf + n, sizeof(g_source_buf) - n, ")");
	s7_eval_c_string(g_sc, g_source_buf);
}

// LootCore.roll against the fixed reference table already verified in
// s7_riscv_loot_golden_test.cpp - loot-roll(42, [(1,10),(2,20),(3,5)]) = 3.
GUEST_PUBLIC
long long guest_loot_roll(long long seed) {
	char expr[160];
	snprintf(expr, sizeof(expr),
		"(loot-roll %lld (list (cons 1 10) (cons 2 20) (cons 3 5)))", seed);
	s7_pointer result = s7_eval_c_string(g_sc, expr);
	return (long long)s7_integer(result);
}

// CombatCore.replay against the fixed golden vector already verified
// in s7_riscv_combat_golden_test.cpp (spawn, 30 ticks, one opener
// attack -> tick=30, hp=90, alive=1).
GUEST_PUBLIC
GuestResult guest_combat_replay(void) {
	s7_pointer result = s7_eval_c_string(g_sc,
		"(car (combat-replay (list 'spawn"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick 'tick"
		" 'attack)))");

	// (define-record state tick combo last-attack hp spawn alive)
	int64_t tick = s7_integer(s7_vector_ref(g_sc, result, 0));
	int64_t hp = s7_integer(s7_vector_ref(g_sc, result, 3));
	int64_t alive = s7_boolean(g_sc, s7_vector_ref(g_sc, result, 5)) ? 1 : 0;

	GuestResult out;
	out.values[0] = tick;
	out.values[1] = hp;
	out.values[2] = alive;
	out.count = 3;
	return out;
}

// ProgressionCore.replay against the fixed golden vector already
// verified in s7_riscv_progression_golden_test.cpp (grant(1), grant(1),
// sell(1,50), train, buyArt(1) -> credits=150, affinity=16).
GUEST_PUBLIC
GuestResult guest_progression_replay(void) {
	s7_pointer result = s7_eval_c_string(g_sc,
		"(car (progression-replay (list (list 'grant 1) (list 'grant 1)"
		" (list 'sell 1 50) 'train (list 'buyArt 1))))");

	// (define-record profile credits affinity items arts)
	int64_t credits = s7_integer(s7_vector_ref(g_sc, result, 0));
	int64_t affinity = s7_integer(s7_vector_ref(g_sc, result, 1));

	GuestResult out;
	out.values[0] = credits;
	out.values[1] = affinity;
	out.count = 2;
	return out;
}

int main(void) {
	guest_init();
	// Never `return` from main() - libriscv/OpenSSL global-destructor-
	// ordering crash, same rule s7_sandbox_guest.c documents; _exit()
	// sidesteps it, leaving the interpreter alive in guest memory for
	// repeat vmcalls from the host actor.
	_exit(0);
}
