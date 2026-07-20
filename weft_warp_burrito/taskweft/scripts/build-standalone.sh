#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# One-step build of the standalone `taskweft` Burrito binaries.
#
# Runs on a Linux host (native, WSL, a container, or CI). Zig cross-compiles,
# so a single Linux host produces both the Linux and macOS binaries — the
# macOS wrapper links against zig's bundled libSystem stubs, which a real macOS
# host's SDK setup does not provide cleanly. The Windows binary must be built
# on Windows (Burrito's CopyERTS step can't lay out the Windows ERTS from a
# non-Windows host); build it with `mix release taskweft` on Windows.
#
# Usage (from the repo root, on Linux / WSL / Docker):
#   scripts/build-standalone.sh                       # linux_amd64 + macos_arm64
#   scripts/build-standalone.sh linux_amd64           # one target
#   TASKWEFT_SMOKE=1 scripts/build-standalone.sh linux_amd64
#                                                     # build + run the smoke test
#
# From Windows, run it through WSL:
#   wsl bash scripts/build-standalone.sh
#
# Output: ./burrito_out/taskweft_<target>[.exe]

set -euo pipefail

ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(linux_amd64 macos_arm64)

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Ensure the NIF compiler wrappers are executable regardless of git's exec bit.
chmod +x scripts/nif-compile scripts/zig-cc scripts/zig-cxx 2>/dev/null || true

# --- toolchain -------------------------------------------------------------
command -v xz >/dev/null || { echo "error: xz not found (Burrito needs it)"; exit 1; }
# sccache (optional) caches the NIF compile — used automatically by
# scripts/nif-compile when present on PATH.
command -v sccache >/dev/null && echo "sccache: $(sccache --version | head -1)"

zig_dir="${ZIG_DIR:-${HOME}/.local/zig-${ZIG_VERSION}}"
if [ ! -x "${zig_dir}/zig" ]; then
  echo "--> fetching zig ${ZIG_VERSION}"
  mkdir -p "${zig_dir}"
  curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C "${zig_dir}" --strip-components=1
fi
export PATH="${zig_dir}:${PATH}"
zig version

# --- build -----------------------------------------------------------------
export MIX_ENV=prod TASKWEFT_BURRITO=1
export TASKWEFT_COMMIT="${TASKWEFT_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"

mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null
mix deps.get

for target in "${TARGETS[@]}"; do
  echo "==> building ${target}"
  BURRITO_TARGET="${target}" mix release taskweft --overwrite

  if [ -n "${TASKWEFT_SMOKE:-}" ] && [ "${target}" = "linux_amd64" ]; then
    # Only linux_amd64 runs natively on an x86_64 Linux host.
    bin="burrito_out/taskweft_${target}"
    echo "==> smoke ${bin}"
    rm -rf "${HOME}/.local/share/.burrito" "${HOME}/.cache/burrito_file_cache" 2>/dev/null || true
    timeout 180 "${bin}" version </dev/null >/dev/null           # pre-warm self-extract
    timeout 60 "${bin}" version </dev/null | grep -E "^taskweft [0-9]+\.[0-9]+\.[0-9]+"
    timeout 60 "${bin}" plan priv/smoke/blocks_world.jsonld </dev/null | grep -E '^\[\['
  fi
done

echo "==> done:"
ls -la burrito_out/
