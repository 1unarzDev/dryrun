# Verification record

**Platform actually used:** Arch Linux x86_64, kernel 7.2.8; Docker image `swift:6.2` (Swift 6.2.x, Swift Testing
6.2.4); Node 26.10.0; pnpm. **No macOS, no Xcode, no iOS SDK, no simulator, no device.**
Date: 2026-10-09.

## UI redesign and impact features (2026-10-14)

**Platform:** macOS 27.0.1, Xcode 27.0, iOS 27.0 simulator (iPhone 18 Pro). No physical device.
`scripts/mac/verify.sh` passes every step (bundle `artifacts/mac-20261014-111357.tar.gz`):

| Step | Result |
|---|---|
| core-tests | 143 tests in 22 suites passed (9 new: outage card, next steps) |
| vault-tests | 31 passed |
| backend | 68 passed; translation baseline re-recorded for the new keys |
| app-build | builds; no warnings in app code |
| ui-journeys | 8/8 passed (5 new: one-tap demo, guided setup with every answer "Not sure", Next steps mark done, outage card fill-in and share, share with family) |
| screenshot-tour | 18 screens × EN/ES/VI = 54 captured and inspected |
| plan-pdfs | 9 rendered, validator issues: none |

**Accessibility pass.** Main screens were captured at Dynamic Type AX XXL (`scripts/mac/screens.sh --xxl`). This
found and fixed two problems:
- Next steps overflowed the screen edge.
- The rehearsal action bar broke words letter by letter.

Rows now stack at accessibility sizes, and the bottom bars cap at AX1.

An Accessibility Inspector audit was **not** run.

**What changed:** see `docs/UI_AUDIT.md` (every control and the test that covers it) and `docs/goals/ui-impact-goal.md`.

**Open:**
- Home, Settings, the manual home editor, and RoomPlan text are still English-only.
- ES/VI strings are unreviewed drafts.
- Device-only checks are unchanged (below).

## macOS run (2026-10-09)

**Platform:** macOS 27.0.1, Xcode 27.0 (27A266a), iOS 27.0 simulator (iPhone 18 Pro). No physical device.
`scripts/mac/verify.sh`, all steps PASS (bundle `artifacts/mac-20261009-200717.tar.gz`):

| Step | Result |
|---|---|
| core-tests (native, `swift test`) | 134 tests in 20 suites passed |
| vault-tests (native; CryptoKit) | 31 tests in 5 suites passed |
| backend (`pnpm test && pnpm typecheck`) | 68 tests passed; typecheck clean |
| app-build (`build-for-testing`, simulator) | builds; no warnings in app code |
| ui-journeys (`DemoJourneyUITests`) | 3/3 passed |
| screenshot-tour | 14 screens × EN/ES/VI captured and inspected |
| plan-pdfs | 3 households × EN/ES/VI rendered, validator issues: none |

Fixed during this run:
- **Compile:** Xcode 27's `@State` macro rejects a `switch` expression as an initial value (`HomeTabView.mode`).
- **PDF:** long wrapped lines lost their opening lines (the 2-1-1 help line), because `Block.draw` used an
  unbounded rect height. It now draws into the measured height.
- **Plan dates:** "Plan generated" used the UTC day, so evening plans showed tomorrow's date.
  `PlanBuilder.Options.timeZone` (default UTC) is now set to the device time zone by the app; there is a test for it.
- **Raw IDs on screen:**
  - Services showed "Device: eq-oxygen".
  - Recommendation details showed fact and event IDs.
  - Unknowns showed "backup › bk-station › setupConfirmed".
  - Onboarding and setup pickers showed enum case names ("singleFamily").
  - Home issues all read "Confirm this window." and now name the room.
- **2D plan:** fitting to outdoor markers shrank the house into a corner, and room labels overlapped each other and
  the safety markers.
- **UI test:** "Try this change" is below the fold of a lazy `List`; the test now scrolls to it.
- **Tooling:**
  - `verify.sh` and `doctor.sh` did not select Xcode when `xcode-select` pointed at the Command Line Tools.
  - `doctor.sh` reported FoundationModels present when no iOS SDK was installed.
  - The PDF summary lines ran together.

