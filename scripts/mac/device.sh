#!/usr/bin/env bash
# Build, install, and launch Dry Run on a connected iPhone (USB or same-network pairing).
# Usage: DEVELOPMENT_TEAM=ABCDE12345 BUNDLE_ID=com.yourname.dryrun scripts/mac/device.sh [--list] [--device <udid>] [-- <launch args>]
#   --list          list connected devices with the UDID that --device expects (shown locally only; nothing is saved)
#   -- <args>       launch arguments, e.g.  -- -demoHousehold hh-oak -demoScenario home-fire -demoStep end
# Requires: Developer Mode on the phone, the phone trusted/paired in Xcode, a signing team in Xcode > Settings > Accounts.
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
if not rows:
    print("no connected iPhone found")
for d in rows:
    hw = d.get("hardwareProperties", {})
    print(f"{hw.get('udid', '?')}  {hw.get('marketingName', hw.get('productType', '?'))}  {d.get('deviceProperties', {}).get('name', '')}")
PY
  rm -f "$tmp"
}

DEVICE=""; LAUNCH_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_devices; exit 0 ;;
    --device) DEVICE="$2"; shift ;;
    --) shift; LAUNCH_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

[ -n "${DEVELOPMENT_TEAM:-}" ] || { warn "set DEVELOPMENT_TEAM (Xcode > Settings > Accounts > Team ID)"; exit 2; }
[ "$BUNDLE_ID" != "org.example.dryrun.app" ] || warn "using the placeholder bundle ID; set BUNDLE_ID=com.<you>.dryrun if signing fails"

if [ -z "$DEVICE" ]; then
  DEVICE="$(list_devices 2>/dev/null | awk 'NR==1 && $1 != "no" {print $1}')"
  [ -n "$DEVICE" ] || { warn "no connected iPhone found (try --list)"; exit 1; }
fi

ensure_project || exit 1
log "Building for device …${DEVICE: -4}"
# Log to a file and test xcodebuild's own status: piping into tail would report tail's status and hide a failed build.
mkdir -p "$ROOT/.build-mac"
BUILD_LOG="$ROOT/.build-mac/device-build.log"
if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS,id=$DEVICE" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" DRYRUN_BUNDLE_ID="$BUNDLE_ID" >"$BUILD_LOG" 2>&1; then
  build_diagnostics "$BUILD_LOG" "$BUILD_LOG.errors"
  if [ -s "$BUILD_LOG.errors" ]; then head -40 "$BUILD_LOG.errors"; else tail -40 "$BUILD_LOG"; fi
  warn "build failed; full log: ${BUILD_LOG#"$ROOT"/}"
  exit 1
fi
tail -3 "$BUILD_LOG"
APP="$DERIVED/Build/Products/Debug-iphoneos/DryRun.app"
[ -d "$APP" ] || { warn "built app not found at ${APP#"$ROOT"/}"; exit 1; }
log "Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" || exit 1
log "Launching ${LAUNCH_ARGS[*]:-}"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}"
