#!/usr/bin/env bash
# Run SwiftPM for a package inside the swift:6.2 Linux container (no Xcode on this host).
# Usage: scripts/swift.sh <package-dir> <swift args...>
# Env: DRYRUN_SCRATCH=<name> gives each agent/lane its own build dir (default: "default").
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$1"; shift
SCRATCH="${DRYRUN_SCRATCH:-default}"
mkdir -p "$ROOT/.build-linux/$SCRATCH" "$ROOT/.build-linux/swiftpm-cache"
exec docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp/home -e DRYRUN_WRITE_FIXTURES="${DRYRUN_WRITE_FIXTURES:-}" -e DRYRUN_DUMP="${DRYRUN_DUMP:-}" \
  -v "$ROOT:/repo" -v "$ROOT/.build-linux/swiftpm-cache:/tmp/home" -w "/repo/$PKG" swift:6.2 \
  swift "$@" --scratch-path "/repo/.build-linux/$SCRATCH/$(echo "$PKG" | tr / _)"
