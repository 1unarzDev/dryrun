# Verification record

## Family-preparedness revision (2026-10-17) — current evidence

**Implementation prepared; native build and device test pending.** Starting checkout: main at
`2a8ab385a113cbcebcb8dc5a594d8ed8bacdd5b3`. Current source revision is the latest commit updating
CLAUDE_NATIVE_HANDOFF.md; use `git log -1 --format='%H %s' -- docs/CLAUDE_NATIVE_HANDOFF.md` to identify it.
The owner's two untracked audit/handoff files were read and preserved, not committed.

Actual platform: Linux x86_64, Docker `swift:6.2`, Swift Testing 6.2.4; Node/pnpm. No Xcode/iOS SDK,
simulator, physical iPhone or LiDAR capture was available. Owner offered a Mac through a separate Claude session;
CLAUDE_NATIVE_HANDOFF.md gives commands and evidence gates. This pass cannot say Ready for iPhone testing.

| Executed command/check | Current result |
|---|---|
| `DRYRUN_SCRATCH=oct17-current-core scripts/swift.sh packages/DryRunCore test` | **246 tests / 36 suites passed** |
| `DRYRUN_SCRATCH=oct17-current-vault scripts/swift.sh packages/DryRunVault test` | **35 tests / 6 suites passed** |
| `cd services/public-api && pnpm test && pnpm typecheck` | **68 tests / 4 files passed**, TypeScript clean |
| Docker Swift6.2 `swiftc -parse`, all app, app-test and UI-test Swift sources | Passed; **syntax only**, no native SDK typecheck |
| `git diff --check`, shell syntax, Python artifact scripts compile | Passed |
| `DRYRUN_DUMP=1 DRYRUN_SCRATCH=preview scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump` | 1 opt-in generation test passed, seven fictional document JSON snapshots |
| Portable reference PDFs | 14 Letter/A4 artifacts, text extraction and rendered reference QA; **not native CoreText/PDFKit output**. See output/README.md |
| Native build, current simulator UI/integration tests, live Apple search/directions/snapshot | **Not run** |
| Physical scan/review/assignment/relaunch/rehearse/export, interruption and unsupported hardware | **Not run** |
| Real-household usability, safety expert or human translation review | **Not performed** |

Fresh baseline was actually established before edits: core149/23, vault33/5, backend68/4 and typecheck passed.
The final suites add meaningful no-layout migration, family/clinical selection, subject identity, cold-only/mixed
support, saved-meetup link, stale routes, grade/refuge/window/callback tests. SpatialRevisionTests reuse13 layout
configurations (studio/concave/basement/walkout/split/incomplete/duplicate/narrow/obstructed/offset landings/apartment/
ranch/two-storey), enumerating fire origins with representative starts and flood/tornado destination/access cases.
These fixtures do not establish all houses or real emergencies safe. Old tests were reconciled to current typed
no-refuge/current-route semantics; no safety gate was disabled to force a route. Fixture regeneration now requires
`DRYRUN_WRITE_FIXTURES=1`; ordinary empty environment no longer rewrites expected outcomes.

Independent lane source reviews found and fixed stale whole-household form writes, unsupported meeting-task blank
screens, hidden geometry in card-only exports, cross-page sensitive selection leaks, old route history in exports,
false home markers/resource meetup defaults, closed-attic refuge eligibility and processing-generation invalidation.
Final type-switch regressions verify that custom names survive while old compatibility/setup/runtime evidence is
cleared; the app and both test targets were syntax-parsed again and vault tests rerun after this change.
They did **not** inspect native screenshots. Local logs are in `artifacts/revision-20261017/logs` (ignored build
artifacts). Portable PDF audit/results are retained with fictional examples; no real home data was collected.

Native tests are authored and wired into project/scheme/verify script: 8 AppPersistenceTests, 3 MapRequestTests,
4 PlanExportTests, 5 ReviewReminderTests, 3 PlanGenerationPrivacyTests, 3 MapDirectionsRequestTests and 3 RehearsalNamesTests (29 total); 5 current DemoJourneyUITests plus the EN/ES/VI screenshot tour. **Zero executed native tests**
in this pass. The fresh-install UI test uses in-memory storage; real vault force-quit/relaunch remains a separate
native/device gate. Source parsing cannot establish their selectors or SDK concurrency correctness.

Material unverified/limited work: real SDK RoomPlan categories/transforms/story/shared-frame alignment, actual
MapKit failures/attribution, share/print lifecycle, small phone/large text/VoiceOver/Reduce Motion, EN/ES/VI end-to-end
rendering and human translations. Manual edits now include shape-preserving room resizing, explicit additional
levels/first rooms and separately recorded stair landings; free vertex/CAD and independent captured-wall editing
remain absent. The optional one-time local reminder is implemented but system permission/delivery/deletion paths
are unverified. Some preparedness details use household-authored notes rather than tailored questionnaires.
Validation issues/questions have EN/ES/VI key coverage; other dynamic text can still have English fallbacks.
Do not characterize this revision as fully complete or device verified. See REVISION_EVIDENCE.md for the mapping.

