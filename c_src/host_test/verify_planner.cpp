// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Stage 5A proof: c_src/s7/fixtures/planner.scm (the compiled HTN
// planner -- task search AND domain evaluation, all in Scheme; see the
// file's own header) against a hand-written reference oracle that
// mirrors the same control flow (splice order, fuel placement, method/
// goal/multigoal branching) independently, using only the
// already-trusted generic structural host ops (car/cdr/cons/
// hash-table-ref/hash-table-set/list-ref -- verified separately by
// verify_s7.cpp) as its own primitives. Every test case runs three ways:
// the reference oracle, the IR interpreter oracle, and real RISC-V
// execution.
#include <cstdio>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#include <libriscv/machine.hpp>

#include "../s7/compiler.h"
#include "../s7/host_math.h"
#include "../s7/ir_interpreter.h"
#include "../s7/value.h"

using Machine64 = riscv::Machine<riscv::RISCV64>;
using Val = int64_t;

namespace {

// --- Fixed tag order, matching planner.scm's header comment exactly. ---
struct Tags {
  Val call, goal, multigoal, eval, set, lit, param, get, eq, lt, add, sub, not_, and_, or_;

  static Tags build(s7::HostBignumTable& t) {
    Tags tg;
    tg.call = t.make_atom("call");
    tg.goal = t.make_atom("goal");
    tg.multigoal = t.make_atom("multigoal");
    tg.eval = t.make_atom("eval");
    tg.set = t.make_atom("set");
    tg.lit = t.make_atom("lit");
    tg.param = t.make_atom("param");
    tg.get = t.make_atom("get");
    tg.eq = t.make_atom("eq");
    tg.lt = t.make_atom("lt");
    tg.add = t.make_atom("add");
    tg.sub = t.make_atom("sub");
    tg.not_ = t.make_atom("not");
    tg.and_ = t.make_atom("and");
    tg.or_ = t.make_atom("or");
    return tg;
  }

  Val as_list(s7::HostBignumTable& t) const {
    return t.make_list({call, goal, multigoal, eval, set, lit, param, get, eq, lt, add, sub,
                        not_, and_, or_});
  }
};

// --- Node builders (host-owned tagged lists, mirrors planner.scm) ---

Val mk_lit(s7::HostBignumTable& t, const Tags& tg, Val value) {
  return t.make_list({tg.lit, value});
}
Val mk_param(s7::HostBignumTable& t, const Tags& tg, Val name) {
  return t.make_list({tg.param, name});
}
Val mk_get(s7::HostBignumTable& t, const Tags& tg, Val var, Val key) {
  return t.make_list({tg.get, var, key});
}
Val mk_add(s7::HostBignumTable& t, const Tags& tg, Val a, Val b) {
  return t.make_list({tg.add, a, b});
}

// --- Action/method/task builders ---

// action = (params binds body); body step = (eval node) | (set var key node)
Val mk_action(s7::HostBignumTable& t, Val params, Val binds, Val body) {
  return t.make_list({params, binds, body});
}
Val mk_bind(s7::HostBignumTable& t, Val name, Val var, Val key) {
  return t.make_list({name, var, key});
}
Val mk_eval_step(s7::HostBignumTable& t, const Tags& tg, Val node) {
  return t.make_list({tg.eval, node});
}
Val mk_set_step(s7::HostBignumTable& t, const Tags& tg, Val var, Val key, Val node) {
  return t.make_list({tg.set, var, key, node});
}

// method = (params binds checks subtasks); subtask-def = (name arg-nodes)
Val mk_method(s7::HostBignumTable& t, Val params, Val binds, Val checks, Val subtasks) {
  return t.make_list({params, binds, checks, subtasks});
}
Val mk_subtask_def(s7::HostBignumTable& t, Val name, Val arg_nodes) {
  return t.make_list({name, arg_nodes});
}

Val mk_call(s7::HostBignumTable& t, const Tags& tg, Val name, Val args) {
  return t.make_list({tg.call, name, args});
}
Val mk_binding(s7::HostBignumTable& t, Val var, Val key, Val desired) {
  return t.make_list({var, key, desired});
}
Val mk_goal(s7::HostBignumTable& t, const Tags& tg, Val bindings) {
  return t.make_list({tg.goal, bindings});
}
Val mk_multigoal(s7::HostBignumTable& t, const Tags& tg, Val bindings) {
  return t.make_list({tg.multigoal, bindings});
}

// --- Reference oracle: independent control-flow mirror of planner.scm,
//     built only from already-trusted generic structural ops. ---

struct RefPlanner {
  s7::HostBignumTable& t;
  const Tags& tg;

