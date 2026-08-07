#!/bin/sh
# Entrypoint for multiplayer-fabric-crdb on Fly.io.
#
# Fly runs one machine here, not docker-compose.yml's separate
# crdb-certs-init sidecar, so this does both jobs: generate a real CA
# plus node/client certs once (persisted on the same mounted volume
# cockroach's own data lives on, so a restart reuses them instead of
# regenerating and invalidating every cert uro already trusts), then
# run the same start-single-node command compose already uses, then
# bootstrap the gateway_writer/gateway_admin roles AGENTS.md documents
# (DML-only vs DDL-capable), matching Uro.Repo's / Uro.Repo.Migration's
# already-established cert-based, password-less connection scheme.
set -e

CERTS_DIR=/cockroach/cockroach-data/certs

# Consider the cert set complete only if every file start-single-node and
# every client role actually needs is present. A previous, earlier
# experiment on this same volume left a partial certs/ directory behind
# (ca.crt only, no node cert) -- checking ca.crt alone caused this
# entrypoint to "reuse" that incomplete set and fail with "problem with
# node certificate: not found". If anything required is missing, wipe
# and regenerate the whole set together so the CA and every cert it
# signs are always internally consistent with each other.
certs_complete() {
	[ -f "$CERTS_DIR/ca.crt" ] && [ -f "$CERTS_DIR/node.crt" ] && [ -f "$CERTS_DIR/node.key" ] \
		&& [ -f "$CERTS_DIR/client.root.crt" ] \
		&& [ -f "$CERTS_DIR/client.gateway_writer.crt" ] \
		&& [ -f "$CERTS_DIR/client.gateway_admin.crt" ]
}

if ! certs_complete; then
	echo "entrypoint: certs missing or incomplete, wiping and generating a fresh set"
	rm -rf "$CERTS_DIR"
	mkdir -p "$CERTS_DIR"
	cockroach cert create-ca --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key" \
		--lifetime=876000h
	cockroach cert create-node localhost 127.0.0.1 ::1 "$FLY_PRIVATE_IP" \
		multiplayer-fabric-crdb.internal multiplayer-fabric-crdb.flycast \
		--certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key" --lifetime=800000h
	cockroach cert create-client root \
		--certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key" --lifetime=800000h
	cockroach cert create-client gateway_writer \
		--certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key" --lifetime=800000h
	cockroach cert create-client gateway_admin \
		--certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key" --lifetime=800000h
	echo "entrypoint: certs generated, first-boot bootstrap will run below"
	FIRST_BOOT=1
else
	echo "entrypoint: certs already exist on the volume, reusing"
	FIRST_BOOT=0
fi

/cockroach/cockroach.sh start-single-node \
	--certs-dir="$CERTS_DIR" --listen-addr=:26257 --http-addr=:8080 &
CRDB_PID=$!

trap 'echo "entrypoint: forwarding SIGTERM to cockroach"; kill -TERM "$CRDB_PID" 2>/dev/null; wait "$CRDB_PID"' TERM INT

# Deliberately NOT gated on $FIRST_BOOT: an earlier run of this script
# generated a fresh certs/ dir, got as far as CREATE DATABASE/CREATE USER,
# then failed on an invalid GRANT (CockroachDB 22.1 has no
# SELECT/INSERT/UPDATE/DELETE privilege at the DATABASE level, table-
# level or ALL TABLES IN SCHEMA only) -- gating this block on $FIRST_BOOT
# would mean a boot after that failure, with certs now already complete,
# skips the bootstrap forever, even though the roles/grants never
# finished. Every statement below is idempotent (IF NOT EXISTS, or a
# GRANT re-applying the same privilege), so running this every boot is
# safe and self-healing instead.
echo "entrypoint: waiting for cockroach to accept SQL connections"
i=0
while [ "$i" -lt 60 ]; do
	if cockroach sql --certs-dir="$CERTS_DIR" --host=localhost:26257 -e "SELECT 1" >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 1
done

echo "entrypoint: ensuring uro database and gateway_writer/gateway_admin roles/grants exist"
cockroach sql --certs-dir="$CERTS_DIR" --host=localhost:26257 -e "
	CREATE DATABASE IF NOT EXISTS uro;
	CREATE USER IF NOT EXISTS gateway_writer;
	CREATE USER IF NOT EXISTS gateway_admin;
	GRANT ALL ON DATABASE uro TO gateway_admin;
	GRANT CONNECT ON DATABASE uro TO gateway_writer;
"
# ALL TABLES IN SCHEMA only affects tables that already exist -- a no-op
# right now (uro's migrations have not created any yet), but re-running
# this every boot means it takes effect for real once they do, without
# needing a separate manual grant step after every future migration.
cockroach sql --certs-dir="$CERTS_DIR" --host=localhost:26257 --database=uro -e "
	GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO gateway_writer;
" 2>&1 || echo "entrypoint: table-level grant skipped (no tables yet, or already granted)"
echo "entrypoint: role/grant bootstrap complete"

wait "$CRDB_PID"
