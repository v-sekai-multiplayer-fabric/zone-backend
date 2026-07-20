# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.ReBAC do
  @moduledoc """
  Facade dispatching ReBAC calls through `Uro.Ports.ReBAC`.

  Resolved from application config exactly like `UroLoop.commit/2`.
  """

  def new_graph, do: adapter().new_graph()
  def add_edge(graph, subj, obj, rel), do: adapter().add_edge(graph, subj, obj, rel)
  def check_rel(graph, subj, rel, obj), do: adapter().check_rel(graph, subj, rel, obj)

  defp adapter, do: Application.get_env(:uro, :rebac_adapter, Uro.ReBAC.TaskweftAdapter)
end
