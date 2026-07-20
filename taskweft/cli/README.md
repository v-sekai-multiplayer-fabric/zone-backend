<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# cli/ — legacy C++ CLI (dev tool only)

The shipped artifact is the Elixir CLI (`Taskweft.CLI`) packaged as a
standalone Burrito binary — see the top-level `README.md`. This C++ binary
predates that migration and is kept only as a thin dev tool for exercising
`taskweft_nif`'s planner directly, without the Elixir/MCP layer. It is not
built, tested, or released as part of the shipped `taskweft` binary.
