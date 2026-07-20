#!/usr/bin/env python3
"""
IPyHOP timing benchmark — canonical problems.
Run from the cloned IPyHOP repo root:
  cd /tmp/ipyhop && python3 <path>/ipyhop_bench.py
"""
import sys, timeit, statistics
sys.path.insert(0, '/tmp/ipyhop')

from ipyhop import IPyHOP

# ── simple_travel ─────────────────────────────────────────────────────────────
from examples.simple_travel.task_based.simple_travel_domain import actions as st_actions, methods as st_methods
from examples.simple_travel.task_based.simple_travel_problem import init_state as st_state, task_list_1, task_list_2
import copy

st_planner = IPyHOP(st_methods, st_actions)

# ── blocks_world ──────────────────────────────────────────────────────────────
from examples.blocks_world.task_based.blocks_world_actions import actions as bw_actions
from examples.blocks_world.task_based.blocks_world_methods_1 import methods as bw_methods
from examples.blocks_world.task_based.blocks_world_problem import (
    init_state_1, goal1a, init_state_2, goal2a, init_state_3, goal3
)

bw_planner = IPyHOP(bw_methods, bw_actions)

N = 500

def bench(label, fn):
    times = []
    for _ in range(N):
        t = timeit.timeit(fn, number=1) * 1_000_000  # µs
        times.append(t)
    times.sort()
    p50 = times[N // 2]
    p99 = times[int(N * 0.99)]
    avg = statistics.mean(times)
    print(f"{label:<40} p50={p50:7.1f}µs  p99={p99:7.1f}µs  avg={avg:7.1f}µs")

print(f"\n{'IPyHOP benchmark (Python ' + sys.version.split()[0] + ')'}")
print(f"{'problem':<40} {'p50':>10}  {'p99':>10}  {'avg':>10}")
print("-" * 75)

# simple_travel
bench("simple_travel / task_list_1",
      lambda: st_planner.plan(copy.deepcopy(st_state), task_list_1, verbose=0))
bench("simple_travel / task_list_2",
      lambda: st_planner.plan(copy.deepcopy(st_state), task_list_2, verbose=0))

# blocks_world
bench("blocks_world / init1 + goal1a (3 blk)",
      lambda: bw_planner.plan(copy.deepcopy(init_state_1), [('move_blocks', goal1a)], verbose=0))
bench("blocks_world / init2 + goal2a (4 blk)",
      lambda: bw_planner.plan(copy.deepcopy(init_state_2), [('move_blocks', goal2a)], verbose=0))
bench("blocks_world / init3 + goal3  (19 blk)",
      lambda: bw_planner.plan(copy.deepcopy(init_state_3), [('move_blocks', goal3)],  verbose=0))
