-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 K. S. Ernest (iFire) Lee
import Planner.Capabilities
import PlausibleWitnessDag

/-!
# MCP authorization — ReBAC model + witness certification

"Just enough" software verification for the hosted taskweft MCP server
(`taskweft/deploy`): *who may call the server* is modelled as a ReBAC
`HAS_CAPABILITY` reachability question over the real `Planner.Capabilities`
engine, and the existence of an authorized subject is certified by the
`PlausibleWitnessDag` iterative-deepening search.

Concrete authorization facts are additionally machine-checked by `decide`
(kernel-verified): a whitelisted login is authorized, a member inherits the
capability through `IS_MEMBER_OF`, and an outsider is denied. This mirrors the
Elixir gate (`TaskweftDeploy.OAuth.check_whitelist`) without adding runtime
structure the deploy doesn't need (YAGNI).
-/

open PlausibleWitnessDag

namespace MCPAuthWitness

/-- The MCP server, as a ReBAC object. -/
def resource : Entity := "mcp:taskweft"

/-- Authorization graph: the whitelisted login holds the capability directly; an
    org holds it and members inherit it through `IS_MEMBER_OF`. -/
def graph : List Relationship :=
  [ ⟨"fire", RelationType.HAS_CAPABILITY, resource⟩,
    ⟨"taskweft-org", RelationType.HAS_CAPABILITY, resource⟩,
    ⟨"contrib", RelationType.IS_MEMBER_OF, "taskweft-org"⟩ ]

/-- A subject is authorized iff it reaches `HAS_CAPABILITY resource`
    (fuel-bounded, via the real ReBAC relation-expression engine). -/
def authorized (who : Entity) : Bool :=
  checkRelationExpr graph who (RelationExpr.base RelationType.HAS_CAPABILITY) resource 8

-- Kernel-verified facts.
example : authorized "fire" = true := by decide
example : authorized "contrib" = true := by decide      -- inherited via IS_MEMBER_OF
example : authorized "eve" = false := by decide          -- not whitelisted
example : authorized "stranger" = false := by decide

/-- Candidate subject space searched for a witness of authorization. -/
def subjects : Array Entity := #["stranger", "eve", "fire", "contrib"]

/-- Witness predicate for the DAG driver: candidate index `i` witnesses
    authorization when `subjects[i]` is authorized. -/
def candidateIsWitness (_lvl : Level) (i : Nat) : Bool :=
  match subjects[i]? with
  | some who => authorized who
  | none => false

/-- Deterministic read-back: recover the first authorized subject. -/
def readback (_steps : Nat) : Readback Entity :=
  match (List.range subjects.size).find? (fun i => authorized (subjects.getD i "")) with
  | some i => { value := subjects.getD i "", found := true, witnessIdx := i, budgetHit := false }
  | none => { value := "", found := false, budgetHit := false }

/-- Certified witness search over the ReBAC graph, plus a soundness assertion. -/
def run : IO Unit := do
  let (who, lvl, tr) ← resolve "mcp-authorization" candidateIsWitness readback
  IO.println s!"witness: {who} (level {lvl}) outcome {repr tr.outcome}"
  unless authorized who && ! authorized "stranger" do
    throw (IO.userError "MCP authorization witness verification failed")
  IO.println "OK: MCP authorization is witnessed and sound"

end MCPAuthWitness

def main : IO Unit := MCPAuthWitness.run