Open, not fixed:
- Rehearsal status rows (`ServiceNames`) and the new readable fact names are English-only in ES/VI. Translating
  them needs new locale keys and a language review.
- The core resource unit gives "1 charges".
- Device-only checks are still pending (below).

## Commands and results (Linux run)

| Command | Result |
|---|---|
| `scripts/swift.sh packages/DryRunCore test` | **133 tests in 20 suites passed**, 0 known issues |
| `scripts/swift.sh packages/DryRunVault test` | **31 tests in 5 suites passed** (Linux: swift-crypto backend) |
| `cd services/public-api && pnpm test` | **68 tests in 4 files passed** (includes 10 regional-agent security probes) |
| `cd services/public-api && pnpm typecheck` | clean (`tsc --noEmit`) |
| `swiftc -parse` on every file in `apps/ios` | parses (syntax only; **not a compile**) |
| `python3 -c "import yaml; yaml.safe_load(open('apps/ios/project.yml'))"` | valid YAML (not run through XcodeGen) |
| `DRYRUN_DUMP=1 … --filter PlanDemoDump` | readable rehearsal, comparison, and Vietnamese plan output reviewed by the lead |

Failures encountered and fixed during the build, all caught by tests or reviews:

- **Spatial:** a door in a near-touching gap was treated as an adjacency, and scanned widths were treated as confirmed.
- **Planner:** scan-observed operability and step-free values satisfied hard requirements.
- **Planner:** doors in thick scanned walls dropped out of routing.
- **Plan builder:**
  - Wheelchair routes were merged with walking routes.
  - Prohibition styling was lost in ES/VI.
  - An English "outside" leaked into translated routes.
  - Assumed water was printed as fact.
  - Placeholder filling was multi-pass.
- **Cursor:** the alarm event was hidden behind a minute-0 decision.
- **Confirmation:** windows could become exits through the generic answer; upper-floor shelter spots were accepted; there were two definitions of "ground floor".
- **Privacy:** NWS "Cancel" messages were shown as active alerts; stale alerts were dropped, producing a false all-clear; the app-switcher cover missed sheets; unreadable vault files mapped to "locked".
- **Regional agent:** a compromised-model test got an `http://` metadata URL and an "is OPEN" claim accepted.

See `docs/lanes/review-*.md` for each.

## Feature status

Legend: IMPLEMENTED (code exists) · TESTED_CORE (Linux tests exercise it) · TESTED_SIMULATOR / TESTED_DEVICE (none
yet) · PARTIAL · BLOCKED.

