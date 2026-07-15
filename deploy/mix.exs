# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule TaskweftDeploy.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft_deploy,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [taskweft_deploy: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [
      # :inets/:ssl are only pulled in for completeness; GitHub calls go through req.
      extra_applications: [:logger],
      mod: {TaskweftDeploy.Application, []}
    ]
  end

  defp deps do
    [
      # The entire taskweft featureset — planner NIF, MCP server, JSON-LD loader —
      # in one dep. Its OTP app starts nothing unless it is the Burrito binary.
      # Path dep: this app now lives inside the taskweft monorepo (folded in
      # from the standalone taskweft/deploy repo — too much friction keeping
      # every feature change synced across a publish-then-bump-then-redeploy
      # chain across two repos). No more Hex publish required to pick up a
      # taskweft change here.
      {:taskweft, path: ".."},
      # The generic OAuth-to-MCP bridge (macaroons, GitHub OAuth, MCP bearer
      # guard) — deliberately stays its own repo/Hex package; it's genuinely
      # reusable and not taskweft-specific.
      {:oauth_mcp_bridge, "~> 0.1.0-dev"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end
end
