---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: storage
---

# 0009 Fly.io S3 (Tigris) for aria-storage

## Context

`aria_storage`'s Waffle S3 backend (`config :ex_aws, :s3`) is currently
pointed at a self-hosted VersityGW host, part of the now-suspended
`multiplayer-fabric-observability`/self-hosted stack that is being kept
dead rather than redeployed.

## Decision Outcome

Chosen: **Fly.io's S3-compatible object storage (Tigris)**. Repoint-only
— `aria_storage` already speaks any S3-compatible endpoint via
`ex_aws`, so this is pointing `config :ex_aws, :s3` (host/port/scheme)
at the Tigris endpoint + bucket instead of `VERSITYGW_HOST`.

## Consequences

Good: no self-hosted object-storage infra to run; managed service with
a free tier. Bad: Tigris egress/API differences from VersityGW (e.g.
any VersityGW-specific behavior the baker pipeline relies on) aren't
yet verified.

## Confirmation

Not yet done: create the Tigris bucket via `fly storage create`, set
it as a Fly secret, redeploy, confirm a chunk upload round-trips
through Tigris.
