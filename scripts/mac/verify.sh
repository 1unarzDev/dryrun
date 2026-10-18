#!/usr/bin/env bash
# Full macOS verification for Dry Run. Every step is logged and recorded; a failing step never stops the run.
# Produces artifacts/mac-<timestamp>/ and artifacts/mac-<timestamp>.tar.gz (fictional data only).
#
# Usage: scripts/mac/verify.sh [--quick] [--no-ui] [--no-backend] [--locales en,es,vi] [--sim-name "iPhone 16"]
#   --quick       core/vault tests + app build + journeys only (no screenshot tour, no PDFs, no backend)
#   --no-ui       skip all simulator UI tests, screenshots, and PDFs
#   --no-backend  skip services/public-api
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

QUICK=0; NO_UI=0; NO_BACKEND=0; LOCALES="en,es,vi"
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; NO_BACKEND=1 ;;
    --no-ui) NO_UI=1 ;;
    --no-backend) NO_BACKEND=1 ;;
    --locales) LOCALES="$2"; shift ;;
    --sim-name) export SIM_NAME="$2"; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) warn "unknown option $1"; exit 2 ;;
  esac
  shift
done

require_xcode || exit 1
new_run mac
"$(dirname "$0")/doctor.sh" "$OUT/environment.md" >/dev/null
redact_file "$OUT/environment.md"

# 1. Swift packages, native macOS (vault uses CryptoKit here, not swift-crypto)
step core-tests swift test --package-path "$ROOT/packages/DryRunCore" --scratch-path "$ROOT/.build-mac/core"
step vault-tests swift test --package-path "$ROOT/packages/DryRunVault" --scratch-path "$ROOT/.build-mac/vault"

# 2. Backend (optional)
if [ "$NO_BACKEND" = 1 ]; then skip_step backend "disabled"
elif ! have pnpm; then skip_step backend "pnpm not installed"
else step backend bash -c "cd '$ROOT/services/public-api' && pnpm install --frozen-lockfile && pnpm test && pnpm typecheck"
fi

# 3. Generate the Xcode project and build the app + UI tests for a simulator
if ! step xcodegen ensure_project; then
  skip_step app-build "project generation failed"; NO_UI=1
else
  SIM="$(pick_simulator 2>"$OUT/logs/simulator.log")" || SIM=""
  if [ -n "$SIM" ]; then
    echo "simulator: $(xcrun simctl list devices | grep "$SIM" | sed -E 's/\(([0-9A-F]{8})-[^)]*\)/(\1...)/' | xargs)" >>"$OUT/environment.md"
    boot_simulator "$SIM"
    BUILD_DEST="platform=iOS Simulator,id=$SIM"
  else
    # Still compile, so the run reports build errors even on a Mac with no simulator runtime installed.
    warn "no iPhone simulator found (see logs/simulator.log); compiling only, UI steps will be skipped"
    BUILD_DEST="generic/platform=iOS Simulator"
  fi
  if ! step app-build xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
      -destination "$BUILD_DEST" -derivedDataPath "$DERIVED" "$SIM_SIGNING"; then
    NO_UI=1
  fi
  [ -n "$SIM" ] || NO_UI=1
  # Build diagnostics in one place, deduplicated: compiler, linker, and package-resolution errors.
  build_diagnostics "$OUT/logs/app-build.log" "$OUT/compile-errors.txt"
  grep -E ' warning: ' "$OUT/logs/app-build.log" | sort -u >"$OUT/compile-warnings.txt" || true
fi

# 4. UI journeys, screenshot tour, plan PDFs
if [ "$NO_UI" = 1 ]; then
  skip_step app-integration-tests "build failed, no simulator, or disabled"; skip_step ui-journeys "build failed, no simulator, or disabled"; skip_step screenshot-tour "build failed, no simulator, or disabled"
  skip_step plan-pdfs "build failed, no simulator, or disabled"
else
  step app-integration-tests xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" \
    -only-testing:DryRunTests -resultBundlePath "$OUT/app-tests.xcresult"
  result_summary "$OUT/app-tests.xcresult" "$OUT/app-tests-summary.json"
  step ui-journeys xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" \
    -only-testing:DryRunUITests/DemoJourneyUITests -resultBundlePath "$OUT/journeys.xcresult"
  result_summary "$OUT/journeys.xcresult" "$OUT/journeys-summary.json"

  if [ "$QUICK" = 1 ]; then
    skip_step screenshot-tour "--quick"; skip_step plan-pdfs "--quick"
  else
    TEST_RUNNER_TOUR_LOCALES="$LOCALES" step screenshot-tour xcodebuild test-without-building -project "$PROJECT" \
      -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" \
      -only-testing:DryRunUITests/ScreenshotTourUITests -resultBundlePath "$OUT/tour.xcresult"
    export_attachments "$OUT/tour.xcresult" "$OUT/screenshots" >>"$OUT/logs/screenshot-tour.log" 2>&1 || true
    redact_file "$OUT/logs/screenshot-tour.log"
    step plan-pdfs "$(dirname "$0")/plan-pdfs.sh" "$SIM" "$OUT/pdfs"
  fi
fi

# 5. Summary
{
  echo "# Dry Run macOS verification — $RUN_ID"
  echo
  echo "| Step | Status | Seconds |"
  echo "|---|---|---|"
  tail -n +2 "$STEPS" | awk -F'\t' '{printf "| %s | %s | %s |\n", $1, $2, $3}'
  echo
  if [ -s "$OUT/compile-errors.txt" ]; then
    echo "## Build errors ($(wc -l <"$OUT/compile-errors.txt" | xargs) unique lines, first 40)"
    echo '```'; head -40 "$OUT/compile-errors.txt"; echo '```'
  elif steps_failed app-build; then
    # The build failed without a line the filter recognises: show the end of the log rather than nothing.
    echo "## Build failed (last 40 log lines)"
    echo '```'; tail -40 "$OUT/logs/app-build.log"; echo '```'
  fi
  [ -f "$OUT/compile-warnings.txt" ] && echo "Compile warnings: $(wc -l <"$OUT/compile-warnings.txt" | xargs) unique (see compile-warnings.txt)"
  [ -d "$OUT/screenshots" ] && echo "Screenshots: $(find "$OUT/screenshots" -name '*.png' | wc -l | xargs)"
  if ls "$OUT"/pdfs/DONE-*.txt >/dev/null 2>&1; then
    echo; echo "## Plan PDFs"
    # One block per household; the app writes these files without a trailing newline.
    for f in "$OUT"/pdfs/DONE-*.txt; do
      n="${f##*/DONE-}"; echo "### ${n%.txt}"; cat "$f"; echo
    done
  fi
  echo
  echo "Environment: see environment.md. Logs: logs/. Result bundles: *.xcresult (open in Xcode)."
} >"$OUT/SUMMARY.md"
for f in "$OUT"/*.txt "$OUT"/*.json "$OUT"/*.md "$OUT"/logs/*.log; do redact_file "$f"; done

TARBALL="$(make_bundle)"
cat "$OUT/SUMMARY.md"
echo
echo "Bundle: ${TARBALL#"$ROOT"/}  ← send this file"
# A failing step never stops the run, but automation (the GitHub workflow) should not report success for it.
if [ -n "${CI:-}" ] && steps_failed; then exit 1; fi
exit 0
