// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies shrubbery-to-scheme.scm (the s7 port of
// shrubbery_to_scheme.py, per user direction) against the Python
// version's own known-good output on the same input - not just "it
// runs," a real equivalence check.
//
// Ground truth (from `python3 shrubbery_to_scheme.py _verify_snippet.shrub`):
//   (define (add-one x) (+ x 1))
//   (define (classify n) (cond ((< n 0) 'negative) ((= n 0) 'zero) (else 'positive)))
#include "s7_riscv_core.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

static std::string readFile(const char* path) {
	std::ifstream stream(path);
	std::ostringstream buf;
	buf << stream.rdbuf();
	return buf.str();
}

static std::string schemeEscape(const std::string& s) {
	std::string out;
	for (char c : s) {
		if (c == '\\' || c == '"') out += '\\';
		if (c == '\n') { out += "\\n"; continue; }
		out += c;
	}
	return out;
}

static bool checkOne(const std::string& reader, const std::string& label,
	const std::string& source, const std::string& expected) {
	std::string expr =
		"(begin " + reader +
		" (define actual (shrubbery->scheme \"" + schemeEscape(source) + "\"))"
		" (define expected \"" + schemeEscape(expected) + "\")"
		" (if (string=? actual expected) 1 (begin (display actual) (newline) (display expected) (newline) 0)))";
	s7RiscvInitialize();
	int64_t result;
	try {
		// The default 2,000,000-instruction fuel is NOT enough for this
		// reader on real content (measured: the two-function snippet alone
		// costs 1.27M) - build-block-tree's list-ref/length-based tree
		// walk is O(n^2), a real, documented cost of this reader, not
		// hidden. 200M is a generous one-time offline-preprocessing
		// budget, not a per-content-call runtime cost.
		result = s7RiscvEvalInt<200'000'000ull>(expr);
	} catch (const std::exception& e) {
		printf("%s: EXCEPTION: %s\n", label.c_str(), e.what());
		return false;
	}
	printf("%s: %s (%llu instructions)\n", label.c_str(), result == 1 ? "PASS" : "FAIL",
		(unsigned long long)s7RiscvTotalInstructions());
	fflush(stdout);
	return result == 1;
}

int main() {
	std::string reader = readFile("riscv-guests/shrubbery/shrubbery-to-scheme.scm");
	std::string snippet = readFile("riscv-guests/shrubbery/_verify_snippet.shrub");
	std::string loot = readFile("riscv-guests/shrubbery/loot.shrub");
	if (reader.empty() || snippet.empty() || loot.empty()) {
		fprintf(stderr, "could not read a required input file\n");
		_exit(1);
	}

	const std::string snippetExpected =
		"(define (add-one x) (+ x 1))\n"
		"(define (classify n) (cond ((< n 0) 'negative) ((= n 0) 'zero) (else 'positive)))";
	// Ground truth from `python3 shrubbery_to_scheme.py loot.shrub`.
	const std::string lootExpected =
		"(define (u32 x) (logand x #xFFFFFFFF))\n"
		"(define (xorshift32-next32 s0) (let* ((s1 (u32 (logxor s0 (u32 (ash s0 13))))) (s2 (u32 (logxor s1 (ash s1 -17)))) (s3 (u32 (logxor s2 (u32 (ash s2 5)))))) s3))\n"
		"(define (rng-range seed bound) (cond ((= bound 0) 0) (else (modulo (xorshift32-next32 seed) bound))))\n"
		"(define (total-weight-loop t acc) (cond ((null? t) acc) (else (total-weight-loop (cdr t) (+ acc (cdr (car t)))))))\n"
		"(define (total-weight table) (total-weight-loop table 0))\n"
		"(define (pick table r acc) (cond ((null? table) 0) (else (let* ((entry (car table)) (item (car entry)) (w (cdr entry)) (new-acc (+ acc w))) (cond ((< r new-acc) item) (else (pick (cdr table) r new-acc)))))))\n"
		"(define (loot-roll seed table) (let* ((tot (total-weight table))) (cond ((= tot 0) 0) (else (pick table (rng-range seed tot) 0)))))";

	bool ok1 = checkOne(reader, "snippet (define/cond/negative-zero-positive)", snippet, snippetExpected);
	bool ok2 = checkOne(reader, "loot.shrub (real content)", loot, lootExpected);

	if (!ok1 || !ok2) {
		fprintf(stderr, "FAIL: s7 port of the shrubbery reader diverges from the Python version\n");
		_exit(1);
	}
	printf("PASS: shrubbery-to-scheme.scm matches shrubbery_to_scheme.py exactly on both inputs\n");
	fflush(stdout);
	_exit(0);
}
