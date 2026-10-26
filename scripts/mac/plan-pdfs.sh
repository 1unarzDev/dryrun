#!/usr/bin/env bash
# Generates EN/ES/VI plan PDFs + PlanDocument JSON for each fictional household on a booted simulator
# (DEBUG build's -demoWritePlanPDFs mode) and copies them to <dest>.
# Usage: scripts/mac/plan-pdfs.sh <simulator-udid> <dest-dir>
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
SIM="$1"; DEST="$2"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/DryRun.app"
[ -d "$APP" ] || { echo "app not built at $APP"; exit 1; }
mkdir -p "$DEST"
# The ID the app was actually built with, not $BUNDLE_ID from the environment (which may be set for device work).
APP_ID="$(app_bundle_id "$APP")"
[ -n "$APP_ID" ] || { echo "could not read the bundle ID from $APP/Info.plist"; exit 1; }
xcrun simctl install "$SIM" "$APP"
status=0
for hh in hh-oak hh-lake hh-pine; do
  xcrun simctl terminate "$SIM" "$APP_ID" >/dev/null 2>&1 || true
  # The simulator keeps the app's data between runs: remove the previous run's files and DONE markers first, or the
  # wait below would end at once and copy stale PDFs.
  DATA="$(xcrun simctl get_app_container "$SIM" "$APP_ID" data 2>/dev/null)"
  [ -n "$DATA" ] && rm -rf "$DATA/Documents/demo-plans"
  xcrun simctl launch "$SIM" "$APP_ID" -uiTestingInMemory -demoHousehold "$hh" -demoWritePlanPDFs >/dev/null
  DATA="$(xcrun simctl get_app_container "$SIM" "$APP_ID" data)"
  for _ in $(seq 1 90); do
    [ -f "$DATA/Documents/demo-plans/DONE-$hh.txt" ] && break
    sleep 1
  done
  if [ -f "$DATA/Documents/demo-plans/DONE-$hh.txt" ]; then
    cp "$DATA/Documents/demo-plans/plan-$hh-"* "$DATA/Documents/demo-plans/DONE-$hh.txt" "$DEST/"
    echo "$hh: $(tr '\n' ' ' <"$DATA/Documents/demo-plans/DONE-$hh.txt")"
  else
    echo "$hh: timed out waiting for PDFs"; status=1
  fi
done
xcrun simctl terminate "$SIM" "$APP_ID" >/dev/null 2>&1 || true
exit $status
