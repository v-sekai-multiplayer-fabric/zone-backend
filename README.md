<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# multiplayer-fabric-taskweft

The planner server exposes the `plan`, `replan` tools and every bundled `priv/plans/{domains,problems}/*.jsonld` as a
resource.

Download the binary for your platform from the
[latest release](https://github.com/V-Sekai-fire/multiplayer-fabric-taskweft/releases).

```sh
taskweft plan <domain.jsonld>                     # plan from a self-contained file
taskweft plan --problem <domain> <problem>        # plan from split domain + problem
taskweft plan                                     # plan from JSON-LD on stdin
taskweft temporal <domain> [problem]              # plan + STN temporal metadata (JSON)
taskweft simulate <domain> [problem]              #   opts: --probs <json> --seed <int>
taskweft replan <fail_step> <domain> [problem]    # replan after a step failure (JSON)
taskweft mcp                                       # MCP server over stdio
taskweft mcp --http [--port N] [--host H]          # MCP server over HTTP
taskweft version                                   # version + build commit
taskweft help                                      # usage
```

## MCP client setup

Point your MCP config at the binary — no `mix`, no `cwd`, no toolchain:

```json
{
  "mcpServers": {
    "taskweft": {
      "command": "/path/to/taskweft",
      "args": ["mcp"]
    }
  }
}
```
