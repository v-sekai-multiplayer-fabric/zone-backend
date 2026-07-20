#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Populate .env with random secrets before the first `docker compose up`.
# Safe to re-run — existing keys are never overwritten.
#
# Usage:
#   cd multiplayer-fabric-hosting
#   ./generate-secrets.sh
#   docker compose up -d

set -e

ENV_FILE="$(dirname "$0")/.env"
touch "$ENV_FILE"

rand20() {
  openssl rand -base64 30 | tr -d '\n/+=' | cut -c1-20
}

rand32() {
  openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-32
}

rand40() {
  openssl rand -base64 60 | tr -d '\n/+=' | cut -c1-40
}

rand64() {
  openssl rand -base64 64 | tr -d '\n/+=' | cut -c1-64
}

add_secret() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    echo "  ${key}: already set, skipping"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    echo "  ${key}: generated"
  fi
}

echo "Writing secrets to $ENV_FILE ..."
add_secret ADMIN_PASSWORD    "$(rand32)"
add_secret USER_PASSWORD     "$(rand32)"
add_secret PHOENIX_KEY_BASE  "$(rand64)"
add_secret JOKEN_SIGNER      "$(rand32)"
add_secret AWS_ACCESS_KEY_ID "$(rand20)"
add_secret AWS_SECRET_ACCESS_KEY "$(rand40)"

# WebTransport TLS cert for the Elixir zone server.
# Short-lived self-signed P-256 cert (14-day limit for WebTransport).
# multiplayer-fabric-zone-server/priv/ symlinks here.
CERT_DIR="$(dirname "$0")/certs"
ZONE_CERT="$CERT_DIR/zone-server.crt"
ZONE_KEY="$CERT_DIR/zone-server.key"
mkdir -p "$CERT_DIR"
if [ -f "$ZONE_CERT" ]; then
  echo "  zone-server cert: already exists, skipping"
else
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -keyout "$ZONE_KEY" -out "$ZONE_CERT" -days 14 -nodes \
    -subj "/CN=zone-server" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" 2>/dev/null
  echo "  zone-server cert: generated (14-day WebTransport cert)"
fi

echo "Done. Run: docker compose up -d"
