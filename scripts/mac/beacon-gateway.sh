#!/usr/bin/env bash
# Run Beacon's gateway on this Mac so the phone app works when opened from the home screen, with no cable.
# Usage: scripts/mac/beacon-gateway.sh [--install] [--ip] [--tunnel] [--codex] [--config-only]
#   --install      also build and install the app on the iPhone (needed once, and after the address changes)
#   --ip           put the Mac's current Wi-Fi IP in the app instead of its stable <name>.local address
#   --tunnel       Cloudflare quick tunnel (no account) for Wi-Fi that blocks devices from reaching each other
#   --codex        serve with the experimental synthetic-only Codex provider instead of Gemini/Groq
#   --config-only  write the app config and exit without starting the gateway
# Reads services/ai-orchestrator/.env (GOOGLE_AI_STUDIO_KEY, DRYRUN_DEV_TOKEN, PORT, DRYRUN_MAX_USD). The provider key
# stays on the Mac; the app gets only the gateway URL and the local fixture token, in a git-ignored bundle file.
# Personal Hotspot fallback: turn on the iPhone's hotspot, join it from the Mac, then run this script with --install
# (or keep the default .local address, which follows the Mac onto the new network).
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

INSTALL=0; USE_IP=0; TUNNEL=0; CODEX=0; CONFIG_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --ip) USE_IP=1 ;;
    --tunnel) TUNNEL=1 ;;
    --codex) CODEX=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

GATEWAY_DIR="$ROOT/services/ai-orchestrator"
ENV_FILE="$GATEWAY_DIR/.env"
CONFIG="$IOS_DIR/DryRun/Resources/BeaconGateway.json"
[ -f "$ENV_FILE" ] || { warn "missing ${ENV_FILE#"$ROOT"/}: copy the keys there first (see services/ai-orchestrator/README.md)"; exit 1; }

env_value() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1 | sed -e 's/^"//' -e 's/"$//'; }
TOKEN="$(env_value DRYRUN_DEV_TOKEN)"
PORT="$(env_value PORT)"; PORT="${PORT:-8788}"
[ "${#TOKEN}" -ge 24 ] || { warn "DRYRUN_DEV_TOKEN in .env must be at least 24 characters"; exit 1; }

wifi_ip() {
  local iface ip
  for iface in en0 en1 bridge100; do ip="$(ipconfig getifaddr "$iface" 2>/dev/null)" && [ -n "$ip" ] && { echo "$ip"; return; }; done
}

# Writes the app's config; returns 0 when it changed, so the caller knows the installed app needs a rebuild.
write_config() {
  local url="$1" old=""
  [ -f "$CONFIG" ] && old="$(cat "$CONFIG")"
  local new; new="$(printf '{"url":"%s","token":"%s"}\n' "$url" "$TOKEN")"
  [ "$new" = "$old" ] && return 1
  mkdir -p "$(dirname "$CONFIG")"
  printf '%s' "$new" >"$CONFIG"; chmod 600 "$CONFIG"
  return 0
}

