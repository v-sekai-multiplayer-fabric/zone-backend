#!/usr/bin/env bash
# Imports CRDB certs from multiplayer-fabric-hosting into macOS Keychain.
# Run once per developer machine; re-run to rotate certs.
#
# Usage:
#   ./scripts/setup_keychain_certs.sh [certs-dir]
#
# Default certs-dir: ../../../multiplayer-fabric/multiplayer-fabric-hosting/certs/crdb
# relative to this script's location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_CERTS="${SCRIPT_DIR}/../../../multiplayer-fabric/multiplayer-fabric-hosting/certs/crdb"
CERTS_DIR="${1:-$DEFAULT_CERTS}"

if [[ ! -d "$CERTS_DIR" ]]; then
  echo "error: certs directory not found: $CERTS_DIR" >&2
  echo "hint: start the Docker stack first, or pass the certs dir as an argument." >&2
  exit 1
fi

SERVICE="multiplayer-fabric-crdb"

import_pem() {
  local account="$1"
  local file="$CERTS_DIR/$2"

  if [[ ! -f "$file" ]]; then
    echo "error: missing $file" >&2
    exit 1
  fi

  local b64
  b64=$(base64 < "$file")

  security delete-generic-password -a "$account" -s "$SERVICE" 2>/dev/null || true
  security add-generic-password -a "$account" -s "$SERVICE" -w "$b64"
  echo "  imported $account from $(basename "$file")"
}

echo "Importing CRDB certs into Keychain service '$SERVICE'..."
import_pem "ca-cert"     "ca.crt"
import_pem "client-cert" "client.root.crt"
import_pem "client-key"  "client.root.key"
echo "Done. Run 'mix test --include property' to verify."