  Val nested_ref(Val state, Val var, Val key) {
    Val inner = t.apply(s7::kHostMapRef, state, var);
    if (inner == s7::kFalse) return s7::kFalse;
    return t.apply(s7::kHostMapRef, inner, key);
  }

  Val nested_set(Val state, Val var, Val key, Val value) {
    Val inner = t.apply(s7::kHostMapRef, state, var);
    Val kv = t.apply(s7::kHostCons, key, t.apply(s7::kHostCons, value, s7::kNil));
    Val new_inner = t.apply(s7::kHostMapSet, inner, kv);
    Val kv2 = t.apply(s7::kHostCons, var, t.apply(s7::kHostCons, new_inner, s7::kNil));
    return t.apply(s7::kHostMapSet, state, kv2);
  }

  bool goal_satisfied(Val state, Val var, Val key, Val desired) {
    return nested_ref(state, var, key) == desired;
  }

  Val params_ref(const std::vector<std::pair<Val, Val>>& params, Val name) {
    for (auto& [k, v] : params) {
      if (k == name) return v;
    }
    return s7::kFalse;
  }

  Val eval_node(Val node, const std::vector<std::pair<Val, Val>>& params, Val state) {
    Val tag = t.apply(s7::kHostCar, node, 0);
    if (tag == tg.lit) return t.apply(s7::kHostListRef, node, s7::tag_fixnum(1));
    if (tag == tg.param) return params_ref(params, t.apply(s7::kHostListRef, node, s7::tag_fixnum(1)));
    if (tag == tg.get) {
      Val var = t.apply(s7::kHostListRef, node, s7::tag_fixnum(1));
      Val key = t.apply(s7::kHostListRef, node, s7::tag_fixnum(2));
      return nested_ref(state, var, key);
    }
    Val a = eval_node(t.apply(s7::kHostListRef, node, s7::tag_fixnum(1)), params, state);
    if (tag == tg.not_) return (a == s7::kFalse) ? s7::kTrue : s7::kFalse;
    Val b = eval_node(t.apply(s7::kHostListRef, node, s7::tag_fixnum(2)), params, state);
    if (tag == tg.eq) return (a == b) ? s7::kTrue : s7::kFalse;
    if (tag == tg.lt) return (t.unbox(a) < t.unbox(b)) ? s7::kTrue : s7::kFalse;
    if (tag == tg.add) return t.box(t.unbox(a) + t.unbox(b));
    if (tag == tg.sub) return t.box(t.unbox(a) - t.unbox(b));
    if (tag == tg.and_) return (a == s7::kFalse) ? s7::kFalse : b;
    if (tag == tg.or_) return (a != s7::kFalse) ? s7::kTrue : b;
    throw std::runtime_error("ref_eval_node: unknown node tag");
  }

  std::vector<Val> eval_node_list(Val nodes, const std::vector<std::pair<Val, Val>>& params,
                                  Val state) {
    std::vector<Val> out;
    while (nodes != s7::kNil) {
      out.push_back(eval_node(t.apply(s7::kHostCar, nodes, 0), params, state));
      nodes = t.apply(s7::kHostCdr, nodes, 0);
    }
    return out;
  }

  std::vector<std::pair<Val, Val>> build_params(Val names, const std::vector<Val>& args) {
    std::vector<std::pair<Val, Val>> params;
    size_t i = 0;
    while (names != s7::kNil && i < args.size()) {
      params.emplace_back(t.apply(s7::kHostCar, names, 0), args[i]);
      names = t.apply(s7::kHostCdr, names, 0);
      ++i;
    }
    return params;
  }

