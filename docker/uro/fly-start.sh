#!/bin/sh
# Real production startup for the Burrito-wrapped uro release.
#
# AGENTS.md has documented this exact script's job for a while --
# migrate as gateway_admin, then serve as gateway_writer -- but the
# script itself never actually existed in this repo until now.
#
# Unlike a mix-based boot (`mix ecto.migrate`), a compiled release has
# no mix tasks at runtime: Uro.Release.migrate/0 (lib/uro/release.ex)
# is the real Phoenix-release pattern for this, invoked here via the
# release's own `eval` command.
set -e

echo "fly-start: running migrations (gateway_admin / Uro.Repo.Migration)"
/usr/local/bin/uro eval "Uro.Release.migrate()"

echo "fly-start: starting Uro.Endpoint (gateway_writer / Uro.Repo)"
exec /usr/local/bin/uro start
