defmodule Taskweft.ReBAC do
  @moduledoc """
  Relationship-Based Access Control (ReBAC) graph engine.

  Wraps the C++ `tw_rebac.hpp` via Fine NIF. The graph is passed as a JSON
  string (wire format: `{"edges":[{"subject","object","rel"}],"definitions":{}}`).
  Relation expressions (RelExpr) are also JSON maps:

      {"type":"base","rel":"OWNS"}
      {"type":"union","a":{...},"b":{...}}
      {"type":"intersection","a":{...},"b":{...}}
      {"type":"difference","a":{...},"b":{...}}
      {"type":"tuple_to_userset","pivot_rel":"IS_MEMBER_OF","inner":{...}}

  Valid relation names: HAS_CAPABILITY, CONTROLS, OWNS, IS_MEMBER_OF,
  DELEGATED_TO, SUPERVISOR_OF, PARTNER_OF, CAN_ENTER, CAN_INSTANCE.
  """

  alias Taskweft.NIF

  @empty_graph ~s({"edges":[],"definitions":{}})

  @doc "Return an empty graph JSON string."
  def new_graph, do: @empty_graph

  @doc "Add a directed edge (subj)-[rel]->(obj) to the graph."
  def add_edge(graph_json, subj, obj, rel) do
    NIF.rebac_add_edge(graph_json, subj, obj, rel)
  end

  @doc """
  Check whether `subj` satisfies `expr_json` with respect to `obj`.

  `fuel` limits recursive expansion depth (default 8).
  Returns `true` or `false`.
  """
  def check(graph_json, subj, expr_json, obj, fuel \\ 8) do
    NIF.rebac_check(graph_json, subj, expr_json, obj, fuel)
  end

  @doc """
  Convenience helper for a simple base relation check.

      check_rel(graph, "alice", "OWNS", "resource_x")
  """
  def check_rel(graph_json, subj, rel, obj, fuel \\ 8) do
    expr = ~s({"type":"base","rel":"#{rel}"})
    NIF.rebac_check(graph_json, subj, expr, obj, fuel)
  end

  @doc """
  Expand rel → all subjects that hold `rel` to `obj`.

  Follows IS_MEMBER_OF transitive chains up to `fuel` hops.
  Returns a list of subject strings.
  """
  def expand(graph_json, rel, obj, fuel \\ 8) do
    NIF.rebac_expand(graph_json, rel, obj, fuel)
  end

  @doc """
  Parse relation edges from a list of memory facts.

  `facts_json` is a JSON array of `{content, trust_score?, ...}` objects.
  Sentences matching known verb phrases (owns, controls, delegates to, etc.)
  become edges. Returns a graph JSON string.
  """
  def parse_relation_edges(facts_json, trust_threshold \\ 0.5) do
    NIF.rebac_parse_relation_edges(facts_json, trust_threshold)
  end
end
