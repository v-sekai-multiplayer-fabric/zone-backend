---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: telemetry
---

# 0008 AppSignal for OpenTelemetry

## Context

`multiplayer-fabric-observability` (self-hosted VictoriaMetrics/Tempo/
OTEL Collector) is being kept suspended rather than redeployed. `uro`'s
own OTel export (`config/prod.exs`, `opentelemetry_exporter` OTLP/HTTP)
needs a target that isn't that stack.

## Decision Outcome

Chosen: **AppSignal** (free-tier OTLP ingestion). Repoint-only —
`uro` already speaks OTLP/HTTP generically
(`OTEL_EXPORTER_OTLP_ENDPOINT` is already overridable), so this is
setting `OTEL_EXPORTER_OTLP_ENDPOINT` to AppSignal's OTLP endpoint plus
its API-key header, no new integration code.

## Consequences

Good: no self-hosted observability infra to run; managed service with
a free tier. Bad: AppSignal's free tier has real limits (data
retention/volume) not yet load-tested against this app's actual span
volume.

## Confirmation

Not yet done: create the AppSignal app + API key, set it as a Fly
secret, redeploy, confirm spans land in AppSignal.
