# macOS verification guide

Run time depends on Xcode/package caches and the selected test matrix; record actual durations. You need a Mac with **Xcode 16.3 or later**
(the vault package resolves swift-crypto 4.5.2, whose manifest needs Swift 6.1); Xcode 26 is needed to also compile the
optional Foundation Models code. Everything uses fictional data.

## 1. One-time setup (5 min)

```sh
xcode-select -p                      # should point inside Xcode.app; if not: sudo xcode-select -s /Applications/Xcode.app
xcodebuild -runFirstLaunch           # accept components
brew install xcodegen                # https://brew.sh if Homebrew is missing
brew install pnpm                    # optional: backend tests
# This owner already has a Mac checkout: inspect git status/divergence and preserve local work.
# See docs/CLAUDE_NATIVE_HANDOFF.md before integrating origin/main.
```

In Xcode > Settings > Components (Platforms), make sure an **iOS simulator runtime** is installed.

## 2. Run the full verification (one command)

```sh
scripts/mac/verify.sh
```

It runs:
- the core and vault package tests natively; the vault uses real CryptoKit here
- the backend tests
- XcodeGen project generation and an app build
- native app integration tests and the current five UI journeys
- the current EN/ES/VI screenshot tour (inspect the actual resulting screens)
- EN/ES/VI plan PDFs for each fictional household

A failing step does not stop later checks. Inspect every PASS/FAIL/SKIP in SUMMARY.md; a bundle alone is not success.

**Output:** `artifacts/mac-<timestamp>.tar.gz` plus a printed summary.

Faster variants:
- `scripts/mac/verify.sh --quick`: tests, build, and journeys only.
- `--sim-name "iPhone 16"`: choose a simulator.
- `--locales en`: screenshots in one language only.

If the build fails, the first 40 unique compiler errors are in the summary and in `compile-errors.txt`. Send them
with the exact tested SHA. The Mac agent should fix the source defect, rerun the affected checks and record the fix; do not disable a failing gate.

## 3. Hardware-only capture gate (required for device verification, needs a LiDAR iPhone)

Follow `docs/DEVICE_CHECKLIST.md` and record actual results/errors. Use `scripts/mac/device.sh` to install on the phone after a successful native build. Do not claim a duration until measured; capture, interruption and export checks may take longer than one short scan.

## 4. What to send back

| Item | Required | Notes |
|---|---|---|
| `artifacts/mac-<timestamp>.tar.gz` | **yes** | Environment report, step results, logs, compile errors and warnings, screenshots, accessibility dumps, PDFs |
| Anything you changed to get it building | if any | `git diff` or a short description |
| Filled `DEVICE_CHECKLIST.md` form | if you ran it | Answers only; **no photos or scans of a real home** |
| Anything that looked wrong | optional | One line per issue with the screenshot name, e.g. `vi-plan-document: text cut off` |

What the bundle does *not* contain:
- device names, full device IDs, signing identity names, hostname, or account name (home paths become `~`)
- real household data

The `.xcresult` bundles stay in the `artifacts/mac-<timestamp>/` folder so you can open them in Xcode. They are left
out of the `.tar.gz`, because they record full paths, the Mac, and device names and IDs and cannot be redacted.

## Other authorized Mac workflows

- **External Mac over SSH, if the owner supplies access:**
  `scripts/remote-mac.sh you@mac.local verify` (or `screens --locales en --screens fire,plan`).
  It syncs to its dedicated remote checkout, runs the script and pulls `artifacts/` back. Inspect the script and remote destination first; do not overwrite the owner’s existing checkout. Turn on Remote Login on the Mac first:
  System Settings > General > Sharing.
- **Cloud Mac, if the repo is pushed to GitHub:** in the Actions tab, run **iOS verify** manually and download the
  bundle artifact. This uses a simulator only, needs no signing secrets and does not deploy. Record the workflow run URL, head SHA and every test result. A queued run is not verification.

## Previewing and testing the UI (for frontend work)

| Goal | Command |
|---|---|
| Screenshot tour, fast loop | `scripts/mac/screens.sh --locales en --screens fire,plan --open` |
| Same tour on a connected iPhone | `DEVELOPMENT_TEAM=<TeamID> BUNDLE_ID=com.<you>.dryrun scripts/mac/screens.sh --device <udid>` |
| Install and open on the phone in a given state | `DEVELOPMENT_TEAM=… BUNDLE_ID=… scripts/mac/device.sh -- -demoHousehold hh-oak -demoScenario home-fire -demoStep end` |
| List phones (prints the UDID that `--device` expects) | `scripts/mac/device.sh --list` |
| Live canvas | Open `apps/ios/DryRun.xcodeproj`, then `App/Previews.swift` (9 previews; change `locale:` to `es`/`vi`) |
| Environment only | `scripts/mac/doctor.sh` |

The demo launch arguments documented in `apps/ios/DryRun/App/DemoLaunch.swift` open any tab, scenario step, home view
mode, or generated plan directly, in any language. They always use the in-memory store and never touch real
household data.

**Phone requirements:**
- Developer Mode on (Settings > Privacy & Security).
- The phone trusted and paired in Xcode's Devices window.
- A free or paid Apple developer team in Xcode > Settings > Accounts.
- A bundle ID that's unique to your team.
