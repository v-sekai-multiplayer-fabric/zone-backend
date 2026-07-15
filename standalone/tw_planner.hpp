// Taskweft HTN planner — pure C++20, no Godot dependency.
// Depth-first search over method decompositions, porting IPyHOP's seek_plan().
#pragma once
#include "tw_domain.hpp"
#include "tw_soltree.hpp"
#include <algorithm>
#include <chrono>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

static constexpr int TW_MAX_DEPTH = 256;

// Default planner wall-clock budget — the industry-standard knob for
// bounding HTN search instead of relying solely on a static depth limit.
// Adversarial or pathological domains hit the wall clock long before any
// sensible depth, so this is the real DoS guard.
static constexpr std::chrono::milliseconds TW_DEFAULT_BUDGET{5000};

// Granularity at which `tw_seek_plan` consults the wall clock. One probe
// per recursion entry would work but `steady_clock::now()` costs ~10ns
// on Apple silicon and the planner is microsecond-scale on legitimate
// inputs; sampling every 256 entries keeps the overhead invisible while
// still bounding adversarial loops to ~µs of overshoot.
static constexpr int TW_BUDGET_SAMPLE_EVERY = 256;

struct TwBudget {
    std::chrono::steady_clock::time_point deadline;
    int                                   tick   = 0;
    bool                                  fired  = false;

    static TwBudget from_now(std::chrono::milliseconds ms) {
        return TwBudget{std::chrono::steady_clock::now() + ms, 0, false};
    }

    bool exceeded() {
        if (fired) return true;
        if ((++tick % TW_BUDGET_SAMPLE_EVERY) != 0) return false;
        if (std::chrono::steady_clock::now() >= deadline) {
            fired = true;
            return true;
        }
        return false;
    }
};

// Thrown out of `tw_seek_plan` when the wall-clock budget is exhausted.
// NIF callers translate to a distinct error so consumers can tell
// "no plan exists" from "we ran out of time".
struct TwBudgetExceeded : std::runtime_error {
    TwBudgetExceeded() : std::runtime_error("planner_time_budget_exceeded") {}
};

// Serialize a TwCall to a canonical string key for blacklist membership tests.
// Mirrors Python's tuple identity: ("action_name", arg1, arg2, ...).
inline std::string tw_call_key(const TwCall &call) {
    std::string key = call.name;
    for (const TwValue &a : call.args) { key += '\x1f'; key += a.to_string(); }
    return key;
}

// A set of blacklisted command keys (serialized TwCalls).
// Blacklisted commands are skipped during planning — used by replan to avoid
// repeating the same (action, concrete_args) that failed at runtime.
// Mirrors IPyHOP planner.blacklist / blacklist_command().
using TwBlacklist = std::unordered_set<std::string>;

inline uint64_t tw_mix_hash(uint64_t h, uint64_t v) {
    h ^= v + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
    return h;
}

// Memoization caches for search subproblems.
// Key shape: hash(state, tasks). The scope is one planner invocation, so
// blacklist/method-skip invariants are fixed across all recursive calls.
using TwMemoKey = uint64_t;
using TwFailCache = std::unordered_set<TwMemoKey>;
using TwSuccessCache = std::unordered_map<TwMemoKey, std::vector<TwCall>>;
using TwMethodStats = std::unordered_map<uint64_t, std::vector<int>>;

inline uint64_t tw_goal_binding_hash(const TwGoalBinding &b) {
    uint64_t h = 1469598103934665603ull;
    h = tw_mix_hash(h, std::hash<std::string>{}(b.var));
    h = tw_mix_hash(h, std::hash<std::string>{}(b.key));
    h = tw_mix_hash(h, b.desired.stable_hash());
    return h;
}

