// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Verifies taskweft-types.shrub's three operational functions
// (allocNodeId/addToBlacklist/pruneNode, Layer 0 of the full taskweft
// port) against hand-traced expected values, checked line-by-line
// against the real Lean4 source (taskweft/taskweft's
// lean/Planner/Types.lean):
//
//   allocNodeId({next_node_id=5, ...}) -> (state', 5), state'.next_node_id=6
//   addToBlacklist(state, 'x) prepends: current_blacklist = (x)
//   pruneNode(tree={nodes=(1 2 3), edges=((1.2)(2.3))}, target=2)
//     -> nodes=(1 3), edges=() (both edges touch node 2)
//
// Composite check: alloc a node id from a fresh plan-state (10 empty/
// zero fields + next_node_id=5), blacklist 'x on the result, prune node
// 2 from a 3-node/2-edge tree - expect new-id=5, blacklist=(x),
// pruned nodes count=2, pruned edges count=0. Encoded as one integer:
// new-id*1000 + blacklist-len*100 + pruned-nodes*10 + pruned-edges
// = 5000 + 100 + 20 + 0 = 5120.
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
	if (macros.empty() || types.empty()) {
		fprintf(stderr, "could not read record-macros.scm or taskweft-types-generated.scm\n");
		_exit(1);
	}

	const std::string setup =
		" (define fresh-state (make-plan-state '() '() #f #f #f 0 '() '() '() 5 (vector)))"
		" (define alloc-result (alloc-node-id fresh-state))"
		" (define new-id (cdr alloc-result))"
		" (define blacklisted (add-to-blacklist (car alloc-result) 'x))"
		" (define tree (make-solution-tree (list (make-solution-node 1 'a 'open \"\" '() 0)"
		"                                         (make-solution-node 2 'b 'open \"\" '() 0)"
		"                                         (make-solution-node 3 'c 'open \"\" '() 0))"
		"                                  (list (cons 1 2) (cons 2 3))))"
		" (define pruned (prune-node tree 2))";

	const std::string expr =
		"(begin " + macros + types + setup +
		" (+ (* new-id 1000) (* (length (plan-state-current-blacklist blacklisted)) 100)"
		"    (* (length (solution-tree-nodes pruned)) 10) (length (solution-tree-edges pruned))))";

	constexpr int64_t kExpected = 5120;
	s7RiscvInitialize();
	int64_t result = s7RiscvEvalInt(expr);
	printf("result = %lld (expected %lld)\n", (long long)result, (long long)kExpected);
	fflush(stdout);

	if (result != kExpected) {
		fprintf(stderr, "FAIL\n");
		_exit(1);
	}
	printf("PASS: allocNodeId/addToBlacklist/pruneNode all correct\n");
	fflush(stdout);
	_exit(0);
}
