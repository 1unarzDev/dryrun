# Verification record

**Platform actually used:** Arch Linux x86_64, kernel 7.2.8; Docker image `swift:6.2` (Swift 6.2.x, Swift Testing
6.2.4); Node 26.10.0; pnpm. **No macOS, no Xcode, no iOS SDK, no simulator, no device.**
Date: 2026-10-09.

## Commands and results (final run)

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
| SwiftUI app shell (tabs, onboarding, rehearsal, debrief, comparison, plan, help, settings) | IMPLEMENTED (authored, parse-checked, reviewed) | **Never compiled** |
| PDF rendering (Core Text, continuation pages, share/print) | IMPLEMENTED | **Never rendered**; ES/VI clipping and diacritics unverified |
| RoomPlan capture, RealityKit dollhouse, 2D plan, MapKit | IMPLEMENTED | **Never compiled or run**; API uncertainties listed in docs/lanes/agent-b.md |
| Optional on-device explanations (FoundationModels, iOS 26, gated, validator) | IMPLEMENTED | **Never run**; template fallback is the tested path |
| UI test journeys | IMPLEMENTED | **Never run** |
| Privacy shield, temp-export lifecycle, generic error alert | IMPLEMENTED | Device behavior unverified |
| Demo launch modes, SwiftUI previews, screenshot-tour UI test | IMPLEMENTED | Parse-checked only; never run |
| macOS tooling (`scripts/mac/*`, `scripts/remote-mac.sh`, `.github/workflows/ios-verify.yml`) | IMPLEMENTED | ShellCheck-clean and `bash -n`; YAML valid; **never executed on macOS** — first run may need small fixes (`xcresulttool` flags vary by Xcode version) |

## Pending hardware and human verification (not done; do not claim)

- Compile and run on Xcode 26 / iOS 18+ simulator; run `DryRunUITests`.
- Physical LiDAR RoomPlan scan → confirmation → routes in a real (consenting) home.
- Keychain accessibility class, behavior while locked, file protection class after atomic replace, backup exclusion.
- PDF output inspection (EN/ES/VI, longest strings, Dynamic Type), AirPrint.
- On-device Foundation Models availability, refusal, and fallback.
- Responsiveness on the oldest supported iPhone.
- Human safety-content review; ES and VI language review.
- A synthetic home fixture is not evidence that scanning works.