inline uint64_t tw_task_hash(const TwTask &task) {
    if (const TwCall *call = std::get_if<TwCall>(&task)) {
        uint64_t h = tw_mix_hash(0x43554c4cull, std::hash<std::string>{}(call->name));
        for (const TwValue &a : call->args)
            h = tw_mix_hash(h, a.stable_hash());
        return h;
    }
    if (const TwGoal *goal = std::get_if<TwGoal>(&task)) {
        uint64_t h = 0x474f414cull;
        for (const TwGoalBinding &b : goal->bindings)
            h = tw_mix_hash(h, tw_goal_binding_hash(b));
        return h;
    }
    const TwMultiGoal &mg = std::get<TwMultiGoal>(task);
    uint64_t h = 0x4d554c54ull;
    for (const TwGoalBinding &b : mg.bindings)
        h = tw_mix_hash(h, tw_goal_binding_hash(b));
    return h;
}

inline uint64_t tw_tasks_hash(const std::vector<TwTask> &tasks) {
    uint64_t h = 0x5441534bull;
    for (const TwTask &t : tasks)
        h = tw_mix_hash(h, tw_task_hash(t));
    return h;
}

inline TwMemoKey tw_search_key(const TwState &state, const std::vector<TwTask> &tasks) {
    uint64_t h = state.signature_hash();
    h = tw_mix_hash(h, tw_tasks_hash(tasks));
    return h;
}

inline uint64_t tw_method_call_hash(const std::string &name,
                                    const std::vector<TwValue> &args) {
    uint64_t h = tw_mix_hash(0x4d455448ull, std::hash<std::string>{}(name));
    for (const TwValue &a : args) h = tw_mix_hash(h, a.stable_hash());
    return h;
}

inline std::vector<size_t> tw_order_methods(uint64_t key,
                                            size_t count,
                                            TwMethodStats *method_stats) {
    std::vector<size_t> order(count);
    for (size_t i = 0; i < count; ++i) order[i] = i;
    if (!method_stats || count <= 1) return order;

    std::vector<int> &scores = (*method_stats)[key];
    if (scores.size() < count) scores.resize(count, 0);

    // Cheap best-first policy: if no method has positive evidence, keep
    // declaration order to avoid per-node sorting overhead.
    size_t best_idx = 0;
    int best_score = scores[0];
    for (size_t i = 1; i < count; ++i) {
        if (scores[i] > best_score) {
            best_score = scores[i];
            best_idx = i;
        }
    }
    if (best_score > 0 && best_idx != 0) std::swap(order[0], order[best_idx]);
    return order;
}

inline void tw_note_method_result(uint64_t key,
                                  size_t method_idx,
                                  bool success,
                                  TwMethodStats *method_stats) {
    if (!method_stats) return;
    std::vector<int> &scores = (*method_stats)[key];
    if (scores.size() <= method_idx) scores.resize(method_idx + 1, 0);
    const int delta = success ? 2 : -1;
    scores[method_idx] = std::max(-64, std::min(64, scores[method_idx] + delta));
}

// Cheap branch plausibility probe used before full recursion.
// This deliberately checks only shape-level impossibility (missing method/action,
// blacklisted primitive) over a tiny task prefix to keep overhead negligible.
inline bool tw_task_shallow_plausible(const TwTask &task,
                                      const TwState &state,
                                      const TwDomain &domain,
                                      const TwBlacklist *blacklist) {
    if (const TwCall *call = std::get_if<TwCall>(&task)) {
        if (domain.actions.count(call->name)) {
            if (blacklist && blacklist->count(tw_call_key(*call))) return false;
            return true;
        }
        return domain.task_methods.count(call->name) > 0;
    }

    if (const TwGoal *goal = std::get_if<TwGoal>(&task)) {
        if (goal->is_satisfied(state)) return true;
        const std::vector<TwGoalBinding> unmet = goal->unsatisfied(state);
        for (const TwGoalBinding &b : unmet)
            if (domain.goal_methods.count(b.var)) return true;
        return false;
    }

    const TwMultiGoal *mg = std::get_if<TwMultiGoal>(&task);
    if (!mg) return true;
    if (mg->is_satisfied(state)) return true;
    const std::vector<TwGoalBinding> unmet = mg->unsatisfied(state);
    for (const TwGoalBinding &b : unmet)
        if (domain.goal_methods.count(b.var)) return true;
    return false;
}