  std::vector<std::pair<Val, Val>> run_binds(Val binds, std::vector<std::pair<Val, Val>> params,
                                             Val state) {
    while (binds != s7::kNil) {
      Val b = t.apply(s7::kHostCar, binds, 0);
      Val name = t.apply(s7::kHostListRef, b, s7::tag_fixnum(0));
      Val var = t.apply(s7::kHostListRef, b, s7::tag_fixnum(1));
      Val key = t.apply(s7::kHostListRef, b, s7::tag_fixnum(2));
      params.emplace_back(name, nested_ref(state, var, key));
      binds = t.apply(s7::kHostCdr, binds, 0);
    }
    return params;
  }

  // Returns the new state, or kFalse if an eval step failed.
  Val run_body(Val steps, const std::vector<std::pair<Val, Val>>& params, Val state) {
    while (steps != s7::kNil) {
      Val step = t.apply(s7::kHostCar, steps, 0);
      Val step_tag = t.apply(s7::kHostListRef, step, s7::tag_fixnum(0));
      if (step_tag == tg.eval) {
        Val node = t.apply(s7::kHostListRef, step, s7::tag_fixnum(1));
        if (eval_node(node, params, state) == s7::kFalse) return s7::kFalse;
      } else {
        Val var = t.apply(s7::kHostListRef, step, s7::tag_fixnum(1));
        Val key = t.apply(s7::kHostListRef, step, s7::tag_fixnum(2));
        Val node = t.apply(s7::kHostListRef, step, s7::tag_fixnum(3));
        state = nested_set(state, var, key, eval_node(node, params, state));
      }
      steps = t.apply(s7::kHostCdr, steps, 0);
    }
    return state;
  }

  // action = (params binds body). Returns new state or kFalse.
  Val apply_action(Val action, Val state, const std::vector<Val>& args) {
    Val a_params = t.apply(s7::kHostListRef, action, s7::tag_fixnum(0));
    Val a_binds = t.apply(s7::kHostListRef, action, s7::tag_fixnum(1));
    Val a_body = t.apply(s7::kHostListRef, action, s7::tag_fixnum(2));
    auto params = run_binds(a_binds, build_params(a_params, args), state);
    return run_body(a_body, params, state);
  }

  bool run_checks(Val checks, const std::vector<std::pair<Val, Val>>& params, Val state) {
    while (checks != s7::kNil) {
      if (eval_node(t.apply(s7::kHostCar, checks, 0), params, state) == s7::kFalse) return false;
      checks = t.apply(s7::kHostCdr, checks, 0);
    }
    return true;
  }

  // method = (params binds checks subtasks). Returns subtask-list handle
  // (kNil if empty), or kFalse if a check failed.
  Val try_method(Val method, Val state, const std::vector<Val>& args) {
    Val m_params = t.apply(s7::kHostListRef, method, s7::tag_fixnum(0));
    Val m_binds = t.apply(s7::kHostListRef, method, s7::tag_fixnum(1));
    Val m_checks = t.apply(s7::kHostListRef, method, s7::tag_fixnum(2));
    Val m_subtasks = t.apply(s7::kHostListRef, method, s7::tag_fixnum(3));
    auto params = run_binds(m_binds, build_params(m_params, args), state);
    if (!run_checks(m_checks, params, state)) return s7::kFalse;

    std::vector<Val> out;
    Val defs = m_subtasks;
    while (defs != s7::kNil) {
      Val def = t.apply(s7::kHostCar, defs, 0);
      Val name = t.apply(s7::kHostListRef, def, s7::tag_fixnum(0));
      Val arg_nodes = t.apply(s7::kHostListRef, def, s7::tag_fixnum(1));
      std::vector<Val> resolved = eval_node_list(arg_nodes, params, state);
      out.push_back(mk_call(t, tg, name, t.make_list(resolved)));
      defs = t.apply(s7::kHostCdr, defs, 0);
    }
    return t.make_list(out);
  }

  // --- Search (mirrors walk-tasks/branch-*/try-*-methods in planner.scm) ---

  Val cons(Val head, Val list) { return t.apply(s7::kHostCons, head, list); }

  Val list_append(Val a, Val b) {
    if (a == s7::kNil) return b;
    return cons(t.apply(s7::kHostCar, a, 0), list_append(t.apply(s7::kHostCdr, a, 0), b));
  }

