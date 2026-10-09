#!/usr/bin/env bash
# Fast UI iteration: build once, capture the screenshot tour, export PNGs (+ accessibility dumps).
# Usage: scripts/mac/screens.sh [--locales en] [--screens fire,plan] [--sim-name "iPhone 16"] [--device <udid>] [--open]
#   --device <udid>   run the tour on a connected iPhone (needs DEVELOPMENT_TEAM and a unique BUNDLE_ID)
#   --open            open the screenshot folder in Finder when done
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

LOCALES="en,es,vi"; SCREENS=""; DEVICE=""; OPEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --locales) LOCALES="$2"; shift ;;
    --screens) SCREENS="$2"; shift ;;
    --sim-name) export SIM_NAME="$2"; shift ;;
    --device) DEVICE="$2"; shift ;;
    --open) OPEN=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

new_run screens
step xcodegen ensure_project || { cat "$OUT/logs/xcodegen.log"; exit 1; }

if [ -n "$DEVICE" ]; then
  [ -n "${DEVELOPMENT_TEAM:-}" ] || { warn "set DEVELOPMENT_TEAM=<your team id> for device runs"; exit 2; }
  DEST="platform=iOS,id=$DEVICE"
  SIGN="DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID -allowProvisioningUpdates"
else
  SIM="$(pick_simulator)" || exit 1
  boot_simulator "$SIM"
  DEST="platform=iOS Simulator,id=$SIM"
  SIGN="$SIM_SIGNING"
fi

# shellcheck disable=SC2086  # SIGN is intentionally word-split into build settings
step build xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
  -derivedDataPath "$DERIVED" $SIGN || { grep -E ' error: ' "$OUT/logs/build.log" | sort -u | head -40; exit 1; }

# shellcheck disable=SC2086
TEST_RUNNER_TOUR_LOCALES="$LOCALES" TEST_RUNNER_TOUR_SCREENS="$SCREENS" step tour xcodebuild test-without-building \
  -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DERIVED" $SIGN \
  -only-testing:DryRunUITests/ScreenshotTourUITests -resultBundlePath "$OUT/tour.xcresult"
export_attachments "$OUT/tour.xcresult" "$OUT/screenshots"

TARBALL="$(make_bundle)"
echo "Screenshots: ${OUT#"$ROOT"/}/screenshots  ·  Bundle: ${TARBALL#"$ROOT"/}"
[ "$OPEN" = 1 ] && open "$OUT/screenshots"
exit 0