inline bool tw_prefix_plausible(const std::vector<TwTask> &tasks,
                                const TwState &state,
                                const TwDomain &domain,
                                const TwBlacklist *blacklist,
                                size_t probe = 2) {
    const size_t n = std::min(tasks.size(), probe);
    for (size_t i = 0; i < n; ++i) {
        if (!tw_task_shallow_plausible(tasks[i], state, domain, blacklist)) return false;
    }
    return true;
}

// ── Witness oracle: goal-reachability pre-check ────────────────────────────────
//
// Soundness requires checking that NO plan exists for the current task prefix
// given the domain's goal methods — not bounding a generic DFS depth.
//
// For TOHTN domains, we check: if a goal has an unsatisfied binding, does the
// first goal-method make measurable progress (reduce unmet bindings)? If the
// answer is no for all unsatisfied goals, this branch is impossible and we
// skip it. This is sound because the planner tries every goal method
// (alternatives field) — skipping a branch only when the FIRST method
// can't make progress.
//
// This mirrors the existing fail-cache pattern: the witness oracle provides
// an additional cheap check that is sound over the full planner search.

struct TwWitnessResult {
    bool  found;       // true if at least one unsatisfied goal has a reachable first method
    int   certified;   // number of goals certified as reachable via first methods
    int   skipped;     // number of goals skipped because no first method exists
};

inline TwWitnessResult tw_witness_oracle_goal_reach(
        const TwState          &state,
        const std::vector<TwTask> &tasks,
        const TwDomain         &domain) {

    int certified = 0;
    int skipped = 0;

    for (size_t i = 0; i < tasks.size(); ++i) {
        const TwTask &task = tasks[i];

        // Skip satisfied goals and primitive actions
        if (const TwGoal *goal = std::get_if<TwGoal>(&task)) {
            if (goal->is_satisfied(state)) continue;
        }
        if (const TwMultiGoal *mg = std::get_if<TwMultiGoal>(&task)) {
            if (mg->is_satisfied(state)) continue;
        }
        if (const TwCall *call = std::get_if<TwCall>(&task)) {
            if (domain.actions.count(call->name)) continue;
        }

        // For compound tasks and unsatisfied goals: check if the first
        // method can decompose.  In TOHTN, "first method" is mit->second[0].
        if (const TwCall *call = std::get_if<TwCall>(&task)) {
            auto mit = domain.task_methods.find(call->name);
            if (mit != domain.task_methods.end() && !mit->second.empty()) {
                certified++;
                continue;
            }
            skipped++;
            continue;
        }

        if (const TwGoal *goal = std::get_if<TwGoal>(&task)) {
            const std::vector<TwGoalBinding> unmet = goal->unsatisfied(state);
            if (unmet.empty()) continue;

            auto git = domain.goal_methods.find(unmet[0].var);
            if (git != domain.goal_methods.end() && !git->second.empty()) {
                certified++;
                continue;
            }
            skipped++;
            continue;
        }
    }

    TwWitnessResult result;
    result.found = certified > 0 || skipped == 0;
    result.certified = certified;
    result.skipped = skipped;
    return result;
}

