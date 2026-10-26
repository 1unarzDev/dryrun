#!/usr/bin/env bash
# Fast UI iteration: build once, capture the screenshot tour, export PNGs (+ accessibility dumps).
# Usage: scripts/mac/screens.sh [--locales en] [--screens fire,plan] [--sim-name "iPhone 16"] [--device <udid>] [--xxl] [--open]
#   --device <udid>   run the tour on a connected iPhone (signing as in device.sh; see scripts/mac/device.sh --list)
#   --xxl             largest accessibility text size (Dynamic Type AX XXL), to check for clipping
#   --open            open the screenshot folder in Finder when done
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

LOCALES="en,es,vi"; SCREENS=""; DEVICE=""; OPEN=0; XXL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --locales) LOCALES="$2"; shift ;;
    --screens) SCREENS="$2"; shift ;;
    --sim-name) export SIM_NAME="$2"; shift ;;
    --device) DEVICE="$2"; shift ;;
    --open) OPEN=1 ;;
    --xxl) XXL=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

require_xcode || exit 1
new_run screens
step xcodegen ensure_project || { cat "$OUT/logs/xcodegen.log"; exit 1; }

if [ -n "$DEVICE" ]; then
  resolve_signing || exit 2
  DEST="platform=iOS,id=$DEVICE"
  # DRYRUN_BUNDLE_ID, not PRODUCT_BUNDLE_IDENTIFIER: the latter would also rename the UI-test bundle (see project.yml).
  SIGN=("${DEVICE_SIGNING[@]}")
else
  SIM="$(pick_simulator)" || exit 1
  boot_simulator "$SIM"
  DEST="platform=iOS Simulator,id=$SIM"
  SIGN=("$SIM_SIGNING")
fi

step build xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
  -derivedDataPath "$DERIVED" "${SIGN[@]}" || {
    build_diagnostics "$OUT/logs/build.log" "$OUT/compile-errors.txt"
    if [ -s "$OUT/compile-errors.txt" ]; then head -40 "$OUT/compile-errors.txt"; else tail -40 "$OUT/logs/build.log"; fi
    [ -n "$DEVICE" ] && signing_hints "$OUT/logs/build.log"
    exit 1
  }

# An empty TOUR_SCREENS must not reach the test runner as "no screens": export the filter only when one was given.
export TEST_RUNNER_TOUR_LOCALES="$LOCALES"
if [ "$XXL" = 1 ]; then export TEST_RUNNER_TOUR_XXL=1; else unset TEST_RUNNER_TOUR_XXL; fi
if [ -n "$SCREENS" ]; then export TEST_RUNNER_TOUR_SCREENS="$SCREENS"; else unset TEST_RUNNER_TOUR_SCREENS; fi
step tour xcodebuild test-without-building \
  -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DERIVED" "${SIGN[@]}" \
  -only-testing:DryRunUITests/ScreenshotTourUITests -resultBundlePath "$OUT/tour.xcresult"
export_attachments "$OUT/tour.xcresult" "$OUT/screenshots"

TARBALL="$(make_bundle)"
echo "Screenshots: ${OUT#"$ROOT"/}/screenshots  ·  Bundle: ${TARBALL#"$ROOT"/}"
[ "$OPEN" = 1 ] && open "$OUT/screenshots"
exit 0