Follow-up verification added constrained correction/provenance/room-review, independent captured-wall retention,
current dynamic outlines after add/delete, actual concave-boundary opening placement, legal stair endpoints/mobility,
polygon-overlap/nonfinite regressions,
shared current shelter validation and isolated hypothetical selection, review maintenance, independent solo/joint
review, fact-specific check invalidation and EN/ES/VI issue/question coverage. Source reviews caught and fixed the
barrier/shelter/stale-check/nested-sheet defects before push. The fire blocked-space regression now asserts the
entire route, including its start; it no longer permits an implicit exposed-start exception.

An incremental vault binary initially failed `pruneStaleDropsResultsForOldRevisions` and crashed. The focused
failure reproduced in that scratch directory; the unchanged source passed all 35 tests in a fresh directory and
again after `swift package clean` rebuilt the original directory. No source/test expectation was changed for this
build-artifact failure. Final counts above come from current integrated sources; the failed/rebuilt logs are kept
locally alongside the final logs. Native tests are still zero executed.

## Integrated connected-flow follow-up (October 17 local / October 18 UTC)

The current full suites above passed after all implementation lanes froze. Logs are
`/tmp/dryrun-current-{core,vault,backend,parse}-final.log`, with ignored copies under
`artifacts/revision-20261017/logs`. An earlier concurrent build stopped because BaselinePreparedness changed
while compiling; the final run used settled sources. No test was disabled for that build race.

Added meaningful coverage includes oversized responder instructions after the main contact/meetup card without rewriting them; canonical quantity/ownership plus storage location; scoped medication and
equipment supplies; physical drill/flood/well/utility completion without changing hazards or routes; old contact
roles and the additive waterUtility role; exact subject IDs in comparison diffs; availability synchronization
that preserves untouched supply evidence; purpose-specific direct editors; supported coverage; failed selected
export with no retained-sensitive-plan fallback; stable place ordering; coordinate-only meetups; and selected
medical supply locations in every language. A utility number cannot substitute a family emergency contact.
The near-home meeting purpose now precedes the backup under a neutral Meeting places heading, independent of IDs.

Shared HomeScenePresentation tests exercise unavailable/upper-floor/unknown-grade/blocked openings, selected
floor and no-route starts, annotation/stair floor selection, and clearing a recorded opening width. Native views
now use that presentation contract; actual scene rendering remains unrun. Source review fixed the missing
sceneFloorID declaration, scan-review dismissal and highlighted item/floor mismatches.

Three additional Linux XCTest presentation checks compiled the actual Names.swift/DisplayNames.swift in a
throwaway SwiftPM harness (`/tmp/dryrun-names-presentation.log`): dotted subject IDs, unnamed-person fallbacks,
and EN/ES/VI number/unit/plural display. These are separate from the 246 core tests and do not constitute
execution of the native RehearsalNamesTests target. The target still requires Xcode.

Fourteen fictional Letter/A4 reference PDFs were regenerated from seven current core JSON documents and audited
for phone/meetup text, paper size, glyph replacement and long-note END marker. Representative current pages and
full-plan contact sheets were visually inspected; see output/README.md for exact limits. They are reference
ReportLab renders, not native screenshots or iOS PDF output. No native/simulator/device count has increased.

## Historical records below — do not apply them to the current build

## MapKit and RoomPlan integration pass (2026-10-16)

**Platform actually used:** Linux x86_64 checkout `/home/lunarz/dryrun`; portable Swift commands ran in the repository's
Swift 6.2 Docker harness (Swift Testing 6.2.4); Node 26.10.0 and pnpm for the backend. There is no macOS host,
Xcode installation, iOS SDK, simulator runtime, or physical iPhone/LiDAR device in this environment.

| Command | Result |
|---|---|
| `DRYRUN_SCRATCH=final scripts/swift.sh packages/DryRunCore test` | **149 tests in 23 suites passed** |
| `DRYRUN_SCRATCH=final scripts/swift.sh packages/DryRunVault test` | **33 tests in 5 suites passed** |
| `cd services/public-api && pnpm test && pnpm typecheck` | **68 backend tests passed**; TypeScript typecheck clean |
| Docker `swift:6.2` `swiftc -parse` over every `apps/ios/DryRun/**/*.swift` (mounted checkout) | **Passed**; syntax parsing only |
| `git diff --check` | Passed |

The portable suites exercise coordinate validation and provenance, county frames, resource precedence, private-place
separation, legacy vault decoding, save-failure behavior, RoomPlan import/geometry, confirmation, interruption and
unknown-start handling. The backend tests cover the paired Zod contract and regional scoping. Source parsing does not
prove that MapKit, Core Location, RoomPlan, RealityKit, SwiftUI, or strict-concurrency APIs compile against an iOS 18
SDK. No simulator journeys, Apple Maps search/directions calls, screenshots, or physical RoomPlan capture were run or
visually reviewed here. See [`docs/MAPKIT_SCAN_INTEGRATION.md`](MAPKIT_SCAN_INTEGRATION.md) for the architecture,
privacy boundary, provenance, offline behavior, migration behavior, and device checklist.

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
| Manual layout (rectangular rooms, doors on shared walls) | TESTED_CORE | SpatialManualLayoutTests; editor UI compiles, not exercised by UI tests |
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
| RoomPlan capture, RealityKit dollhouse, 2D plan, MapKit | PARTIAL | Compile on Xcode 27; 2D plan and 3D view rendered in the simulator tour. RoomPlan capture (needs LiDAR) and the MapKit view not exercised |
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
