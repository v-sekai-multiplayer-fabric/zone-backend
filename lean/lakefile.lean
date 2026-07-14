import Lake
open Lake DSL

package «taskweft» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- Holographic Reduced Representations: algebra and formal properties
@[default_target]
lean_lib «HRR» where
  srcDir := "."

-- HTN planner: types, capabilities/ReBAC, blocks world, temporal, unified GTN
@[default_target]
lean_lib «Planner» where
  srcDir := "."

-- Zone protocol: port assignment and 100-byte packet layout
@[default_target]
lean_lib «ZoneProtocol» where
  srcDir := "."

-- "Just enough" software verification of the hosted MCP authorization
-- (taskweft/deploy): a ReBAC HAS_CAPABILITY witness certified by the
-- plausible iterative-deepening search. Kept out of the core Planner lib so
-- only this target pulls the plausible dependency.
require «plausible-witness-dag» from git
  "https://github.com/fire/plausible-witness-dag" @ "main"

@[default_target]
lean_exe «mcp_auth_witness» where
  root := `MCPAuthWitness
