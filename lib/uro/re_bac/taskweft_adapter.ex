# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.ReBAC.TaskweftAdapter do
  @moduledoc "Real adapter wrapping Taskweft.ReBAC 1:1."
  @behaviour Uro.Ports.ReBAC

  @impl true
  def new_graph, do: Taskweft.ReBAC.new_graph()

  @impl true
  def add_edge(graph, subj, obj, rel), do: Taskweft.ReBAC.add_edge(graph, subj, obj, rel)

  @impl true
  def check_rel(graph, subj, rel, obj), do: Taskweft.ReBAC.check_rel(graph, subj, rel, obj)
end
