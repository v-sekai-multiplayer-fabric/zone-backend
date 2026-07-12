<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# multiplayer-fabric-taskweft

HTN planner server. Exposes the `plan` and `replan` tools, and every bundled
`priv/plans/{domains,problems}/*.jsonld` as a resource.

Download the binary from the
[latest release](https://github.com/V-Sekai-fire/multiplayer-fabric-taskweft/releases).

```sh
taskweft plan <domain.jsonld>        # plan: from a file, --problem <d> <p>, or stdin
taskweft temporal <domain> [problem] # plan + STN temporal metadata
taskweft simulate <domain> [problem] # plan under failure probs (--probs, --seed)
taskweft replan <fail_step> <domain> # replan after a step failure
taskweft mcp [--http [--port N]]     # MCP server: stdio, or HTTP
```

## MCP client

Point your MCP config at the binary — no `mix`, no toolchain:

```json
{ "mcpServers": { "taskweft": { "command": "/path/to/taskweft", "args": ["mcp"] } } }
```
