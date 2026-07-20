# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.Application do
  @moduledoc """
  OTP application for `:taskweft`.

  Three ways this boots, chosen by what's actually running it:

  1. **`taskweft_deploy` release** (hosted MCP web server, Fly.io production)
     — starts `TaskweftDeploy.Application.children/0` (a Cowboy endpoint).
     Detected via `RELEASE_NAME`, the env var `mix release` sets
     automatically at runtime — not a hand-rolled flag. Folded in from a
     formerly-separate `deploy/` Mix project (github.com/taskweft/deploy,
     then a `deploy/` subdirectory with its own mix.exs/mix.lock): one Mix
     project, one mix.lock, no synced-across-two-lockfiles class of bug.
  2. **`taskweft` release, Burrito-wrapped standalone binary** (issue #53) —
     starts a single `Task` that runs `Taskweft.CLI.main/0`, turning the
     binary into a CLI: subcommands that produce output print and halt, and
     `mcp` keeps the VM alive. Detected via the `__BURRITO` runtime marker;
     set `TASKWEFT_CLI=0` to suppress it even in the standalone binary.
  3. **Library dependency** (or `mix test` / `mix run`) — neither of the
     above applies, so this starts an empty supervision tree. No behaviour
     change for consumers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      cond do
        deploy_release?() ->
          TaskweftDeploy.Application.children()

        run_cli?() ->
          [Supervisor.child_spec({Task, fn -> Taskweft.CLI.main() end}, restart: :temporary)]

        true ->
          []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Taskweft.Supervisor)
  end

  defp deploy_release?, do: System.get_env("RELEASE_NAME") == "taskweft_deploy"

  defp run_cli? do
    System.get_env("TASKWEFT_CLI") != "0" and burrito_standalone?()
  end

  # The Burrito zig wrapper exports `__BURRITO=1` into the release runtime
  # (see burrito `src/erlang_launcher.zig`). Read it directly rather than
  # through `Burrito.Util`, whose module may not be loaded this early in boot.
  defp burrito_standalone? do
    System.get_env("__BURRITO") != nil
  end
end
