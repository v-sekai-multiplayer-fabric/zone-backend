# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # Attach OpenTelemetry instrumentation to Phoenix + Ecto. Span exporting
    # is configured via :opentelemetry / :opentelemetry_exporter in
    # config/prod.exs.
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:uro, :repo])

    children =
      if System.get_env("MINIMAL_START") == "true",
        do: [],
        else:
          [
            Uro.Repo,
            Uro.Repo.Migration,
            Uro.Endpoint,
            Uro.VSekai.ZoneJanitor,
            Uro.Pow.DetsCache,
            {Phoenix.PubSub, [name: Uro.PubSub, adapter: Phoenix.PubSub.PG2]},
            ExMarcel.TableWrapper,

            # ExMarcel
            {Task, fn -> Uro.Helpers.Validation.init_extra_extensions() end}
          ] ++ rebac_sandbox_children() ++ planner_sandbox_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Uro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Config-flip (RFD 0022, defaulted on since RFD 0038): only boot the
  # compiled-Scheme ReBAC program when it is actually selected, so an
  # environment that overrides :rebac_adapter to something else never
  # depends on priv/rebac.elf existing.
  defp rebac_sandbox_children do
    if Application.get_env(:uro, :rebac_adapter) == Uro.ReBAC.SandboxAdapter do
      elf = File.read!(Path.join(:code.priv_dir(:uro), "rebac.elf"))

      [
        Supervisor.child_spec(
          {WeftWarpBurrito.Program, elf: elf, name: Uro.ReBAC.SandboxAdapter.Program},
          id: Uro.ReBAC.SandboxAdapter.Program
        )
      ]
    else
      []
    end
  end

  # Config-flip (RFD 0023, defaulted on since RFD 0038): only boot the
  # compiled-Scheme planner program when it is actually selected, so an
  # environment that overrides :planner_adapter to something else never
  # depends on priv/planner.elf existing.
  defp planner_sandbox_children do
    if Application.get_env(:uro, :planner_adapter) == Uro.Planner.SandboxAdapter do
      elf = File.read!(Path.join(:code.priv_dir(:uro), "planner.elf"))

      [
        Supervisor.child_spec(
          {WeftWarpBurrito.Program, elf: elf, name: Uro.Planner.SandboxAdapter.Program},
          id: Uro.Planner.SandboxAdapter.Program
        )
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Uro.Endpoint.config_change(changed, removed)
    :ok
  end
end