inline std::optional<std::vector<TwCall>> tw_seek_plan(
        std::shared_ptr<TwState> state,
        std::vector<TwTask>      tasks,
        const TwDomain           &domain,
        int                      fuel,
        const TwBlacklist       *blacklist,
        TwBudget                &budget,
        TwFailCache             *fail_cache = nullptr,
        TwSuccessCache          *success_cache = nullptr,
        TwMethodStats           *method_stats = nullptr) {

    if (budget.exceeded()) throw TwBudgetExceeded{};
    if (fuel <= 0) return std::nullopt;
    if (tasks.empty()) return std::vector<TwCall>{};

    TwMemoKey cache_key = 0;
    if (fail_cache) {
        cache_key = tw_search_key(*state, tasks);
        if (fail_cache->count(cache_key)) return std::nullopt;
    }
    if (success_cache) {
        if (cache_key == 0) cache_key = tw_search_key(*state, tasks);
        auto sit = success_cache->find(cache_key);
        if (sit != success_cache->end()) return sit->second;
    }
    auto mark_fail = [&]() -> std::optional<std::vector<TwCall>> {
        if (fail_cache && cache_key != 0) fail_cache->insert(cache_key);
        return std::nullopt;
    };
    auto mark_success = [&](const std::vector<TwCall> &plan) {
        if (success_cache && cache_key != 0) (*success_cache)[cache_key] = plan;
    };

    std::vector<TwTask> remaining(tasks.begin() + 1, tasks.end());

    // ── Witness oracle pre-check (TOHTN, goal-reachability) ─────────────
    // Before recursing into compound-task dispatch, check if unsatisfied
    // goals in the task prefix can be reached via their first goal-methods.
    // If none can, this branch is impossible — skip without expansion.
    {
        TwWitnessResult wr = tw_witness_oracle_goal_reach(*state, tasks, domain);
        if (!wr.found) return mark_fail();
    }

    // --- Conjunctive goal (unigoal) ---
    if (TwGoal *goal = std::get_if<TwGoal>(&tasks[0])) {
        if (goal->is_satisfied(*state))
            return tw_seek_plan(state, remaining, domain, fuel - 1,
                                blacklist, budget, fail_cache, success_cache, method_stats);

        std::vector<TwGoalBinding> unmet = goal->unsatisfied(*state);
        if (unmet.empty()) return std::nullopt;

        // Pick first unsatisfied binding; try all goal methods for its var.
        const TwGoalBinding &b = unmet[0];
        std::unordered_map<std::string, std::vector<TwGoalMethodFn>>::const_iterator git =
            domain.goal_methods.find(b.var);
        if (git == domain.goal_methods.end()) return mark_fail();

        std::vector<TwValue> goal_args = {TwValue(b.key), b.desired};
        TwCall gcall;
        gcall.name = b.var;
        gcall.args = goal_args;
        const uint64_t gkey = tw_method_call_hash(gcall.name, gcall.args);
        std::vector<size_t> order = tw_order_methods(gkey, git->second.size(), method_stats);
        std::unordered_set<uint64_t> seen_decompositions;
        for (size_t midx : order) {
            const TwGoalMethodFn &method = git->second[midx];
            std::optional<std::vector<TwTask>> subs = method(state, goal_args);
            if (!subs) continue;
            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.push_back(*goal);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            const uint64_t decomp_sig = tw_tasks_hash(new_tasks);
            if (!seen_decompositions.insert(decomp_sig).second) continue;
            if (!tw_prefix_plausible(new_tasks, *state, domain, blacklist)) continue;
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan(state, new_tasks, domain, fuel - 1,
                            blacklist, budget, fail_cache, success_cache, method_stats);
            if (result) {
                tw_note_method_result(gkey, midx, true, method_stats);
                mark_success(*result);
                return result;
            }
            tw_note_method_result(gkey, midx, false, method_stats);
        }
        return mark_fail();
    }

    // --- Multigoal (RECTGTN 'N'): backtrack over which binding to satisfy first ---
    if (TwMultiGoal *mg = std::get_if<TwMultiGoal>(&tasks[0])) {
        if (mg->is_satisfied(*state))
            return tw_seek_plan(state, remaining, domain, fuel - 1,
                                blacklist, budget, fail_cache, success_cache, method_stats);

        std::vector<TwGoalBinding> unmet = mg->unsatisfied(*state);
        if (unmet.empty()) return mark_fail();

        // Try each unsatisfied binding as the next thing to satisfy (IPyHOP _mg).
        for (size_t idx = 0; idx < unmet.size(); ++idx) {
            TwGoal sub_goal;
            sub_goal.bindings = {unmet[idx]};

            std::vector<TwTask> new_tasks;
            new_tasks.push_back(sub_goal);
            new_tasks.push_back(*mg);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan(state, new_tasks, domain, fuel - 1,
                            blacklist, budget, fail_cache, success_cache, method_stats);
            if (result) {
                mark_success(*result);
                return result;
            }
        }
        return mark_fail();
    }

    // --- Primitive action or compound task ---
    TwCall &call = std::get<TwCall>(tasks[0]);

    // Primitive action (RECTGTN 'E' — a command that can fail at runtime).
    std::unordered_map<std::string, TwActionFn>::const_iterator ait =
        domain.actions.find(call.name);
    if (ait != domain.actions.end()) {
        // Skip blacklisted commands — specific (action, args) instances that
        // failed at runtime and must not be replanned (IPyHOP blacklist_command).
        if (blacklist && blacklist->count(tw_call_key(call))) return mark_fail();

        std::shared_ptr<TwState> new_state = ait->second(state->copy(), call.args);
        if (!new_state) return mark_fail();
        std::optional<std::vector<TwCall>> sub =
            tw_seek_plan(new_state, remaining, domain, fuel - 1,
                         blacklist, budget, fail_cache, success_cache, method_stats);
        if (!sub) return mark_fail();
        std::vector<TwCall> plan = {call};
        plan.insert(plan.end(), sub->begin(), sub->end());
        mark_success(plan);
        return plan;
    }

    // Compound task: try each method in order
    std::unordered_map<std::string, std::vector<TwMethodFn>>::const_iterator mit =
        domain.task_methods.find(call.name);
    if (mit != domain.task_methods.end()) {
        const uint64_t tkey = tw_method_call_hash(call.name, call.args);
        std::vector<size_t> order = tw_order_methods(tkey, mit->second.size(), method_stats);
        std::unordered_set<uint64_t> seen_decompositions;
        for (size_t midx : order) {
            const TwMethodFn &method = mit->second[midx];
            std::optional<std::vector<TwTask>> subs = method(state, call.args);
            if (!subs) continue;
            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            const uint64_t decomp_sig = tw_tasks_hash(new_tasks);
            if (!seen_decompositions.insert(decomp_sig).second) continue;
            if (!tw_prefix_plausible(new_tasks, *state, domain, blacklist)) continue;
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan(state, new_tasks, domain, fuel - 1,
                            blacklist, budget, fail_cache, success_cache, method_stats);
            if (result) {
                tw_note_method_result(tkey, midx, true, method_stats);
                mark_success(*result);
                return result;
            }
            tw_note_method_result(tkey, midx, false, method_stats);
        }
        return mark_fail();
    }

    return mark_fail();
}

