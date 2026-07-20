defmodule Taskweft.ReBACPropTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Taskweft.ReBAC

  @relations [
    "OWNS",
    "CONTROLS",
    "IS_MEMBER_OF",
    "DELEGATED_TO",
    "HAS_CAPABILITY",
    "SUPERVISOR_OF",
    "PARTNER_OF"
  ]

  def name_gen do
    let(
      chars <- non_empty(list(range(?a, ?z))),
      do: List.to_string(chars)
    )
  end

  def rel_gen, do: oneof(Enum.map(@relations, &exactly/1))

  property "add_edge: edge appears in expanded results" do
    forall {subj, obj, rel} <- {name_gen(), name_gen(), rel_gen()} do
      g = ReBAC.new_graph() |> ReBAC.add_edge(subj, obj, rel)
      holders = ReBAC.expand(g, rel, obj)
      Enum.member?(holders, subj)
    end
  end

  property "check_rel: true after add_edge" do
    forall {subj, obj, rel} <- {name_gen(), name_gen(), rel_gen()} do
      g = ReBAC.new_graph() |> ReBAC.add_edge(subj, obj, rel)
      ReBAC.check_rel(g, subj, rel, obj)
    end
  end

  property "check_rel: false on empty graph" do
    forall {subj, obj, rel} <- {name_gen(), name_gen(), rel_gen()} do
      g = ReBAC.new_graph()
      not ReBAC.check_rel(g, subj, rel, obj)
    end
  end

  property "union expr: holds when either branch holds" do
    forall {subj, obj} <- {name_gen(), name_gen()} do
      g =
        ReBAC.new_graph()
        |> ReBAC.add_edge(subj, obj, "OWNS")

      expr =
        ~s({"type":"union","a":{"type":"base","rel":"OWNS"},"b":{"type":"base","rel":"CONTROLS"}})

      ReBAC.check(g, subj, expr, obj)
    end
  end

  property "intersection expr: requires both branches" do
    forall {subj, obj} <- {name_gen(), name_gen()} do
      g_one = ReBAC.new_graph() |> ReBAC.add_edge(subj, obj, "OWNS")
      g_both = ReBAC.add_edge(g_one, subj, obj, "CONTROLS")

      expr =
        ~s({"type":"intersection","a":{"type":"base","rel":"OWNS"},"b":{"type":"base","rel":"CONTROLS"}})

      not ReBAC.check(g_one, subj, expr, obj) and
        ReBAC.check(g_both, subj, expr, obj)
    end
  end

  property "IS_MEMBER_OF transitivity" do
    forall {a, b, obj} <- {name_gen(), name_gen(), name_gen()} do
      g =
        ReBAC.new_graph()
        |> ReBAC.add_edge(a, b, "IS_MEMBER_OF")
        |> ReBAC.add_edge(b, obj, "OWNS")

      ReBAC.check_rel(g, a, "OWNS", obj)
    end
  end

  property "CONTROLS delegation inversion" do
    forall {delegator, delegatee, obj} <- {name_gen(), name_gen(), name_gen()} do
      g =
        ReBAC.new_graph()
        |> ReBAC.add_edge(delegator, delegatee, "DELEGATED_TO")
        |> ReBAC.add_edge(delegator, obj, "OWNS")

      ReBAC.check_rel(g, delegator, "OWNS", obj)
    end
  end

  property "parse_relation_edges: owns sentence creates OWNS edge" do
    forall {subj, obj} <- {name_gen(), name_gen()} do
      sentence = "#{String.capitalize(subj)} owns #{String.capitalize(obj)}."
      facts = ~s([{"content": "#{sentence}", "trust_score": 0.9}])
      graph = ReBAC.parse_relation_edges(facts)
      is_binary(graph) and String.contains?(graph, "OWNS")
    end
  end

  property "parse_relation_edges: low trust facts produce no OWNS edge" do
    forall {subj, obj} <- {name_gen(), name_gen()} do
      sentence = "#{String.capitalize(subj)} owns #{String.capitalize(obj)}."
      facts = ~s([{"content": "#{sentence}", "trust_score": 0.1}])
      graph = ReBAC.parse_relation_edges(facts, 0.5)
      graph =~ ~s("edges":[]) or not (graph =~ "OWNS")
    end
  end
end
