#!/usr/bin/env bash
# Drive verification on an external Mac over SSH from this (Linux) machine, then pull the artifacts back.
# Usage: scripts/remote-mac.sh <user@mac-host> <verify|screens|doctor|device> [script args...]
#   e.g. scripts/remote-mac.sh me@studio.local screens --locales en --screens fire,plan
#        scripts/remote-mac.sh me@studio.local verify
# Env: REMOTE_DIR (default ~/dryrun-remote on the Mac), SSH_OPTS.
# The Mac needs Xcode, XcodeGen (brew install xcodegen), and Remote Login enabled (System Settings > General > Sharing).
# Only the repository is synced (fictional data). Device signing over SSH may need: security unlock-keychain.
set -euo pipefail
HOST="${1:?usage: remote-mac.sh <user@host> <verify|screens|doctor|device> [args]}"
CMD="${2:?missing command}"; shift 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_DIR="${REMOTE_DIR:-dryrun-remote}"
SSH_OPTS="${SSH_OPTS:-}"

case "$CMD" in verify|screens|doctor|device) ;; *) echo "unknown command $CMD" >&2; exit 2 ;; esac

echo "==> Syncing repository to $HOST:$REMOTE_DIR"
# shellcheck disable=SC2086
rsync -az --delete -e "ssh $SSH_OPTS" \
  --exclude .git/ --exclude node_modules/ --exclude '.build*/' --exclude artifacts/ --exclude '*.xcodeproj/' \
  "$ROOT/" "$HOST:$REMOTE_DIR/"

echo "==> Running scripts/mac/$CMD.sh on the Mac"
QUOTED_ARGS=""
for a in "$@"; do QUOTED_ARGS="$QUOTED_ARGS $(printf '%q' "$a")"; done
# Login shell so Homebrew (xcodegen, pnpm) is on PATH.
# shellcheck disable=SC2086
ssh -t $SSH_OPTS "$HOST" "bash -lc 'cd $REMOTE_DIR && scripts/mac/$CMD.sh$QUOTED_ARGS'" || echo "(remote script reported failures; fetching artifacts anyway)"

echo "==> Fetching artifacts"
mkdir -p "$ROOT/artifacts"
# shellcheck disable=SC2086
rsync -az -e "ssh $SSH_OPTS" "$HOST:$REMOTE_DIR/artifacts/" "$ROOT/artifacts/" || true
# shellcheck disable=SC2012  # display only
ls -1t "$ROOT/artifacts" | head -3 | sed "s#^#    artifacts/#"
