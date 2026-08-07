# Fly.io deploy image for multiplayer-fabric-crdb.
#
# Root cause this fixes: the previously deployed crdb machine crash-looped
# on every boot with "failed to spawn command: /docker-entrypoint.sh: No
# such file or directory". ghcr.io/v-sekai/cockroach:latest's real
# entrypoint is /cockroach/cockroach.sh (confirmed via
# `skopeo inspect --config docker://ghcr.io/v-sekai/cockroach:latest`),
# not /docker-entrypoint.sh -- that path does not exist in this image at
# all. Whatever local Dockerfile previously set that override is gone
# (see docs/decisions/0011-fly-redeploy-scope-uro-and-crdb-only.md's own
# "Fly app loss" framing); it was never committed to this repo.
#
# This replaces that lost Dockerfile with one that matches
# docker-compose.yml's already-working local crdb setup: generate a real
# CA plus node/client certs once (crdb-certs-init's own job in compose,
# done here instead since Fly runs one machine, not a sidecar), then run
# the same `start-single-node` command compose already uses.
FROM ghcr.io/v-sekai/cockroach:latest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