  Val binding_var(Val b) { return t.apply(s7::kHostListRef, b, s7::tag_fixnum(0)); }
  Val binding_key(Val b) { return t.apply(s7::kHostListRef, b, s7::tag_fixnum(1)); }
  Val binding_desired(Val b) { return t.apply(s7::kHostListRef, b, s7::tag_fixnum(2)); }

  bool goal_satisfied_all(Val state, Val bindings) {
    while (bindings != s7::kNil) {
      Val b = t.apply(s7::kHostCar, bindings, 0);
      if (!goal_satisfied(state, binding_var(b), binding_key(b), binding_desired(b))) return false;
      bindings = t.apply(s7::kHostCdr, bindings, 0);
    }
    return true;
  }

  Val first_unmet(Val state, Val bindings) {
    while (bindings != s7::kNil) {
      Val b = t.apply(s7::kHostCar, bindings, 0);
      if (!goal_satisfied(state, binding_var(b), binding_key(b), binding_desired(b))) return b;
      bindings = t.apply(s7::kHostCdr, bindings, 0);
    }
    return s7::kFalse;
  }

  std::vector<Val> all_unmet(Val state, Val bindings) {
    std::vector<Val> out;
    while (bindings != s7::kNil) {
      Val b = t.apply(s7::kHostCar, bindings, 0);
      if (!goal_satisfied(state, binding_var(b), binding_key(b), binding_desired(b)))
        out.push_back(b);
      bindings = t.apply(s7::kHostCdr, bindings, 0);
    }
    return out;
  }

  std::vector<Val> args_from_list(Val list) {
    std::vector<Val> out;
    while (list != s7::kNil) {
      out.push_back(t.apply(s7::kHostCar, list, 0));
      list = t.apply(s7::kHostCdr, list, 0);
    }
    return out;
  }

  Val actions_tbl, methods_tbl;

  // Returns kFalse on failure, or a (possibly kNil) plan list on success.
  Val walk_tasks(Val state, Val tasks, int fuel) {
    if (tasks == s7::kNil) return s7::kNil;
    Val task = t.apply(s7::kHostCar, tasks, 0);
    Val task_tag = t.apply(s7::kHostListRef, task, s7::tag_fixnum(0));
    Val bindings = (task_tag == tg.goal || task_tag == tg.multigoal)
                       ? t.apply(s7::kHostListRef, task, s7::tag_fixnum(1))
                       : s7::kFalse;

    if (task_tag == tg.goal) {
      if (goal_satisfied_all(state, bindings)) {
        return walk_tasks(state, t.apply(s7::kHostCdr, tasks, 0), fuel);
      }
      return branch_goal(state, tasks, fuel);
    }
    if (task_tag == tg.multigoal) {
      if (goal_satisfied_all(state, bindings)) {
        return walk_tasks(state, t.apply(s7::kHostCdr, tasks, 0), fuel);
      }
      return branch_multigoal(state, tasks, fuel);
    }
    // Primitive action or compound task.
    Val name = t.apply(s7::kHostListRef, task, s7::tag_fixnum(1));
    Val action = t.apply(s7::kHostMapRef, actions_tbl, name);
    if (action != s7::kFalse) {
      std::vector<Val> args = args_from_list(t.apply(s7::kHostListRef, task, s7::tag_fixnum(2)));
      Val new_state = apply_action(action, state, args);
      if (new_state == s7::kFalse) return s7::kFalse;
      Val rest = walk_tasks(new_state, t.apply(s7::kHostCdr, tasks, 0), fuel);
      if (rest == s7::kFalse) return s7::kFalse;
      return cons(task, rest);
    }
    return branch_compound(state, tasks, fuel);
  }

