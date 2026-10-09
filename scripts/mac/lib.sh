#!/usr/bin/env bash
# Shared helpers for the macOS verification scripts. Compatible with macOS's stock bash 3.2.
# Sourced by doctor.sh, verify.sh, screens.sh, device.sh. Nothing here uploads anything.

# shellcheck disable=SC2034  # variables are used by the scripts that source this file
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT/apps/ios"
PROJECT="$IOS_DIR/DryRun.xcodeproj"
SCHEME="DryRun"
BUNDLE_ID="${BUNDLE_ID:-org.example.dryrun.app}"
DERIVED="$ROOT/.build-mac/DerivedData"
ART_ROOT="$ROOT/artifacts"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# new_run <prefix>  -> sets OUT (artifact dir for this run) and STEPS file
new_run() {
  RUN_ID="$(date +%Y%m%d-%H%M%S)"
  OUT="$ART_ROOT/$1-$RUN_ID"
  mkdir -p "$OUT/logs"
  STEPS="$OUT/steps.tsv"
  printf 'step\tstatus\tseconds\n' >"$STEPS"
  export OUT STEPS RUN_ID
}

# Replace the home directory (which contains the account name) in a text file.
redact_file() {
  [ -f "$1" ] || return 0
  sed -i '' -e "s#$HOME#~#g" -e "s#/Users/[^/ ]*/#/Users/<user>/#g" "$1" 2>/dev/null || true
}

# step <name> <command...>   runs a command, logs to logs/<name>.log, records PASS/FAIL, never aborts the run.
step() {
  local name="$1"; shift
  local logfile="$OUT/logs/$name.log"
  local start end status
  start=$(date +%s)
  log "$name"
  if "$@" >"$logfile" 2>&1; then status=PASS; else status=FAIL; fi
  end=$(date +%s)
  redact_file "$logfile"
  printf '%s\t%s\t%s\n' "$name" "$status" "$((end - start))" >>"$STEPS"
  echo "    $status ($((end - start))s) — log: ${logfile#"$ROOT"/}"
  [ "$status" = PASS ]
}

skip_step() {
  printf '%s\tSKIP\t0\t%s\n' "$1" "$2" >>"$STEPS"
  echo "    SKIP $1: $2"
}

# Picks an available iPhone simulator: $SIM_UDID, else name match on $SIM_NAME, else newest iOS runtime.
pick_simulator() {
  if [ -n "${SIM_UDID:-}" ]; then echo "$SIM_UDID"; return 0; fi
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, os, re, sys
data = json.load(sys.stdin)["devices"]
want = os.environ.get("SIM_NAME", "")
best = None
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if not d.get("isAvailable", True) or not d["name"].startswith("iPhone"):
            continue
        if want and d["name"] != want:
            continue
        # Prefer newest runtime, then non-"Pro Max"/"Plus" standard size for representative screenshots.
        size_rank = 0 if re.fullmatch(r"iPhone \d+( Pro)?", d["name"]) else 1
        key = (version, -size_rank)
        if best is None or key > best[0]:
            best = (key, d["udid"])
if best is None:
    sys.exit("no matching iPhone simulator; set SIM_NAME or SIM_UDID")
print(best[1])
'
}

boot_simulator() {
  local udid="$1"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  # Clean, consistent status bar for screenshots.
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
}

ensure_project() {
  if ! have xcodegen; then
    warn "xcodegen not found. Install with: brew install xcodegen"
    return 1
  fi
  (cd "$IOS_DIR" && xcodegen generate)
}

# Signing: simulator builds need none. Device builds need DEVELOPMENT_TEAM (and a unique BUNDLE_ID).
SIM_SIGNING="CODE_SIGNING_ALLOWED=NO"

# Export XCTest attachments (screenshots, a11y dumps) from an .xcresult into a folder with readable names.
export_attachments() {
  local result="$1" dest="$2"
  mkdir -p "$dest"
  if ! xcrun xcresulttool export attachments --path "$result" --output-path "$dest" >/dev/null 2>&1; then
    warn "xcresulttool export attachments failed (requires Xcode 16+); open $result in Xcode instead"
    return 1
  fi
  /usr/bin/python3 - "$dest" <<'PY'
import json, os, sys
dest = sys.argv[1]
manifest = os.path.join(dest, "manifest.json")
if not os.path.exists(manifest):
    sys.exit(0)
with open(manifest) as f:
    data = json.load(f)
renamed = 0
for test in data if isinstance(data, list) else [data]:
    for a in test.get("attachments", []):
        src = os.path.join(dest, a.get("exportedFileName", ""))
        name = a.get("suggestedHumanReadableName") or a.get("exportedFileName")
        if not os.path.exists(src) or not name:
            continue
        # XCTest appends "_<index>_<uuid>" to suggested names; keep the readable stem.
        stem, ext = os.path.splitext(name)
        ext = ext or os.path.splitext(src)[1]
        stem = stem.split("_0_")[0]
        target = os.path.join(dest, stem + ext)
        if os.path.exists(target) and os.path.abspath(target) != os.path.abspath(src):
            target = os.path.join(dest, stem + "-" + a.get("exportedFileName", "")[:8] + ext)
        os.rename(src, target)
        renamed += 1
print(f"exported {renamed} attachments")
PY
}

result_summary() {
  local result="$1" dest="$2"
  xcrun xcresulttool get test-results summary --path "$result" --compact >"$dest" 2>/dev/null \
    || xcrun xcresulttool get --legacy --path "$result" --format json >"$dest" 2>/dev/null || true
}

# make_bundle -> tar.gz next to the run folder
make_bundle() {
  local tarball="$OUT.tar.gz"
  (cd "$ART_ROOT" && tar -czf "$tarball" "$(basename "$OUT")")
  echo "$tarball"
}
