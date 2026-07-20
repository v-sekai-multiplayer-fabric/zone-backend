---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: ops, fly
---

# 0011 Redeploy scope after Fly.io app loss — uro and crdb only

## Context

`fly apps list` showed `multiplayer-fabric-uro`, `-crdb`, `-gateway`,
`-zone`, `-baker`, and `-observability` all suspended with zero
machines — actually gone, not just scaled to zero.

## Decision Outcome

Chosen: redeploy **only `uro` and `crdb`**. `gateway`, `zone`, `baker`,
and `observability` stay dead — telemetry is being repointed to
AppSignal instead ([[0008-appsignal-for-otel-telemetry]]), and storage to
Tigris ([[0009-fly-tigris-s3-for-aria-storage]]), so the self-hosted
observability app has no remaining purpose; `gateway`/`zone`/`baker`
aren't needed for the current scope of work.

## Consequences

Good: smaller ops surface — two apps to babysit instead of six. Bad:
`crdb`'s data volume was also gone, so this is a **fresh, empty**
CockroachDB, not a restore; anything that depended on `gateway`,
`zone`, `baker`, or the old observability stack has no running
replacement yet and would need its own explicit redeploy decision
later.

## Confirmation

`multiplayer-fabric-crdb`: fresh 10GB volume created
(`vol_491w6557d3o53x3r`, region `iad`), built and deployed from source,
machine currently crash-looping (`exit_code=-1`) — not yet diagnosed.
`multiplayer-fabric-uro`: 14 secrets staged, deploy blocked by the
auto-mode safety classifier — not yet run. `gateway`/`zone`/`baker`/
`observability`: confirmed left suspended, no action taken.