  Val branch_goal(Val state, Val tasks, int fuel) {
    if (fuel < 1) return s7::kFalse;
    Val goal = t.apply(s7::kHostCar, tasks, 0);
    Val remaining = t.apply(s7::kHostCdr, tasks, 0);
    Val unmet = first_unmet(state, t.apply(s7::kHostListRef, goal, s7::tag_fixnum(1)));
    if (unmet == s7::kFalse) return s7::kFalse;
    Val methods = t.apply(s7::kHostMapRef, methods_tbl, binding_var(unmet));
    if (methods == s7::kFalse) return s7::kFalse;
    std::vector<Val> args = {binding_key(unmet), binding_desired(unmet)};
    while (methods != s7::kNil) {
      Val method = t.apply(s7::kHostCar, methods, 0);
      Val subtasks = try_method(method, state, args);
      if (subtasks != s7::kFalse) {
        Val new_tasks = list_append(subtasks, cons(goal, remaining));
        Val result = walk_tasks(state, new_tasks, fuel - 1);
        if (result != s7::kFalse) return result;
      }
      methods = t.apply(s7::kHostCdr, methods, 0);
    }
    return s7::kFalse;
  }

  Val branch_multigoal(Val state, Val tasks, int fuel) {
    if (fuel < 1) return s7::kFalse;
    Val mg = t.apply(s7::kHostCar, tasks, 0);
    Val remaining = t.apply(s7::kHostCdr, tasks, 0);
    std::vector<Val> unmet = all_unmet(state, t.apply(s7::kHostListRef, mg, s7::tag_fixnum(1)));
    for (Val b : unmet) {
      Val sub_goal = mk_goal(t, tg, t.make_list({b}));
      Val new_tasks = cons(sub_goal, cons(mg, remaining));
      Val result = walk_tasks(state, new_tasks, fuel - 1);
      if (result != s7::kFalse) return result;
    }
    return s7::kFalse;
  }

  Val branch_compound(Val state, Val tasks, int fuel) {
    if (fuel < 1) return s7::kFalse;
    Val task = t.apply(s7::kHostCar, tasks, 0);
    Val remaining = t.apply(s7::kHostCdr, tasks, 0);
    Val name = t.apply(s7::kHostListRef, task, s7::tag_fixnum(1));
    Val methods = t.apply(s7::kHostMapRef, methods_tbl, name);
    if (methods == s7::kFalse) return s7::kFalse;
    std::vector<Val> args = args_from_list(t.apply(s7::kHostListRef, task, s7::tag_fixnum(2)));
    while (methods != s7::kNil) {
      Val method = t.apply(s7::kHostCar, methods, 0);
      Val subtasks = try_method(method, state, args);
      if (subtasks != s7::kFalse) {
        Val new_tasks = list_append(subtasks, remaining);
        Val result = walk_tasks(state, new_tasks, fuel - 1);
        if (result != s7::kFalse) return result;
      }
      methods = t.apply(s7::kHostCdr, methods, 0);
    }
    return s7::kFalse;
  }

