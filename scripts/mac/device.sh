#!/usr/bin/env bash
# Build, install, and launch Dry Run on a connected iPhone (USB or same-network pairing).
# Usage: DEVELOPMENT_TEAM=ABCDE12345 BUNDLE_ID=com.yourname.dryrun scripts/mac/device.sh [--list] [--device <udid>] [-- <launch args>]
#   --list          list connected devices (names shown locally only; nothing is saved)
#   -- <args>       launch arguments, e.g.  -- -demoHousehold hh-oak -demoScenario home-fire -demoStep end
# Requires: Developer Mode on the phone, the phone trusted/paired in Xcode, a signing team in Xcode > Settings > Accounts.
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

DEVICE=""; LAUNCH_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) xcrun devicectl list devices; exit 0 ;;
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
  TMP="$(mktemp)"
  xcrun devicectl list devices --json-output "$TMP" >/dev/null 2>&1
  DEVICE="$(/usr/bin/python3 -c '
import json, sys
ds = json.load(open(sys.argv[1]))["result"]["devices"]
ds = [d for d in ds if d.get("hardwareProperties", {}).get("platform") == "iOS"]
print(ds[0]["hardwareProperties"]["udid"] if ds else "")' "$TMP")"
  rm -f "$TMP"
  [ -n "$DEVICE" ] || { warn "no connected iPhone found (try --list)"; exit 1; }
fi

ensure_project || exit 1
log "Building for device …${DEVICE: -4}"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" | tail -5 || exit 1
APP="$DERIVED/Build/Products/Debug-iphoneos/DryRun.app"
log "Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" || exit 1
log "Launching ${LAUNCH_ARGS[*]:-}"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}"
