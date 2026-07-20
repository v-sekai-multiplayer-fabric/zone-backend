alias Taskweft.ReBAC

# ── Graph builders ────────────────────────────────────────────────────────────

# Flat graph: n direct OWNS edges from distinct subjects to the same object.
# Tests the direct-edge path with no membership chains.
defmodule Graphs do
  def flat(n, obj \\ "resource") do
    Enum.reduce(1..n, ReBAC.new_graph(), fn i, g ->
      ReBAC.add_edge(g, "user_#{i}", obj, "OWNS")
    end)
  end

  # Linear IS_MEMBER_OF chain: user → g1 → g2 → … → gN → resource.
  # The queried subject is at the leaf; group gN owns the resource.
  # Exercises the full transitive expansion path.
  def chain(depth, obj \\ "resource") do
    g = ReBAC.new_graph() |> ReBAC.add_edge("group_#{depth}", obj, "OWNS")

    Enum.reduce(depth..1//-1, g, fn i, acc ->
      if i > 1 do
        ReBAC.add_edge(acc, "group_#{i - 1}", "group_#{i}", "IS_MEMBER_OF")
      else
        ReBAC.add_edge(acc, "user_leaf", "group_1", "IS_MEMBER_OF")
      end
    end)
  end

  # Wide fan-out: n groups each owning the resource, user is member of all.
  # Exercises the expand IS_MEMBER_OF scan across many edges.
  def fan(n, obj \\ "resource") do
    base = ReBAC.new_graph()

    Enum.reduce(1..n, base, fn i, g ->
      g
      |> ReBAC.add_edge("group_#{i}", obj, "OWNS")
      |> ReBAC.add_edge("user", "group_#{i}", "IS_MEMBER_OF")
    end)
  end
end

flat_sm  = Graphs.flat(10)
flat_md  = Graphs.flat(100)
flat_lg  = Graphs.flat(1_000)

chain_sm = Graphs.chain(4)
chain_md = Graphs.chain(8)

fan_sm   = Graphs.fan(10)
fan_md   = Graphs.fan(100)
fan_lg   = Graphs.fan(1_000)

base_owns   = ~s({"type":"base","rel":"OWNS"})
union_expr  = ~s({"type":"union","a":{"type":"base","rel":"OWNS"},"b":{"type":"base","rel":"CONTROLS"}})

IO.puts("\n=== ReBAC benchmark (taskweft NIF via tw_rebac.hpp) ===\n")

Benchee.run(
  %{
    # ── Direct-edge hit (last subject in list) ─────────────────────────────
    "check_rel/direct hit  10 edges" => fn -> ReBAC.check_rel(flat_sm,  "user_10",    "OWNS", "resource") end,
    "check_rel/direct hit 100 edges" => fn -> ReBAC.check_rel(flat_md,  "user_100",   "OWNS", "resource") end,
    "check_rel/direct hit 1k edges"  => fn -> ReBAC.check_rel(flat_lg,  "user_1000",  "OWNS", "resource") end,

    # ── Direct-edge miss (subject not in graph) ────────────────────────────
    "check_rel/miss        10 edges" => fn -> ReBAC.check_rel(flat_sm,  "nobody", "OWNS", "resource") end,
    "check_rel/miss       100 edges" => fn -> ReBAC.check_rel(flat_md,  "nobody", "OWNS", "resource") end,
    "check_rel/miss        1k edges" => fn -> ReBAC.check_rel(flat_lg,  "nobody", "OWNS", "resource") end,

    # ── Union expr ────────────────────────────────────────────────────────
    "check/union hit  10 edges" => fn -> ReBAC.check(flat_sm, "user_10",   union_expr, "resource") end,
    "check/union hit 100 edges" => fn -> ReBAC.check(flat_md, "user_100",  union_expr, "resource") end,

    # ── IS_MEMBER_OF chain (deep transitivity) ────────────────────────────
    "check_rel/chain depth 4" => fn -> ReBAC.check_rel(chain_sm, "user_leaf", "OWNS", "resource") end,
    "check_rel/chain depth 8" => fn -> ReBAC.check_rel(chain_md, "user_leaf", "OWNS", "resource") end,

    # ── expand (all holders of a relation) ────────────────────────────────
    "expand/OWNS   10 direct" => fn -> ReBAC.expand(flat_sm, "OWNS", "resource") end,
    "expand/OWNS  100 direct" => fn -> ReBAC.expand(flat_md, "OWNS", "resource") end,
    "expand/OWNS   1k direct" => fn -> ReBAC.expand(flat_lg, "OWNS", "resource") end,

    # ── expand via IS_MEMBER_OF fan-out (exercises the O(n) edge scan) ───
    "expand/IS_MEMBER_OF fan  10" => fn -> ReBAC.expand(fan_sm, "OWNS", "resource") end,
    "expand/IS_MEMBER_OF fan 100" => fn -> ReBAC.expand(fan_md, "OWNS", "resource") end,
    "expand/IS_MEMBER_OF fan  1k" => fn -> ReBAC.expand(fan_lg, "OWNS", "resource") end,
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)