  Val plan(Val state, Val tasks) { return walk_tasks(state, tasks, 400); }
};

// --- Structural plan comparison: prints a plan (list of ("call" name
//     args)) as "name(args) name(args) ..." for diffing across the
//     three execution paths (handle numbers differ between runs). ---
std::string decode_plan(s7::HostBignumTable& t, Val plan) {
  if (plan == s7::kFalse) return "NO-PLAN";
  std::string out;
  while (plan != s7::kNil) {
    Val call = t.apply(s7::kHostCar, plan, 0);
    Val name = t.apply(s7::kHostListRef, call, s7::tag_fixnum(1));
    Val args = t.apply(s7::kHostListRef, call, s7::tag_fixnum(2));
    out += t.deref(name).bytes;
    out += "(";
    bool first = true;
    while (args != s7::kNil) {
      if (!first) out += ",";
      first = false;
      Val a = t.apply(s7::kHostCar, args, 0);
      out += ((a & 7) == 0) ? std::to_string(a >> 3) : "?";
      args = t.apply(s7::kHostCdr, args, 0);
    }
    out += ") ";
    plan = t.apply(s7::kHostCdr, plan, 0);
  }
  return out;
}

int64_t run_riscv(const std::vector<uint8_t>& elf, Val state, Val tasks, Val ctx,
                  s7::HostBignumTable& table) {
  Machine64 machine(elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
  machine.set_userdata(&table);
  return static_cast<int64_t>(machine.vmcall<50'000'000ull>("plan", state, tasks, ctx));
}

}  // namespace

namespace {

// A domain builder constructs (state, tasks, actions_tbl, methods_tbl)
// fresh in whatever table it's given -- called once per execution path
// so each gets independent handle numbering (structural compare only,
// per verify_s7.cpp's own established convention).
struct Built {
  Val state, tasks, actions_tbl, methods_tbl;
};
using Builder = std::function<Built(s7::HostBignumTable&, const Tags&)>;

struct TestCase {
  const char* name;
  Builder build;
  const char* expected;  // decode_plan form
};

}  // namespace

int main() {
  Machine64::install_syscall_handler(
      static_cast<size_t>(s7::kSyscallHostMath), [](Machine64& machine) {
        auto* table = machine.get_userdata<s7::HostBignumTable>();
        auto [op, a, b] = machine.sysargs<int64_t, int64_t, int64_t>();
        machine.set_result(table->apply(op, a, b));
      });

  std::ifstream src_file("c_src/s7/fixtures/planner.scm");
  if (!src_file) src_file.open("s7/fixtures/planner.scm");
  if (!src_file) {
    fprintf(stderr, "FAIL: could not open c_src/s7/fixtures/planner.scm\n");
    return 1;
  }
  std::ostringstream src_stream;
  src_stream << src_file.rdbuf();
  s7::Compiled compiled = s7::compile(src_stream.str());
  int func_index = compiled.ir.find("plan");
  if (func_index < 0) {
    fprintf(stderr, "FAIL: plan not found in compiled program\n");
    return 1;
  }

  // node/action/method/task builders, mirroring planner.scm's shapes.
  auto mk_body_eval = [](s7::HostBignumTable& t, const Tags& tg, Val node) {
    return mk_eval_step(t, tg, node);
  };
  auto mk_body_set = [](s7::HostBignumTable& t, const Tags& tg, Val var, Val key, Val node) {
    return mk_set_step(t, tg, var, key, node);
  };

  const std::vector<TestCase> tests = {
      {"compound-fallback-primary",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val threat = t.make_atom("threat"), loc = t.make_atom("loc");
         Val near = t.make_atom("near"), pos = t.make_atom("pos");
         Val shelter = t.make_atom("shelter"), open = t.make_atom("open");
         Val flee = t.make_atom("flee"), recover = t.make_atom("recover"),
             drift = t.make_atom("drift"), behave = t.make_atom("behave");

         Val flee_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, loc, pos, mk_lit(t, tg, shelter))}));
         Val recover_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, threat, near, mk_lit(t, tg, s7::kFalse))}));
         Val drift_action = mk_action(t, s7::kNil, s7::kNil, s7::kNil);

         Val alt1 = mk_method(t, s7::kNil, s7::kNil, t.make_list({mk_get(t, tg, threat, near)}),
                              t.make_list({mk_subtask_def(t, flee, s7::kNil),
                                          mk_subtask_def(t, recover, s7::kNil)}));
         Val alt2 = mk_method(t, s7::kNil, s7::kNil, s7::kNil,
                              t.make_list({mk_subtask_def(t, drift, s7::kNil)}));

         Val actions_tbl = t.make_map({{flee, flee_action},
                                       {recover, recover_action},
                                       {drift, drift_action}});
         Val methods_tbl = t.make_map({{behave, t.make_list({alt1, alt2})}});
         Val state = t.make_map(
             {{threat, t.make_map({{near, s7::kTrue}})}, {loc, t.make_map({{pos, open}})}});
         Val tasks = t.make_list({mk_call(t, tg, behave, s7::kNil)});
         return {state, tasks, actions_tbl, methods_tbl};
       },
       "flee() recover() "},
      {"compound-fallback-secondary",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val threat = t.make_atom("threat"), loc = t.make_atom("loc");
         Val near = t.make_atom("near"), pos = t.make_atom("pos");
         Val shelter = t.make_atom("shelter"), open = t.make_atom("open");
         Val flee = t.make_atom("flee"), recover = t.make_atom("recover"),
             drift = t.make_atom("drift"), behave = t.make_atom("behave");

         Val flee_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, loc, pos, mk_lit(t, tg, shelter))}));
         Val recover_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, threat, near, mk_lit(t, tg, s7::kFalse))}));
         Val drift_action = mk_action(t, s7::kNil, s7::kNil, s7::kNil);

         Val alt1 = mk_method(t, s7::kNil, s7::kNil, t.make_list({mk_get(t, tg, threat, near)}),
                              t.make_list({mk_subtask_def(t, flee, s7::kNil),
                                          mk_subtask_def(t, recover, s7::kNil)}));
         Val alt2 = mk_method(t, s7::kNil, s7::kNil, s7::kNil,
                              t.make_list({mk_subtask_def(t, drift, s7::kNil)}));

         Val actions_tbl = t.make_map({{flee, flee_action},
                                       {recover, recover_action},
                                       {drift, drift_action}});
         Val methods_tbl = t.make_map({{behave, t.make_list({alt1, alt2})}});
         // threat.near = #f this time -> alt1's check fails -> alt2 (drift).
         Val state = t.make_map(
             {{threat, t.make_map({{near, s7::kFalse}})}, {loc, t.make_map({{pos, open}})}});
         Val tasks = t.make_list({mk_call(t, tg, behave, s7::kNil)});
         return {state, tasks, actions_tbl, methods_tbl};
       },
       "drift() "},
      {"goal-with-no-method-fails",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val loc = t.make_atom("loc"), pos = t.make_atom("pos"), shelter = t.make_atom("shelter"),
             open = t.make_atom("open");
         Val state = t.make_map({{loc, t.make_map({{pos, open}})}});
         Val tasks =
             t.make_list({mk_goal(t, tg, t.make_list({mk_binding(t, loc, pos, shelter)}))});
         // actions/methods tables are always real (possibly empty) map
         // handles in practice -- hash-table-ref requires a Map, unlike
         // hash-table-set's "#f means empty" convenience.
         return {state, tasks, t.make_map({}), t.make_map({})};
       },
       "NO-PLAN"},
      {"multigoal-backtracks-over-both-bindings",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val threat = t.make_atom("threat"), loc = t.make_atom("loc");
         Val near = t.make_atom("near"), pos = t.make_atom("pos");
         Val shelter = t.make_atom("shelter"), open = t.make_atom("open");
         Val flee = t.make_atom("flee"), recover = t.make_atom("recover");

         Val flee_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, loc, pos, mk_lit(t, tg, shelter))}));
         Val recover_action =
             mk_action(t, s7::kNil, s7::kNil,
                       t.make_list({mk_body_set(t, tg, threat, near, mk_lit(t, tg, s7::kFalse))}));

         Val threat_method =
             mk_method(t, s7::kNil, s7::kNil, s7::kNil,
                       t.make_list({mk_subtask_def(t, recover, s7::kNil)}));
         Val loc_method = mk_method(t, s7::kNil, s7::kNil, s7::kNil,
                                    t.make_list({mk_subtask_def(t, flee, s7::kNil)}));

         Val actions_tbl = t.make_map({{flee, flee_action}, {recover, recover_action}});
         Val methods_tbl =
             t.make_map({{threat, t.make_list({threat_method})}, {loc, t.make_list({loc_method})}});
         Val state = t.make_map(
             {{threat, t.make_map({{near, s7::kTrue}})}, {loc, t.make_map({{pos, open}})}});
         Val tasks = t.make_list({mk_multigoal(
             t, tg, t.make_list({mk_binding(t, threat, near, s7::kFalse),
                                mk_binding(t, loc, pos, shelter)}))});
         return {state, tasks, actions_tbl, methods_tbl};
       },
       "recover() flee() "},
      {"goal-forces-method-retry-via-reappend",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val counter = t.make_atom("counter"), val = t.make_atom("val");
         Val cur = t.make_atom("cur"), bump = t.make_atom("bump"),
             counter_task = t.make_atom("reach-3");

         Val bump_action = mk_action(
             t, t.make_list({cur}), t.make_list({mk_bind(t, cur, counter, val)}),
             t.make_list({mk_body_set(t, tg, counter, val,
                                      mk_add(t, tg, mk_param(t, tg, cur), mk_lit(t, tg, s7::tag_fixnum(1))))}));
         Val method =
             mk_method(t, s7::kNil, s7::kNil, s7::kNil, t.make_list({mk_subtask_def(t, bump, s7::kNil)}));

         Val actions_tbl = t.make_map({{bump, bump_action}});
         Val methods_tbl = t.make_map({{counter, t.make_list({method})}});
         Val state = t.make_map({{counter, t.make_map({{val, s7::tag_fixnum(0)}})}});
         Val tasks = t.make_list(
             {mk_goal(t, tg, t.make_list({mk_binding(t, counter, val, s7::tag_fixnum(3))}))});
         (void)counter_task;
         return {state, tasks, actions_tbl, methods_tbl};
       },
       "bump() bump() bump() "},
      {"long-flat-sequence-spends-no-fuel",
       [=](s7::HostBignumTable& t, const Tags& tg) -> Built {
         Val drift = t.make_atom("drift");
         Val drift_action = mk_action(t, s7::kNil, s7::kNil, s7::kNil);
         Val actions_tbl = t.make_map({{drift, drift_action}});
         std::vector<Val> task_list;
         for (int i = 0; i < 50; ++i) task_list.push_back(mk_call(t, tg, drift, s7::kNil));
         Val tasks = t.make_list(task_list);
         return {s7::kNil, tasks, actions_tbl, s7::kNil};
       },
       // 50 repetitions of "drift() ".
       "drift() drift() drift() drift() drift() drift() drift() drift() drift() drift() "
       "drift() drift() drift() drift() drift() drift() drift() drift() drift() drift() "
       "drift() drift() drift() drift() drift() drift() drift() drift() drift() drift() "
       "drift() drift() drift() drift() drift() drift() drift() drift() drift() drift() "
       "drift() drift() drift() drift() drift() drift() drift() drift() drift() drift() "},
  };

  int failures = 0;
  for (const TestCase& test : tests) {
    try {
      s7::HostBignumTable oracle_table;
      Tags oracle_tags = Tags::build(oracle_table);
      Built oracle_built = test.build(oracle_table, oracle_tags);
      RefPlanner ref{oracle_table, oracle_tags};
      ref.actions_tbl = oracle_built.actions_tbl;
      ref.methods_tbl = oracle_built.methods_tbl;
      std::string oracle_str =
          decode_plan(oracle_table, ref.plan(oracle_built.state, oracle_built.tasks));

      s7::HostBignumTable ir_table;
      Tags ir_tags = Tags::build(ir_table);
      Built ir_built = test.build(ir_table, ir_tags);
      Val ir_ctx = ir_table.make_list(
          {ir_built.actions_tbl, ir_built.methods_tbl, ir_tags.as_list(ir_table)});
      std::vector<int64_t> ir_args = {ir_built.state, ir_built.tasks, ir_ctx};
      std::string ir_str = decode_plan(
          ir_table, s7::interpret(compiled.ir, func_index, ir_args, 50'000'000, &ir_table));

      s7::HostBignumTable machine_table;
      Tags machine_tags = Tags::build(machine_table);
      Built machine_built = test.build(machine_table, machine_tags);
      Val machine_ctx = machine_table.make_list(
          {machine_built.actions_tbl, machine_built.methods_tbl, machine_tags.as_list(machine_table)});
      Machine64 machine(compiled.elf, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});
      machine.set_userdata(&machine_table);
      Val machine_result = static_cast<Val>(machine.vmcall<50'000'000ull>(
          "plan", machine_built.state, machine_built.tasks, machine_ctx));
      std::string machine_str = decode_plan(machine_table, machine_result);

      if (oracle_str != test.expected || ir_str != test.expected || machine_str != test.expected) {
        fprintf(stderr, "FAIL %-40s expected=[%s] ref=[%s] ir=[%s] riscv=[%s]\n", test.name,
                test.expected, oracle_str.c_str(), ir_str.c_str(), machine_str.c_str());
        failures++;
      } else {
        printf("ok   %-40s -> %s\n", test.name, oracle_str.c_str());
      }
    } catch (const std::exception& e) {
      fprintf(stderr, "FAIL %-40s exception: %s\n", test.name, e.what());
      failures++;
    }
  }

  if (failures > 0) {
    fprintf(stderr, "FAIL: %d of %zu planner tests diverged\n", failures, tests.size());
    return 1;
  }
  printf("PASS: all %zu planner tests agree between the reference oracle, the IR oracle, and "
         "compiled RISC-V execution\n",
         tests.size());
  return 0;
}
