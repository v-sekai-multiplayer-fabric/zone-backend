# AGENTS.md — multiplayer-fabric-taskweft

Guidance for AI coding agents working in this submodule.

## What this is

Elixir library wrapping a C++20 HTN planner NIF. See `Taskweft` moduledoc
(`lib/taskweft.ex`) for the full module map and domain JSON format notes.

The planner model is **RECTGTN** (Relationship-Enabled Capability-Temporal
Goal-Task-Network). [docs/rectgtn.md](docs/rectgtn.md) defines the acronym and
the golden/rejected JSON-LD shapes for the three task kinds (`TwCall`, `TwGoal`,
`TwMultiGoal`) — the MCP-facing contract to keep aligned with the `plan` tool
description in `taskweft/mcp`.

## Build and test

```sh
mix compile           # compiles C++ NIF via elixir_make
mix test --include property   # ExUnit + PropCheck property tests
```

## MCP

Two call paths — see `Taskweft.MCP.Server` moduledoc for details:

- **Runtime**: `mix taskweft.mcp` starts the stdio server; `Taskweft.MCP.Client` calls peer MCP servers.
- **Training time**: DSPy calls these tools from Python optimization loops (GEPA, BootstrapFewShot).

## Conventions

- All Elixir public functions return `{:ok, value}` or `{:error, reason}`.
- Property tests live alongside unit tests; run both with `--include property`.
- Every new `.ex` / `.exs` file needs SPDX headers:
  ```elixir
  # SPDX-License-Identifier: MIT
  # Copyright (c) 2026 K. S. Ernest (iFire) Lee
  ```
- Commit message style: sentence case, no `type(scope):` prefix.
  Example: `Add hrr_bundle NIF binding for phase-vector aggregation`
