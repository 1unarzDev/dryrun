#!/usr/bin/env bash
# Beacon latency baseline: starts a private gateway on 127.0.0.1:${PERF_PORT:-8792} (never the owner's 8788),
# fires synthetic fictional-household requests per role, and records ONLY timing/status/servedBy receipts.
# Usage: scripts/perf/beacon-latency.sh [runs-per-role=3] [roles=preparation,debrief,resources,director] [--gemini]
# Output: receipt JSON under /private/tmp/dryrun-perf, and the measured table in docs/integration/performance.md.
# Gateway stdout/stderr and the probe's stdout go to protected capture; this script never reads them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATEWAY_DIR="$ROOT/services/ai-orchestrator"
ENV_FILE="$GATEWAY_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="/Users/nicholascheng/dryrun/services/ai-orchestrator/.env"
[ -f "$ENV_FILE" ] || { echo "missing services/ai-orchestrator/.env" >&2; exit 1; }
RUNS="${1:-3}"; ROLES="${2:-preparation,debrief,resources,director}"; PROVIDER=codex
[ "${3:-}" = "--gemini" ] && PROVIDER=gemini
PORT="${PERF_PORT:-8792}"
case "$PORT" in 8788) echo "refusing the owner's port" >&2; exit 2 ;; esac
OUT=/private/tmp/dryrun-perf; mkdir -p "$OUT"; chmod 700 "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGDIR=/private/tmp/dryrun-protected/perf-gateway-$STAMP; mkdir -p "$LOGDIR"; chmod 700 "$LOGDIR"

(cd "$GATEWAY_DIR" && exec env PORT="$PORT" DRYRUN_LISTEN_HOST=127.0.0.1 DRYRUN_PROVIDER="$PROVIDER" \
  DRYRUN_CODEX_CAPABILITIES_FILE="$GATEWAY_DIR/profiles/codex-local-synthetic.json" \
  DRYRUN_MAX_USD="${DRYRUN_MAX_USD:-2}" DRYRUN_FEATURE_TURNS_PER_WINDOW=400 DRYRUN_DIRECTOR_STARTS_PER_WINDOW=120 \
  DRYRUN_DIRECTOR_TURNS_PER_WINDOW=600 DRYRUN_HTTP_REQUESTS_PER_WINDOW=1000 \
  node --env-file="$ENV_FILE" --import tsx src/server.ts >"$LOGDIR/stdout" 2>"$LOGDIR/stderr") &
GW=$!
cleanup() {
  pkill -P "$GW" 2>/dev/null || true; kill "$GW" 2>/dev/null || true
  # Only the listener we started on our own port.
  lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
}
trap cleanup EXIT
for _ in $(seq 1 120); do nc -z 127.0.0.1 "$PORT" 2>/dev/null && break; sleep 0.5; done
nc -z 127.0.0.1 "$PORT" || { echo "gateway did not start on $PORT" >&2; exit 1; }

# One capture per role (each under the 1800 s capture bound). PERF_PARALLEL=1 (default) runs the role streams
# concurrently, like the app's own background work; PERF_PARALLEL=0 runs them one after another.
RECEIPTS=(); PIDS=()
IFS=',' read -r -a ROLE_LIST <<<"$ROLES"
for role in "${ROLE_LIST[@]}"; do
  r="$OUT/beacon-latency-$STAMP-$role.json"; RECEIPTS+=("$r")
  (cd "$GATEWAY_DIR" && DRYRUN_SAFE_RECEIPT="$r" DRYRUN_PERF_URL="http://127.0.0.1:$PORT" DRYRUN_PERF_ENV="$ENV_FILE" \
    python3 "$ROOT/scripts/review/firewall.py" --timeout 1800 capture -- \
    node --import tsx scripts/beacon-latency.ts "$RUNS" "$role") &
  PIDS+=($!)
  [ "${PERF_PARALLEL:-1}" = 1 ] || wait "$!"
done
for p in "${PIDS[@]}"; do wait "$p" || true; done
python3 "$ROOT/scripts/perf/render-latency.py" "$ROOT/docs/integration/performance.md" "$PROVIDER" "${PERF_PARALLEL:-1}" "${RECEIPTS[@]}"
echo "receipts: ${RECEIPTS[*]}"
