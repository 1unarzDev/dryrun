#!/usr/bin/env bash
# Run app unit/UI tests on a connected iPhone and export every screenshot attachment for inspection.
# Usage: [DEVELOPMENT_TEAM=…] [BUNDLE_ID=…] scripts/mac/device-test.sh [--device <udid>] [--out <dir>] [<-only-testing target>…]
#   e.g. scripts/mac/device-test.sh DryRunUITests/SixHazardUITests DryRunTests
# The phone must be unlocked when tests start; keep Auto-Lock off (or the screen awake) during UI journeys.
# Results: <out>/result.xcresult, <out>/summary.json and <out>/attachments/*.png (fictional demo data only).
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

DEVICE=""; OUT=""; ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) ONLY+=("-only-testing:$1") ;;
  esac
  shift
done

require_xcode || exit 1
resolve_signing || exit 2
if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected/ { for (i = 1; i <= NF; i++) if ($i == "(UDID)") { print $(i-1); exit } }')"
  [ -n "$DEVICE" ] || { warn "no connected iPhone found"; exit 1; }
fi
ensure_project || exit 1
OUT="${OUT:-$ROOT/.build-mac/device-tests/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
RESULT="$OUT/result.xcresult"
rm -rf "$RESULT" "$OUT/attachments"  # xcodebuild refuses an existing bundle; a rerun replaces the previous results
log "Testing on device …${DEVICE: -4} ${ONLY[*]:-(all tests)}"
# Extra test-runner environment (e.g. TEST_RUNNER_AIGATEWAY) passes through xcodebuild's TEST_RUNNER_ prefix.
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" "${DEVICE_SIGNING[@]}" "${ONLY[@]+"${ONLY[@]}"}" >"$OUT/xcodebuild.log" 2>&1
STATUS=$?
grep -E "Test Case .* (passed|failed)|error:|\*\* TEST" "$OUT/xcodebuild.log" | tail -60
result_summary "$RESULT" "$OUT/summary.json"
export_attachments "$RESULT" "$OUT/attachments"
log "xcodebuild exit $STATUS; results in ${OUT#"$ROOT"/}"
exit $STATUS