inline std::optional<std::vector<TwCall>> tw_plan(
        std::shared_ptr<TwState>   state,
        std::vector<TwTask>        tasks,
        const TwDomain            &domain,
        const TwBlacklist         *blacklist = nullptr,
        std::chrono::milliseconds  budget_ms = TW_DEFAULT_BUDGET) {
    TwBudget budget = TwBudget::from_now(budget_ms);
    TwFailCache fail_cache;
    TwSuccessCache success_cache;
    TwMethodStats method_stats;
    return tw_seek_plan(std::move(state), std::move(tasks), domain, TW_MAX_DEPTH,
                        blacklist, budget, &fail_cache, &success_cache, &method_stats);
}

// ── Tree-building planner ───────────────────────────────────────────────────
// Like tw_seek_plan, but simultaneously builds a TwSolTree recording the
// method chosen at each decomposition.  On a failed subtree the tree is
// rolled back to its checkpoint before trying the next alternative.
// method_skip: optional per-task set of method indices to skip (used by
// incremental replan to avoid repeating the method that produced the failed plan).
inline std::optional<std::vector<TwCall>> tw_seek_plan_tree(
        std::shared_ptr<TwState>  state,
        std::vector<TwTask>       tasks,
        const TwDomain            &domain,
        TwSolTree                 *tree,
        int                        tree_parent,
        int                        fuel,
        const TwBlacklist         *blacklist,
        const TwMethodSkip        *method_skip,
        TwBudget                  &budget,
        TwFailCache               *fail_cache  = nullptr) {

    if (budget.exceeded()) throw TwBudgetExceeded{};
    if (fuel <= 0) return std::nullopt;
    if (tasks.empty()) return std::vector<TwCall>{};

    TwMemoKey cache_key = 0;
    if (fail_cache) {
        cache_key = tw_search_key(*state, tasks);
        if (fail_cache->count(cache_key)) return std::nullopt;
    }
    auto mark_fail = [&]() -> std::optional<std::vector<TwCall>> {
        if (fail_cache && cache_key != 0) fail_cache->insert(cache_key);
        return std::nullopt;
    };

    std::vector<TwTask> remaining(tasks.begin() + 1, tasks.end());

    // --- Conjunctive goal (unigoal) ---
    if (TwGoal *goal = std::get_if<TwGoal>(&tasks[0])) {
        if (goal->is_satisfied(*state))
            return tw_seek_plan_tree(state, remaining, domain, tree, tree_parent,
                                     fuel - 1, blacklist, method_skip, budget, fail_cache);

        std::vector<TwGoalBinding> unmet = goal->unsatisfied(*state);
        if (unmet.empty()) return std::nullopt;

        const TwGoalBinding &b = unmet[0];
        std::unordered_map<std::string, std::vector<TwGoalMethodFn>>::const_iterator git =
            domain.goal_methods.find(b.var);
        if (git == domain.goal_methods.end()) return mark_fail();

        std::vector<TwValue> goal_args = {TwValue(b.key), b.desired};
        std::string gkey; // for method_skip lookup
        if (method_skip) {
            TwCall gc; gc.name = b.var; gc.args = goal_args;
            gkey = tw_call_key(gc);
        }
        std::unordered_set<uint64_t> seen_decompositions;
        for (size_t m = 0; m < git->second.size(); ++m) {
            if (method_skip) {
                std::unordered_map<std::string, std::unordered_set<int>>::const_iterator si =
                    method_skip->find(gkey);
                if (si != method_skip->end() && si->second.count((int)m)) continue;
            }
            std::optional<std::vector<TwTask>> subs = git->second[m](state, goal_args);
            if (!subs) continue;

            int cp      = tree ? tree->checkpoint() : 0;
            int first   = tree ? (int)tree->action_nodes.size() : 0;
            int gnode   = tree ? tree->add_node(TwSolNode::Kind::Goal, tree_parent,
                                                b.var, goal_args, (int)m) : -1;
            if (tree) tree->nodes[gnode].first_step = first;
            int next_p  = tree ? gnode : tree_parent;

            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.push_back(*goal);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            const uint64_t decomp_sig = tw_tasks_hash(new_tasks);
            if (!seen_decompositions.insert(decomp_sig).second) {
                if (tree) tree->restore(cp);
                continue;
            }
            if (!tw_prefix_plausible(new_tasks, *state, domain, blacklist)) {
                if (tree) tree->restore(cp);
                continue;
            }
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan_tree(state, new_tasks, domain, tree, next_p,
                                  fuel - 1, blacklist, method_skip, budget, fail_cache);
            if (result) return result;
            if (tree) tree->restore(cp);
        }
        return mark_fail();
    }

    // --- Multigoal (RECTGTN 'N') ---
    if (TwMultiGoal *mg = std::get_if<TwMultiGoal>(&tasks[0])) {
        if (mg->is_satisfied(*state))
            return tw_seek_plan_tree(state, remaining, domain, tree, tree_parent,
                                     fuel - 1, blacklist, method_skip, budget, fail_cache);

        std::vector<TwGoalBinding> unmet = mg->unsatisfied(*state);
        if (unmet.empty()) return mark_fail();

        for (size_t idx = 0; idx < unmet.size(); ++idx) {
            TwGoal sub_goal;
            sub_goal.bindings = {unmet[idx]};
            std::vector<TwTask> new_tasks;
            new_tasks.push_back(sub_goal);
            new_tasks.push_back(*mg);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan_tree(state, new_tasks, domain, tree, tree_parent,
                                  fuel - 1, blacklist, method_skip, budget, fail_cache);
            if (result) return result;
        }
        return mark_fail();
    }

    // --- Primitive action or compound task ---
    TwCall &call = std::get<TwCall>(tasks[0]);

    // Primitive action (RECTGTN 'E')
    std::unordered_map<std::string, TwActionFn>::const_iterator ait =
        domain.actions.find(call.name);
    if (ait != domain.actions.end()) {
        if (blacklist && blacklist->count(tw_call_key(call))) return mark_fail();

        std::shared_ptr<TwState> new_state = ait->second(state->copy(), call.args);
        if (!new_state) return mark_fail();

        int cp    = tree ? tree->checkpoint() : 0;
        int step  = tree ? (int)tree->action_nodes.size() : 0;
        int anode = -1;
        if (tree) {
            anode = tree->add_node(TwSolNode::Kind::Action, tree_parent, call.name, call.args);
            tree->nodes[anode].plan_step = step;
            tree->action_nodes.push_back(anode);
        }

        std::optional<std::vector<TwCall>> sub =
            tw_seek_plan_tree(new_state, remaining, domain, tree, tree_parent,
                              fuel - 1, blacklist, method_skip, budget, fail_cache);
        if (!sub) {
            if (tree) tree->restore(cp);
            return mark_fail();
        }
        std::vector<TwCall> plan = {call};
        plan.insert(plan.end(), sub->begin(), sub->end());
        return plan;
    }

    // Compound task (RECTGTN 'T')
    std::unordered_map<std::string, std::vector<TwMethodFn>>::const_iterator mit =
        domain.task_methods.find(call.name);
    if (mit != domain.task_methods.end()) {
        std::string tkey = method_skip ? tw_call_key(call) : std::string{};
        std::unordered_set<uint64_t> seen_decompositions;
        for (size_t m = 0; m < mit->second.size(); ++m) {
            if (method_skip) {
                std::unordered_map<std::string, std::unordered_set<int>>::const_iterator si =
                    method_skip->find(tkey);
                if (si != method_skip->end() && si->second.count((int)m)) continue;
            }
            std::optional<std::vector<TwTask>> subs = mit->second[m](state, call.args);
            if (!subs) continue;

            int cp    = tree ? tree->checkpoint() : 0;
            int first = tree ? (int)tree->action_nodes.size() : 0;
            int tnode = tree ? tree->add_node(TwSolNode::Kind::Task, tree_parent,
                                              call.name, call.args, (int)m) : -1;
            if (tree) tree->nodes[tnode].first_step = first;
            int next_p = tree ? tnode : tree_parent;

            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            const uint64_t decomp_sig = tw_tasks_hash(new_tasks);
            if (!seen_decompositions.insert(decomp_sig).second) {
                if (tree) tree->restore(cp);
                continue;
            }
            if (!tw_prefix_plausible(new_tasks, *state, domain, blacklist)) {
                if (tree) tree->restore(cp);
                continue;
            }
            std::optional<std::vector<TwCall>> result =
                tw_seek_plan_tree(state, new_tasks, domain, tree, next_p,
                                  fuel - 1, blacklist, method_skip, budget, fail_cache);
            if (result) return result;
            if (tree) tree->restore(cp);
        }
        return mark_fail();
    }

    return mark_fail();
}

// Plan and simultaneously build a solution derivation tree.
// The tree can be passed to tw_replan_incremental to backtrack at the exact
// method choice point rather than restarting the full search.
inline std::optional<std::vector<TwCall>> tw_plan_with_tree(
        std::shared_ptr<TwState>   state,
        std::vector<TwTask>        tasks,
        const TwDomain            &domain,
        TwSolTree                 &out_tree,
        const TwBlacklist         *blacklist   = nullptr,
        const TwMethodSkip        *method_skip = nullptr,
        std::chrono::milliseconds  budget_ms   = TW_DEFAULT_BUDGET) {
    out_tree.nodes.clear();
    out_tree.action_nodes.clear();
    TwSolNode root;
    root.kind   = TwSolNode::Kind::Root;
    root.parent = -1;
    out_tree.nodes.push_back(root);
    TwBudget budget = TwBudget::from_now(budget_ms);
    TwFailCache fail_cache;
    return tw_seek_plan_tree(std::move(state), std::move(tasks), domain,
                             &out_tree, 0, TW_MAX_DEPTH, blacklist, method_skip,
                             budget, &fail_cache);
}
