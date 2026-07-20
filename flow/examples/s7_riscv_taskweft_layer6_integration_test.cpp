// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Layer 6 of the full taskweft port: integration. taskweft_nif.cpp's
// own real entry points were fetched and read in full - there is no
// single NIF call that composes goal decomposition, ReBAC, and
// temporal reasoning together (plan_with_temporal* only fuses tw_plan
// with tw_check_temporal*, never TwReBAC::*; the rebac_* NIFs are
// entirely standalone). Checked SimpleTravelExample.lean and
// HealthcareSchedulingExample.lean too - neither combines all three
// either (SimpleTravelExample has no ReBAC/temporal at all;
// HealthcareSchedulingExample has temporal but no ReBAC), and both
// verify via native_decide-proved theorems, not #eval doctests, so
// neither has a ready-made golden vector to lift. Since the real
// system never composes these three either, this test builds its own
// small scenario and hand-traces the expected result - the same
// "hand-trace when no official worked example exists" fallback this
// port has used before (ADR 0035's taskweft-lite verification).
//
// Scenario: a courier delivers a package into a restricted zone.
//   - Goals (taskweft-lite.shrub's find-plan): "deliver-package"
//     decomposes via its one method alternative into the primitive
//     action sequence [pickup, transport, dropoff].
//   - ReBAC (taskweft-capabilities.shrub's has-capability): only a
//     courier who is a member of "authorized_couriers" (which itself
//     HAS_CAPABILITY "access_restricted") may perform the "transport"
//     step, since it moves the package into "restricted_zone".
//     courier1 is a member (authorized); courier2 is not.
//   - Temporal (taskweft-temporal.shrub's all-constraints-satisfied):
//     the produced plan's own order must satisfy pickup-before-
//     transport, transport-before-dropoff, and dropoff completing
//     within a t=30 deadline - checked once against the plan's real
//     order (must hold) and once against a deliberately reordered
//     sequence (must NOT hold), so this isn't just checking a
//     constant #t/#f.
#include "s7_riscv_core.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

static std::string readFile(const char* path) {
	std::ifstream stream(path);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

int main() {
	std::string macros = readFile("riscv-guests/content/record-macros.scm");
	std::string types = readFile("riscv-guests/shrubbery/taskweft-types-generated.scm");
	std::string caps = readFile("riscv-guests/shrubbery/taskweft-capabilities-generated.scm");
	std::string lite = readFile("riscv-guests/shrubbery/taskweft-lite-generated.scm");
	std::string temporal = readFile("riscv-guests/shrubbery/taskweft-temporal-generated.scm");
	if (macros.empty() || types.empty() || caps.empty() || lite.empty() || temporal.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string scenario = R"(
	    (define state (list (cons "location" "warehouse") (cons "has-package" #f) (cons "delivered" #f)))
	    (define actions (list
	      (cons "pickup" (list (cons "has-package" #t)))
	      (cons "transport" (list (cons "location" "restricted_zone")))
	      (cons "dropoff" (list (cons "delivered" #t)))))
	    (define methods (list
	      (cons "deliver-package" (list (cons "standard" (list (list "pickup") (list "transport") (list "dropoff")))))))
	    (define todo (list (list "deliver-package")))
	    (define plan-result (find-plan state todo actions methods))
	    (define plan (car (cdr plan-result)))
	    (define graph (list (make-relationship 'courier1 'IS_MEMBER_OF 'authorized_couriers)
	                         (make-relationship 'authorized_couriers 'HAS_CAPABILITY 'access_restricted)))
	    (define courier1-authorized (has-capability graph 'courier1 'HAS_CAPABILITY 'access_restricted 3))
	    (define courier2-authorized (has-capability graph 'courier2 'HAS_CAPABILITY 'access_restricted 3))
	    (define metas (list (list "pickup" 0 5) (list "transport" 5 20) (list "dropoff" 20 25)))
	    (define cs (list (list 'before "pickup" "transport") (list 'before "transport" "dropoff") (list 'within "dropoff" 30)))
	    (define real-order-ok (all-constraints-satisfied plan metas cs))
	    (define bad-order (list "transport" "pickup" "dropoff"))
	    (define bad-order-ok (all-constraints-satisfied bad-order metas cs))
	)";

	const std::string expr =
		"(begin " + macros + types + caps + lite + temporal + scenario +
		R"( (+ (if (equal? plan (list "pickup" "transport" "dropoff")) 1000000 0)
		        (if (equal? courier1-authorized #t) 100000 0)
		        (if (equal? courier2-authorized #f) 10000 0)
		        (if (equal? real-order-ok #t) 1000 0)
		        (if (equal? bad-order-ok #f) 100 0))))";

	constexpr int64_t kExpected = 1111100;  // 1000000+100000+10000+1000+100
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt<20'000'000ull>(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: Layer 6 integration verified (goals + ReBAC + temporal composed over one scenario)\n");
	fflush(stdout);
	_exit(0);
}
