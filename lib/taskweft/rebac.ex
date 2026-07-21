defmodule Taskweft.ReBAC do
  @moduledoc """
  Relationship-Based Access Control (ReBAC) graph engine.

  Wraps the C++ `tw_rebac.hpp` via Fine NIF. The graph is passed as a JSON
  string (wire format: `{"edges":[{"subject","object","rel"}],"definitions":{}}`).

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
  Convenience helper for a simple base relation check.

      check_rel(graph, "alice", "OWNS", "resource_x")

  `fuel` limits recursive expansion depth (default 8).
  """
  def check_rel(graph_json, subj, rel, obj, fuel \\ 8) do
    expr = ~s({"type":"base","rel":"#{rel}"})
    NIF.rebac_check(graph_json, subj, expr, obj, fuel)
  end
end