| Feature | Status | Evidence / limits |
|---|---|---|
| Shared contracts and Codable models with evidence and uncertainty | TESTED_CORE | fixture round-trip, lenient decoding |
| Deterministic discrete-event engine, AND/OR dependency model, bounded fixed point | TESTED_CORE | SimulationTests (determinism incl. equal-time events, nonconvergence error) |
| Backup allocation without double-counting; no negative quantities | TESTED_CORE | SimulationTests |
| Six distinct scenario packs, each ≥2 decisions, failure and recovery branches | TESTED_CORE | PlanIntegrationTests.distinctScenarios, library test |
| Water advisories (boil / do-not-drink / do-not-use; boiling never recommended for chemical advisories) | TESTED_CORE | SimulationTests.storedWaterDecision and advisory tests |
| Ranking (lexicographic tiers, deterministic ties) | TESTED_CORE | RankingTests |
| Counterfactual replay with structured diff; baseline untouched | TESTED_CORE | CounterfactualTests, fixtures/scenarios expected JSON |
| Helper reachability under fire blockage | TESTED_CORE | SimulationTests.helperReach |
| Egress planner (hard exclusions, confirmed-only evidence, wall audit, independent alternatives, typed no-route) | TESTED_CORE | RouteTests, RouteAdversarialTests (16 probes) |
| Scan import (proposals only, shared frame required, hull fallback flagged) | TESTED_CORE (synthetic input) | **No real RoomPlan scan tested** |
| Manual layout (rectangular rooms, doors on shared walls) | TESTED_CORE | SpatialManualLayoutTests; editor UI authored only |
| Guided confirmation pass | TESTED_CORE (logic) / IMPLEMENTED (UI) | PlanConfirmationTests, LeadAdversarialTests |
| Cache invalidation on home/household edits (revision + content fingerprint) | TESTED_CORE | RouteCache tests, PlanIntegrationTests.doorEditInvalidates |
| Plan document (EN/ES/VI, draft/fallback labels, private notes excluded, stale detection) | TESTED_CORE | PlanBuilderTests, PlanIntegrationTests.multilingualPlans |
| Late async results cannot overwrite newer state | TESTED_CORE (gate) / IMPLEMENTED (AppModel) | PlanSessionTests, LeadAdversarialTests |
| Capability matrix (LiDAR, model, camera, location, network independent) | TESTED_CORE (logic) / IMPLEMENTED (iOS probes) | PlanCapabilityTests |
| Encrypted vault (AES-GCM, authenticated header, atomic writes, tamper → recovery copy, locked ≠ corrupt ≠ key lost, delete-all scope) | TESTED_CORE on Linux | VaultTests. **Keychain, `.complete` protection, backup exclusion: device-only, untested** |
| Public pack cache (known-good retention, size/schema limits, region echo checks) | TESTED_CORE | PublicPackStoreTests |
| Alert freshness (expired, stale, demo, and cancelled never shown as current) | TESTED_CORE | PublicDataTests, vitest |
| Public API (no household endpoints, allowlisted IDs, rejects queries/bodies, NWS adapter) | TESTED_CORE (vitest, recorded fixture) | **Not deployed; NWS live call not exercised in tests** |
| FEMA NFHL | PARTIAL | Labeled fixture behind adapter; live integration not built |
| Regional agent (public-only; typed verbatim claims; template brief) | TESTED_CORE (vitest) | Adversarially reviewed; 9 findings fixed. No model provider; not scheduled; claims not shown in app; DNS-rebinding protection relies on the Workers runtime |
| Region directory | PARTIAL | Statewide pack; 2 verifiedPartial, 6 oemOnly, 5 notStarted of 13 counties; all `needsReview` |
| ES/VI translations | PARTIAL | Complete drafts, placeholder/number parity tested, drift guard; **no human language review** |
| SwiftUI app shell (tabs, onboarding, rehearsal, debrief, comparison, plan, help, settings) | TESTED_SIMULATOR | Xcode 27 / iOS 27 simulator; not run on a device |
| PDF rendering (Core Text, continuation pages, share/print) | TESTED_SIMULATOR | EN/ES/VI rendered and inspected on the simulator; AirPrint untested |
| RoomPlan capture, RealityKit dollhouse, 2D plan, MapKit | IMPLEMENTED | **Never compiled or run**; API uncertainties listed in docs/lanes/agent-b.md |
| Optional on-device explanations (FoundationModels, iOS 26, gated, validator) | IMPLEMENTED | **Never run**; template fallback is the tested path |
| UI test journeys | TESTED_SIMULATOR | 3/3 pass on the iOS 27 simulator |
| Privacy shield, temp-export lifecycle, generic error alert | IMPLEMENTED | Device behavior unverified |
| Demo launch modes, SwiftUI previews, screenshot-tour UI test | TESTED_SIMULATOR (tour) | Tour passes; previews not opened |
| macOS tooling (`scripts/mac/*`, `scripts/remote-mac.sh`, `.github/workflows/ios-verify.yml`) | TESTED (verify, screens, doctor) | Run on macOS 27 / Xcode 27; device.sh, remote-mac.sh and the workflow not run |

## Pending hardware and human verification (not done; do not claim)

- Run on an iOS 18 simulator or device (only iOS 27 was tested).
- Physical LiDAR RoomPlan scan → confirmation → routes in a real (consenting) home.
- Keychain accessibility class, behavior while locked, file protection class after atomic replace, backup exclusion.
- PDF output inspection (EN/ES/VI, longest strings, Dynamic Type), AirPrint.
- On-device Foundation Models availability, refusal, and fallback.
- Responsiveness on the oldest supported iPhone.
- Human safety-content review; ES and VI language review.
- A synthetic home fixture is not evidence that scanning works.
