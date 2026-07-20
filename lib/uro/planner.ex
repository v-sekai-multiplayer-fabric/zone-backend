# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Planner do
  @moduledoc "Facade dispatching planning calls through `Uro.Ports.Planner`."

  def plan(domain_json), do: adapter().plan(domain_json)

  defp adapter, do: Application.get_env(:uro, :planner_adapter, Uro.Planner.TaskweftAdapter)
end
