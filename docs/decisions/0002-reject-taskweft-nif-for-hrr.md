---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: hrr, taskweft
---

# 0002 Reject Taskweft.NIF for HRR tagging

## Context

`taskweft` is already a direct `zone-backend` dependency (`mix.exs:80`)
and ships a real, tested `Taskweft.NIF` HRR implementation (phase-based,
163 PropCheck properties) — using it directly would have eliminated
the NIF-bridge task entirely. Canonical record lives in
`multiplayer-fabric-manuals/decisions/20260720-reject-taskweft-nif-for-hrr.md`
(sibling org repo); this is a same-day backfill for zone-backend's own
decision trail toward [[0003-hrr-pure-elixir-no-nif-no-lean]].

## Decision Outcome

Rejected. V-Sekai is actively replacing `taskweft` (planner, ReBAC,
HRR) with the s7-Lisp-in-libriscv stack in `weft-warp-loop`. Adding a
new `zone-backend` dependency on `Taskweft.NIF` would adopt the exact
thing being migrated away from.

## Consequences

Good: stays consistent with the org-wide taskweft-to-s7 migration; no
new coupling to a deprecating dependency. Bad: forgoes an
already-working, already-tested HRR implementation in favor of
building a new one — which itself was later simplified further, see
[[0003-hrr-pure-elixir-no-nif-no-lean]].

## Confirmation

No new `taskweft`/`taskweft_nif` references added anywhere in
zone-backend's HRR/tagging work; `Uro.Tagging` calls only `Uro.Hrr`.
