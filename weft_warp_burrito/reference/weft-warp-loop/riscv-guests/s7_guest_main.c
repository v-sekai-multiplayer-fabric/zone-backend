#include "s7.h"
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

/* Process-wide s7 interpreter state, matching fanout-core's own
 * "one process-wide IO.Ref State" pattern (Fanoutcore/Ffi.lean) - the
 * host (a single Flow actor) calls in sequentially, so no lock is
 * needed, same justification. */
static s7_scheme *g_sc = NULL;

void guest_init(void) {
	g_sc = s7_init();
}

/* VMCALL entry point: evaluate one expression, print its value through
 * the guest's own stdout (a real Linux write() syscall, routed by the
 * host's setup_linux_syscalls() to its own real stdout). Returns the
 * length of the printed representation via the normal integer
 * return-value register - no cross-address-space buffer marshalling
 * needed for a single string result (a raw host pointer is not valid
 * guest-visible memory - see riscv-guests/README.md). */
__attribute__((used, retain))
int guest_eval(const char *expr) {
	s7_pointer result = s7_eval_c_string(g_sc, expr);
	const char *text = s7_object_to_c_string(g_sc, result);
	printf("%s\n", text);
	fflush(stdout);
	int len = 0;
	while (text[len] != '\0') len++;
	return len;
}

/* VMCALL entry point for content that returns a plain integer (loot
 * rolls, damage/score values, ...): evaluates one expression and
 * returns its value directly via the normal integer return-value
 * register - no stdout, no printf, no write() syscall on this path at
 * all, unlike guest_eval above. The host gets a usable value back
 * programmatically instead of having to scrape stdout text. */
__attribute__((used, retain))
long long guest_eval_int(const char *expr) {
	s7_pointer result = s7_eval_c_string(g_sc, expr);
	return (long long)s7_integer(result);
}

int main(void) {
	guest_init();
	/* Never return from main normally (libriscv's VMCALL.md: that runs
	 * global destructors and leaves the runtime unreliable for repeat
	 * calls) - exit explicitly, keeping g_sc alive for guest_eval. */
	_exit(0);
}
