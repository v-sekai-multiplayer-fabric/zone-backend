# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Planner.TaskweftAdapter do
  @moduledoc "Real adapter wrapping Taskweft.NIF.plan/1."
  @behaviour Uro.Ports.Planner

  @impl true
  def plan(domain_json), do: Taskweft.NIF.plan(domain_json)
end
