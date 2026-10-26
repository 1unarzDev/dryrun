#!/usr/bin/env bash
# Build, install, and launch Dry Run on a connected iPhone (USB or same-network pairing).
# Usage: [DEVELOPMENT_TEAM=ABCDE12345] [BUNDLE_ID=com.yourname.dryrun] scripts/mac/device.sh [--list] [--device <udid>] [-- <launch args>]
#   --list          list connected devices with the UDID that --device expects (shown locally only; nothing is saved)
#   -- <args>       launch arguments, e.g.  -- -demoHousehold hh-oak -demoScenario home-fire -demoStep end
# Requires: Developer Mode on the phone, the phone trusted/paired in Xcode, a signing team in Xcode > Settings > Accounts.
# DEVELOPMENT_TEAM defaults to the team of your Apple Development certificate; BUNDLE_ID to one unique to that team.
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

# Prints "<udid>  <model>  <name>" per connected iPhone/iPad. xcodebuild's -destination id= wants this hardware UDID,
# not the CoreDevice identifier that plain `devicectl list devices` shows.
list_devices() {
  local tmp; tmp="$(mktemp)"
  if ! xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; warn "devicectl is unavailable (needs Xcode 15 or later)"; return 1
  fi
  /usr/bin/python3 - "$tmp" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
rows = [d for d in devices if d.get("hardwareProperties", {}).get("platform") in ("iOS", "iPadOS")]
# devicectl also lists phones paired earlier but not reachable now; list reachable ones first so the default pick works.
rows.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") == "unavailable")
if not rows:
    print("no connected iPhone found")
for d in rows:
    hw, props, conn = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    state = "not reachable" if conn.get("tunnelState") == "unavailable" else conn.get("transportType", "connected")
    print(f"{hw.get('udid', '?')}  {hw.get('marketingName', hw.get('productType', '?'))}  iOS {props.get('osVersionNumber', '?')}"
          f"  [{state}; developer mode {props.get('developerModeStatus', '?')}]  {props.get('name', '')}")
PY
  rm -f "$tmp"
}

DEVICE=""; LAUNCH_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) require_xcode || exit 1; list_devices; exit 0 ;;
    --device) DEVICE="$2"; shift ;;
    --) shift; LAUNCH_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

require_xcode || exit 1
resolve_signing || exit 2

if [ -z "$DEVICE" ]; then
  DEVICE="$(list_devices 2>/dev/null | awk '$1 != "no" && !/not reachable/ {print $1; exit}')"
  [ -n "$DEVICE" ] || { warn "no reachable iPhone: connect it by USB, unlock it, and tap Trust (try --list)"; exit 1; }
fi

ensure_project || exit 1
log "Building for device …${DEVICE: -4}"
# Log to a file and test xcodebuild's own status: piping into tail would report tail's status and hide a failed build.
mkdir -p "$ROOT/.build-mac"
BUILD_LOG="$ROOT/.build-mac/device-build.log"
if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS,id=$DEVICE" \
    -derivedDataPath "$DERIVED" "${DEVICE_SIGNING[@]}" >"$BUILD_LOG" 2>&1; then
  build_diagnostics "$BUILD_LOG" "$BUILD_LOG.errors"
  if [ -s "$BUILD_LOG.errors" ]; then head -40 "$BUILD_LOG.errors"; else tail -40 "$BUILD_LOG"; fi
  signing_hints "$BUILD_LOG"
  warn "build failed; full log: ${BUILD_LOG#"$ROOT"/}"
  exit 1
fi
tail -3 "$BUILD_LOG"
APP="$DERIVED/Build/Products/Debug-iphoneos/DryRun.app"
[ -d "$APP" ] || { warn "built app not found at ${APP#"$ROOT"/}"; exit 1; }
log "Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" || exit 1
log "Launching ${LAUNCH_ARGS[*]:-}"
if ! xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" \
    "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}"; then
  # The usual first-run failure with a free or new team: iOS will not launch an app from a developer it does not trust.
  warn "launch failed. If the phone is locked, unlock it. On a first install, trust the developer on the iPhone:"
  warn "Settings > General > VPN & Device Management > (your Apple Account) > Trust, then run this script again."
  exit 1
fi