TUNNEL_PID=""; GATEWAY_PID=""
cleanup() {
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null
  [ -n "$GATEWAY_PID" ] && kill "$GATEWAY_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT INT TERM

start_gateway() {
  have node || { warn "node not found"; exit 1; }
  [ -d "$GATEWAY_DIR/node_modules" ] || (cd "$GATEWAY_DIR" && pnpm install --frozen-lockfile) || exit 1
  local extra=()
  # Demo spend cap: .env wins; otherwise a higher cap than the 0.25 USD per 10 minutes the server defaults to.
  [ -n "$(env_value DRYRUN_MAX_USD)" ] || extra+=("DRYRUN_MAX_USD=2")
  if [ "$CODEX" = 1 ]; then
    extra+=("DRYRUN_PROVIDER=codex" "DRYRUN_CODEX_CAPABILITIES_FILE=$GATEWAY_DIR/profiles/codex-local-synthetic.json")
  fi
  local bind=0.0.0.0; [ "$TUNNEL" = 1 ] && bind=127.0.0.1
  log "Starting gateway on $bind:$PORT"
  # Loads .env the same way `node --env-file` does; values in the shell environment are not overridden.
  (cd "$GATEWAY_DIR" && env DRYRUN_LISTEN_HOST="$bind" DRYRUN_ACCESS_LOG=1 ${extra[@]+"${extra[@]}"} \
    node --env-file=.env --import tsx src/server.ts) &
  GATEWAY_PID=$!
  local i
  for i in $(seq 1 40); do
    curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && return 0
    kill -0 "$GATEWAY_PID" 2>/dev/null || { warn "gateway exited during startup (check .env)"; exit 1; }
    sleep 0.5
  done
  warn "gateway did not answer /health on port $PORT"; exit 1
}

# Mac-side proof the gateway is reachable on the network address the app uses, plus the phone's own network path.
check_reach() {
  local url="$1"
  if curl -fsS --max-time 5 "$url/health" >/dev/null 2>&1; then
    log "Gateway answers at $url"
  else
    warn "the gateway does not answer at $url from this Mac; try --ip, or --tunnel"
  fi
  local tmp; tmp="$(mktemp)"
  if xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
    /usr/bin/python3 - "$tmp" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
phones = [d for d in devices if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("hardwareProperties", {}).get("reality") == "physical"]
for d in phones:
    c = d.get("connectionProperties", {})
    name = d.get("deviceProperties", {}).get("name", "iPhone")
    if c.get("transportType") == "localNetwork" and c.get("tunnelState") == "connected":
        print(f"==> {name} is connected to this Mac over Wi-Fi: devices on this network can reach each other")
    elif c.get("transportType") == "wired":
        print(f"==> {name} is on the cable; unplug it and rerun to check the Wi-Fi path")
    else:
        print(f"!!  {name} is not reachable over this network. If the app shows the replay, this Wi-Fi may isolate "
              "devices: use --tunnel or the iPhone's Personal Hotspot")
PY
  fi
  rm -f "$tmp"
}

if [ "$TUNNEL" = 1 ]; then
  have cloudflared || { warn "cloudflared not found. Install with: brew install cloudflared"; exit 1; }
  [ "$CONFIG_ONLY" = 1 ] && { warn "--tunnel needs the gateway running; drop --config-only"; exit 2; }
  start_gateway
  TUNNEL_LOG="$(mktemp)"
  cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!
  URL=""
  for _ in $(seq 1 60); do
    URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -1)"
    [ -n "$URL" ] && break
    sleep 0.5
  done
  [ -n "$URL" ] || { warn "no tunnel URL from cloudflared; log: $TUNNEL_LOG"; exit 1; }
  # A quick tunnel's address is new each run, so the app must be rebuilt with it.
  write_config "$URL"; INSTALL=1
else
  if [ "$USE_IP" = 1 ]; then
    HOST="$(wifi_ip)"; [ -n "$HOST" ] || { warn "no Wi-Fi address; is the Mac on a network?"; exit 1; }
  else
    HOST="$(scutil --get LocalHostName 2>/dev/null).local"
  fi
  URL="http://$HOST:$PORT"
  if write_config "$URL"; then
    log "App config now points at $URL"
    [ "$CONFIG_ONLY" = 1 ] && log "Rebuild the app to use it: rerun with --install" || INSTALL=1
  else
    log "App config already points at $URL"
  fi
fi

if [ "$INSTALL" = 1 ]; then
  log "Installing the app with this config (no launch arguments, as from the home screen)"
  "$(dirname "$0")/device.sh" || exit 1
fi
[ "$CONFIG_ONLY" = 1 ] && exit 0

[ "$TUNNEL" = 1 ] || start_gateway
check_reach "$URL"
log "Beacon is serving. Open Dry Run on the phone; Settings > Try a sample family turns Beacon on. Ctrl-C stops."
log "With the gateway stopped, the app shows a recorded Beacon answer, labelled as a replay."
wait "$GATEWAY_PID"
