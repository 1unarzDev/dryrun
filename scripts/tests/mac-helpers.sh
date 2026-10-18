#!/usr/bin/env bash
# Portable regressions for the native verification harness. Does not invoke Xcode or Apple services.
set -euo pipefail
. "$(dirname "$0")/../mac/lib.sh"
unset SIM_UDID SIM_NAME SIM_RUNTIME

# A host may retain newer simulator runtimes after selecting an older Xcode. Choose a runtime
# compatible with that selected SDK instead of letting the newest installed phone win.
xcrun() {
  if [ "$1" = --sdk ]; then
    printf '18.5\n'
  else
    cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"iPhone 17 Pro","udid":"newer","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[{"name":"iPhone 16 Pro Max","udid":"large","isAvailable":true},{"name":"iPhone 16","udid":"supported","isAvailable":true},{"name":"iPhone SE (3rd generation)","udid":"small","isAvailable":true}]}}
JSON
  fi
}
[ "$(pick_simulator)" = supported ]
[ "$(SIM_NAME='iPhone SE (3rd generation)' pick_simulator)" = small ]
[ "$(SIM_RUNTIME=26.2 pick_simulator)" = newer ]
[ "$(SIM_UDID=explicit pick_simulator)" = explicit ]
if SIM_RUNTIME=invalid pick_simulator >/dev/null 2>&1; then exit 1; fi
if SIM_RUNTIME=18.6 pick_simulator >/dev/null 2>&1; then exit 1; fi

# Status is a TSV column, not a regex substring or a literal backslash-t sequence.
STEPS="$(mktemp)"
trap 'rm -f "$STEPS"' EXIT
printf 'step\tstatus\tseconds\ncore-tests\tPASS\t1\nplan-pdfs\tSKIP\t0\n' >"$STEPS"
if steps_failed; then exit 1; fi
printf 'app-build\tFAIL\t2\n' >>"$STEPS"
steps_failed
steps_failed app-build
if steps_failed core-tests || steps_failed missing; then exit 1; fi
printf 'Native verification helper regressions passed\n'
