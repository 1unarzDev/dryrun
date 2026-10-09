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
xcrun simctl install "$SIM" "$APP"
status=0
for hh in hh-oak hh-lake hh-pine; do
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$SIM" "$BUNDLE_ID" -uiTestingInMemory -demoHousehold "$hh" -demoWritePlanPDFs >/dev/null
  DATA="$(xcrun simctl get_app_container "$SIM" "$BUNDLE_ID" data)"
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
xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
exit $status
