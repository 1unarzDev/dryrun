#!/usr/bin/env bash
# Environment report for Dry Run verification. Prints Markdown to stdout (or to $1).
# Privacy: no device names, no full device identifiers, no signing identity names, no hostname or user name.
set -u
# shellcheck source=scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"

report() {
  echo "# Dry Run macOS environment"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Machine"
  echo "- macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "- Hardware: $(sysctl -n hw.model 2>/dev/null) · $(uname -m) · $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB RAM"
  echo "- Free disk (repo volume): $(df -h "$ROOT" | awk 'NR==2 {print $4}')"
  echo
  echo "## Toolchain"
  echo "- xcode-select: $(xcode-select -p 2>/dev/null | sed "s#$HOME#~#")"
  echo "- Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  echo "- iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo missing) · Simulator SDK: $(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo missing)"
  echo "- Swift: $(swift --version 2>/dev/null | head -1)"
  echo "- XcodeGen: $(xcodegen --version 2>/dev/null || echo 'missing — brew install xcodegen')"
  echo "- Node: $(node --version 2>/dev/null || echo missing) · pnpm: $(pnpm --version 2>/dev/null || echo missing)"
  echo "- Valid code-signing identities: $(security find-identity -v -p codesigning 2>/dev/null | tail -1 | awk '{print $1}') (names not recorded)"
  echo "- FoundationModels framework in SDK: $([ -d "$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)/System/Library/Frameworks/FoundationModels.framework" ] && echo yes || echo no)"
  echo
  echo "## iOS simulator runtimes"
  xcrun simctl list runtimes 2>/dev/null | grep -E '^iOS' | sed 's/^/- /'
  echo
  echo "## Available iPhone simulators (first 12)"
  xcrun simctl list devices available 2>/dev/null | grep -E '^\s+iPhone' | head -12 \
    | sed -E 's/\(([0-9A-F]{8})-[0-9A-F-]+\)/(\1…)/' | sed 's/^ */- /'
  echo
  echo "## Connected physical devices (names redacted)"
  local tmp; tmp="$(mktemp)"
  if xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
    /usr/bin/python3 - "$tmp" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
if not devices:
    print("- none")
for d in devices:
    hw = d.get("hardwareProperties", {})
    props = d.get("deviceProperties", {})
    ident = d.get("identifier", "")
    print(f"- {hw.get('marketingName', hw.get('productType', '?'))} · {hw.get('platform', '?')} {props.get('osVersionNumber', '?')}"
          f" · id …{ident[-4:]} · paired={d.get('connectionProperties', {}).get('pairingState', '?')}"
          f" · developerMode={props.get('developerModeStatus', '?')}")
PY
  else
    echo "- devicectl unavailable (requires Xcode 15+)"
  fi
  rm -f "$tmp"
  echo
  echo "## Repository"
  echo "- Commit: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout') $(git -C "$ROOT" status --porcelain 2>/dev/null | grep -q . && echo '(uncommitted changes)')"
}

if [ $# -ge 1 ]; then report >"$1"; echo "wrote ${1#"$ROOT"/}"; else report; fi
