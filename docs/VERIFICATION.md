# Verification record — October 17 revision

## Physical iPhone pass — October 18, 2026 (Claude, owner's iPhone)

Device: iPhone 16 Pro (LiDAR), iOS 26.6.1, Developer Mode on, signed with the owner's free Personal Team through
`scripts/mac/device.sh` (bundle `com.dryrun.dev.<team>`). Xcode 27.0. The phone is in dark mode, so these are the first
dark-mode checks; earlier simulator tours were light mode.

| Check | Result |
|---|---|
| Signed device build, install, launch | **Passes** (first launch needed the developer to be trusted on the phone, as expected for a new team) |
| App unit tests (DryRunTests) on device | **42 / 42 passed**, including encrypted vault and PDF export on real hardware |
| Demo journeys on device | **7 / 7 device-applicable passed** after one fix (below). The encrypted-vault relaunch journey is simulator-only by design (`#if targetEnvironment(simulator)`) |
| Screens on device | home 2D/3D, rehearsal scenes (fire, tornado, flood), family editor, Plan tab, card, Prepare, share: captured in `artifacts/screens-20261018-*` (ignored) and inspected |
| Simulator regression after these changes | DryRunTests 42/42, DemoJourneyUITests 8/8 (iPhone 17e); core `swift test` 320 / 51 suites |
| Real RoomPlan multiroom scan | **Not yet run**: needs the owner to scan rooms by hand |

Found on the device and fixed:
1. **Family editor buried "Add family member"** under ~50 rows for a four-person household; on real hardware the UI test
   could not even scroll to it. Each person is now a name field plus a one-line summary (age · needs) that expands;
   a newly added person opens expanded; single-person editing is unchanged.
2. **3D view**: room names added (flat on each floor, moved clear of furniture, dropped rather than drawn across a
   wall); cut-away walls lowered from 0.9 m to 0.6 m so small rooms and their names stay visible; model framed larger.
   Floor slabs now always face up with explicit normals regardless of outline winding.
3. **3D key**: a key under the 3D view (Home and Rehearse) that mirrors the builder's colour choices, listing only what is
   drawn, with the printed plan's wording.
4. **Scanning**: the shared ARSession is no longer started with plain world tracking before RoomPlan configures it
   (matching Apple's multiroom sample). RoomPlan's recognised room type (single unambiguous section label) pre-fills
   the room type and name in confirmation; it is never marked confirmed and changes no geometry (core test added).

## Native Mac pass — October 17–18, 2026 (Claude, owner's Mac)

**Status: native build passes; simulator tests run; physical iPhone/LiDAR testing not yet done (no device connected).**
Started from `8373597` (origin/main). Changes are in the commits that follow it on `main`.

Environment: Mac14,2, macOS 27.0.1, Xcode 27.0 (27A266a), iOS 27.0 SDK and simulator runtime, deployment target
iOS 18.0 (unchanged). Simulators: iPhone 18 Pro and iPhone 17e (small phone). No iOS 18 runtime is installed on this
Mac, so nothing here was executed on iOS 18 itself. No physical iPhone was connected, and no signing identity exists
(`security find-identity` reports 0).

| Check | Command | Result |
|---|---|---|
| Native simulator build | `xcodebuild … -destination 'platform=iOS Simulator,…' build-for-testing` | **Passes** after three Swift 6.4 region-isolation fixes (below) |
| Unsigned device build | `xcodebuild … -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **Passes** (RoomPlan/ARKit code compiled for iphoneos) |
| Core tests | `swift test --package-path packages/DryRunCore` | **319 tests / 51 suites passed** (317 inherited + 2 new) |
| Vault tests | `swift test --package-path packages/DryRunVault` | **35 passed** |
| Backend | `pnpm test` in services/public-api (after re-recording the ES/VI translation baseline) | **68 passed / 4 files** |
| App unit tests (DryRunTests) | `test-without-building -only-testing:DryRunTests` | **42 / 42 passed** on iPhone 18 Pro simulator |
| UI journeys (DemoJourneyUITests) | `-only-testing:DryRunUITests/DemoJourneyUITests` | **8 / 8 passed** in one final run (`.build-mac/results/final2-*`), including fresh install → contact → card → share preview, encrypted-vault relaunch, the connected address → meetup → recorded preparation → fire rehearsal → updated card → Share preview journey, and all three spatial hazards starting with the scene visible |
| Screenshot tour, small phone EN | `TOUR_LOCALES=en`, iPhone 17e | **Passed**, 28 screens captured and inspected |
| Screenshot tour, small phone ES + VI | `TOUR_LOCALES=es,vi`, iPhone 17e | **Passed**, inspected; remaining English is fictional sample data (room names, place names) stored like proper names |
| Screenshot tour, AX XXL text | `TOUR_XXL=1`, iPhone 17e, 9 main screens | **Passed**; inspected; two layout defects found and fixed (below) |
| Native PDFs | `-demoWritePlanPDFs` (fictional Oak, Lake, Pine), EN/ES/VI, Letter + A4 | Inspected page by page; validator issues: none. Oak full plan: 27 pages Letter / 25 A4, 1.3 MB (was 4.7 MB before icon caching and JPEG maps); card 2 pages, 48–60 KB. Copies in ignored `artifacts/claude-native-20261017/` |
| Physical RoomPlan capture, install, Share/Print on device | — | **Not run**: no iPhone connected |

### Native failures found and fixed

1. `PlanMapSnapshotRenderer.swift:61` — `sending 'snapshot' risks causing data races`. The snapshot is consumed in the
   completion handler without hopping to the main actor; only the finished `UIImage` leaves the closure.
2. `MapKitAdapters.swift:84` — the same pattern for directions, search and address resolution.
3. `MapKitAdapters.swift:193` (the hosted CI blocker) — the region checker could not analyse the task group. Each
   nearby category now runs as its own `Task` that owns its own service, so cancel-previous on one category still
   cannot cancel another, and the stale-generation guard is unchanged. No `@unchecked Sendable` or relaxed checking.
4. `PlanExportTests` long-note test failed for Vietnamese A4 only: Core Text wrapped the marker at a hyphen and PDFKit
   reported a line break inside it. The note was complete; the assertion now ignores line breaks.
5. UI journeys: one test swipe started on the Plan tab's map preview and panned the map instead of scrolling. That was
   also a user trap, so the preview map is now static (the full map opens from "Open map"). The place editor was
   presented with a separate flag and could appear blank; it is now presented from the place itself.
6. XXL text: the card's phone number forced the column wider than the screen, and the rehearsal key overflowed the scene
   frame. Phone numbers now scale down on one line; the key keeps its space and caps its size.

### Independent review (AI reviewer, read-only) and what changed

A separate reviewer inspected the 28 small-phone screenshots, all native PDFs and the navigation code. Findings fixed:
card selection differed between the in-app card (critical info off) and Share (on). Now there is one stored selection
for card, Plan, Share/Print and saved plans. Also fixed: the Vietnamese footer was truncated; A4 "Same as page N" used
the wrong page; a room label was drawn into a neighbouring room; route and badges covered room names on the phone;
the map key said "numbers match" while the near meetup had no pin; onboarding still described the old outage-only
product; "Ground floor" was untranslated; one-line diagram notes spilled onto their own page; raw source IDs were shown
without publishers; Debrief → comparison was a sheet on a sheet; pushed editors showed Back, Cancel and Save; the
"starting room not recorded" line contradicted later stages; rehearsals took 37–40 taps. "Next" now advances to the
next key moment (caution/critical event, decision or end). No event is skipped (core test), so fire is 6 steps and
tornado 17. Not changed: one diagram page per person per hazard (person-specific routes are a requirement), and
lowercase assistance-need labels.

### What this does not establish

Simulator results are not device results. RoomPlan capture, camera denial, tracking loss, shared-session merging,
real-scale measurements, Data Protection, AirPrint, the system share sheet's completion on a device, live Apple search
and directions in real locations, VoiceOver navigation order and Reduce Motion on a device were **not** tested here.
ES/VI strings are draft translations; no professional translation or safety review has taken place. Timing targets
(90 s to a useful card, 2–4 min rehearsal) have not been measured with people.

---

## Earlier record (Linux / hosted CI, before this pass)


**Implementation handed off for continued goal work; native build failing and device verification pending.**
Current source follows `4a3bd60`; evidence below records exact tested commits. The original revision baseline
was `2a8ab385a113cbcebcb8dc5a594d8ed8bacdd5b3`. The owner's two untracked root audit/handoff documents
were read fully and preserved outside commits.

## Actual platform and results

Linux x86_64, Docker `swift:6.2` (Swift Testing 6.2.4), Node/pnpm and portable Python/Poppler tools.
Authorized GitHub macOS CI provides Xcode16.4 and iOS18.5 SDK/runtime; native attempts and failures are recorded
below. No physical iPhone or LiDAR hardware is connected to this workspace. The owner confirmed the existing
Claude/Mac checkout will have a LiDAR-capable iPhone Pro and signing account; see [CLAUDE_NATIVE_HANDOFF.md](CLAUDE_NATIVE_HANDOFF.md).

| Executed command/check | Settled-source result | Local log |
|---|---|---|
| `DRYRUN_SCRATCH=native-followup scripts/swift.sh packages/DryRunCore test` | **317 tests / 50 suites passed** | `dryrun-native-followup-core-final.log` |
| `DRYRUN_SCRATCH=oct17-closure scripts/swift.sh packages/DryRunVault test` | **35 tests / 6 suites passed** | `dryrun-closure-vault.log` |
| `cd services/public-api && pnpm test && pnpm typecheck` | **68 tests / 4 files passed**; TypeScript clean | `dryrun-native-followup-backend-final.log` |
| Docker Swift `swiftc -parse`, every app/app-test/UI-test Swift file | **55 sources parsed**; syntax only, no SDK typecheck | `dryrun-native-followup-parse.log` |
| `git diff --check`; `bash -n` all shell scripts; Python AST parse all artifact scripts | Passed | `dryrun-closure-static.log` |
| `DRYRUN_DUMP=1` core dump, portable PDF generation and text/render audit | Seven fictional JSON snapshots; **14 Letter/A4 PDFs**; all text checks pass | `dryrun-closure-pdfs.log`, `dryrun-closure-pdf-audit.log` |
| Native simulator/iphoneos builds | **Attempted, failing SDK checks**; see exact runs below | GitHub artifacts |
| Native XCTest / simulator UI / live Apple services | **Not executed**; build gates failed | Native pending |
| Physical RoomPlan capture/review/assignment/save/relaunch/rehearse/export | **Not run** | Device pending |
| Real-household pilot / professional safety review / human translation review | **Not performed** | Human pending |

Logs are copied to ignored `artifacts/revision-20261017/logs/`; the portable PDF text audit is retained in
`output/pdf-text-audit.json`. Portable PDFs are ReportLab reference output, not native CoreText/PDFKit proof.
Current cards are two pages, the 12-person long-note card five pages, and full-plan references 24 pages in both
sizes. Each qualified scenario/person/floor panel has its own page; native pagination is a separate gate.
See [output/README.md](../output/README.md) for exact pages inspected and reproduction steps.

## What the portable tests establish

- Old/defaulted model fields, encrypted vault migrations, intentionally absent geometry versus corruption,
  retained contacts/custom labels/places and stable home identity. A layoutless household receives a card,
  general preparations and all six household exercises without invented spatial guidance.
- Subject-specific task identities/fingerprints; independent equipment/person records; actual fact save closes
  only the relevant preparation; recorded progress remains reviewable. Failed native saves are covered by
  authored app tests, not executed Linux UI tests.
- Cold-only and mixed medical requirements, selected sensitive fields, label/type migration, conservative backup
  allocation/setup/output/runtime, wheelchair transport and shared alarm presence/location/coverage/check gates.
- Plain home/location/place/coverage policies; selected pin priorities; source/contact metadata round trips;
  legacy named indoor meetup migration, bidirectional canvas edits/deletion and geographic rescan preservation.
- Deterministic spatial state, current routes/history separation, destination purposes, person-scoped window
  suitability, geometry/portal/mobility helper paths, captured frame/room lineage and callback generation gates.
  Local leaks are distinct from regional flood events/instructions/plan source scope.
- Thirteen reused spatial configurations: ranch, apartment, two-storey, studio/open-plan, concave, basement,
  walkout, split level, incomplete, duplicate opening, narrow/obstructed doorway and offset stair landings.
  Fire origins/resident starts/excluded rooms/exits, flood/refuge/floor relationships and tornado shelter/access
  have deterministic supported/no-route cases. Fixtures do not prove real homes or emergencies safe.
- Shared PlanHomePanel descriptors retain exact primary/alternative legs, final exclusions and every relevant
  start/path/destination/affected/exposed floor. Legacy panel qualifications resolve through the bundled locales;
  schema-one documents remain readable but stale. EN/ES/VI complete-pack, unit, provenance and fallback checks pass.

## Failures found and corrected

The first final full run reported **302 tests with three issues**, all the same new meetup/default-label
localization regression in EN/ES/VI. Generic marker types are now excluded from named-landmark migration; the
original localization assertions pass unchanged. Independent source review also found linked canvas meetup edits
being overwritten/deletions recreated. Focused bidirectional reconciliation now preserves all unrelated place
metadata and rescan plans. Four new behavioral tests and the settled **306/47** full pass cover the fixes.
The failed log `dryrun-closure-core.log` is retained alongside the final pass.

Independent preparation/maps/spatial reviews also corrected shared backup/alarm readiness, no-layout applicability,
helper/window/rescan semantics, local-leak exports, current-state PDF floors/leg styles, paper propagation and
selected preview/export mismatch. Portable visual review found furniture fills could hide room names; reference
and native renderer source now draw labels after furniture. Native drawing has not been executed.

Earlier 149-core/33-vault baseline results, the October 14 simulator tour, intermediate 262/289-core results,
and temporary Linux app-helper harness checks are historical evidence only. They are not added to the final
counts or reported as iOS execution. An earlier vault incremental binary failure was reproduced and cleared by
clean rebuild without changing source/expectations; the current fresh vault scratch passed 35 tests.

## Native and human gates still open

There are **42 authored native XCTest methods**: AppPersistence 9, MapRequest 3, MapDirectionsRequest 3,
PlanExport 7, PlanGenerationPrivacy 7, RehearsalNames 7, ReviewReminder 5, RoomPlanMapping 1; also **7 DemoJourneyUITests** and EN/ES/VI
screenshot tours. **Zero ran on iOS in this revision.** The new simulator-only encrypted-vault journey uses isolated file/Keychain namespaces and tests process
relaunch; it is not yet executed and does not establish physical Data Protection. In-memory journeys remain separate. Syntax parsing cannot establish SDK API/concurrency or selector correctness.

The Mac must compile against the installed SDK with the iOS 18 target, fix native failures, run the real connected
journey, inspect native PDFs/screens and perform installation. RoomPlan categories/transforms/parent IDs/story,
shared coordinates and actual LiDAR processing need measured physical verification. Live MapKit search,
permissions, stale callbacks, attribution/snapshots/offline states; activity/Print file leases and long-note
pagination; small phone, VoiceOver, Dynamic Type, Reduce Motion, light/dark and all translated forms remain
unverified. Native tests include failed-write and practiced-origin/leak selected-export cases but are unrun.

Manual correction offers constrained moves/resize, explicit floors/stair landings, room/opening/annotation review
and retained provenance; free vertex/CAD and independent captured-wall editing remain absent. Some preparedness
arrangements use concise household notes. Translation and safety content remain AI drafts; no professionals or
consenting household testers have reviewed this revision. Timing targets have not been measured. Do not label
this release fully verified, scanning Device verified, or Ready for iPhone testing before the corresponding gates.

## First hosted native attempt — run 39087041160

After the Linux closure, the existing manual GitHub macOS workflow was discovered and dispatched for exact
SHA `dbac954180a873b81b0088a1bb6d9bf20d47d171`. This supersedes the earlier statement that no native build had
been attempted; it does not establish a successful app build. Run:
https://github.com/1unarzDev/dryrun/actions/runs/39087041160

Actual environment: macOS15.7.9 arm64 VirtualMac2,1; Xcode16.4 (16F6), Apple Swift6.1.2, iOS/Simulator SDK18.5;
the default selector chose iPhone17 Pro from the installed runtimes. Hosted package checks passed: core306,
vault35, backend68 and TypeScript. App build-for-testing **failed** on the private CaptureGenerationDelegate's
unstable NSCoding class name. All native app tests, UI journeys, screenshots and native PDF gates were **skipped**.
No physical device/signing identities were available.

The delegate now has an explicit Objective-C class name while retaining immutable originating-generation checks.
This source fix awaits the next native run. The tabular verification-status detector was also changed from a
nonportable escaped-tab grep to an actual-column awk query; PASS/SKIP/failing and named-step queries passed on
Linux. The earlier workflow did report the native build failure; no erroneous successful Mac result is claimed.
The downloaded redacted bundle/logs are under ignored `artifacts/github-39087041160/`.

## Second hosted native attempt — run 39087330893

Exact SHA `a4550a138f5962b593ecd6bbbd758153058b47ea`, same Xcode16.4/iOS18.5 hosted environment:
https://github.com/1unarzDev/dryrun/actions/runs/39087330893
Core306, vault35, backend68/typecheck passed again. App build failed because this SDK exposes
`RoomCaptureView.captureSession` as optional; native app/UI/PDF gates were skipped. The controller now checks
for a session before assigning its delegate/running, retaining a retryable failure otherwise. This correction,
stable captured-room UUID projection, one additional native regression and a connected UI journey await rerun.
The simulator picker now prefers a runtime no newer than the selected SDK; portable mock harness tests passed.
Downloaded evidence: ignored `artifacts/github-39087330893/`.

## Third hosted native attempt — run 39087653478

Exact SHA `88cd8d6`, Xcode16.4/iOS18.5, now correctly selecting an iPhone16 Pro on iOS18.5:
https://github.com/1unarzDev/dryrun/actions/runs/39087653478
Helper regressions, core306, vault35, backend68/typecheck passed. The optional capture-session correction
compiled; app build next failed on Swift6 isolation of the async non-Sendable MKMapSnapshotter.Snapshot return.
App/UI/screenshot/PDF gates were skipped. The renderer is being changed to callback-owned rendering rather
than treating the SDK object as Sendable. Downloaded evidence: ignored `artifacts/github-39087653478/`.

## Fourth hosted native attempt — run 39088100904 (compile only)

Exact SHA `68f4278f9333fec70cceb9685360b997003f7aec`:
https://github.com/1unarzDev/dryrun/actions/runs/39088100904
Helper regressions passed; simulator build and unsigned iphoneos build failed. Package/backend/UI tests were
intentionally skipped in build-only mode. The snapshot callback fix passed its previous diagnostic; compiler
now found the same non-Sendable async response pattern in local search/directions/address resolution and the
unsupported SwiftUI POI spelling `.includingAll`. Those adapters now consume responses inside Apple's documented
main-thread completion handlers and return plain values; the map uses documented `.all` categories. No global
Sendable override or concurrency relaxation was added. Apple documentation for start(completionHandler:),
calculate(completionHandler:) and PointOfInterestCategories was rechecked directly on October17 local time.
These corrections await the next SDK run. Evidence: ignored `artifacts/github-39088100904/`.

## Closeout for Claude continuation — latest native blocker

The owner requested Codex close out and hand visual/PDF refinement and further goal completion to Claude,
with ideators and actual UI inspection. The complete original `/goal` is preserved verbatim in
[goals/2026-10-17-family-preparedness.md](goals/2026-10-17-family-preparedness.md). This handoff is explicitly
**not a completion claim**. See [CLAUDE_CONTINUE_PROMPT](CLAUDE_CONTINUE_PROMPT.md).

Fifth hosted run https://github.com/1unarzDev/dryrun/actions/runs/39088361958 tested exact SHA
`4a3bd60855cce77b99cc9f910323cd2dda24f4ed` in compile-only mode. Xcode16.4 (16F6), Swift6.1.2,
iOS/Simulator SDK18.5; iPhone16 Pro/iOS18.5 selected. Helper tests and XcodeGen passed. Simulator test-target
build **failed (67s)** and unsigned generic iphoneos app build **failed (28s)** with:

```
apps/ios/DryRun/Maps/MapKitAdapters.swift:193:23:
error: sending value of non-Sendable type '() async -> (Int, [AppleMapSearchResult]?)' risks causing data races
```

This is NearbyDiscovery's task-group child closure. Claude must fix it against the installed SDK while retaining
independent per-category services and stale-generation rejection; subsequent compiler errors may still emerge.
Earlier response-projection/POI diagnostics no longer appeared. No relaxed concurrency or Sendable override was
used. Full app/native XCTest/UI/screenshot/native PDF execution remains **unverified**; build-only intentionally
skipped test execution. No physical device/signing/scan was performed. Downloaded redacted logs are in ignored
`artifacts/github-39088361958/`; the linked Actions run is the remotely retrievable evidence.

Later closeout changes version the authored content as2026.10.2 so retained older plans become stale, and
regenerate the seven fictional JSON documents/14 portable PDF references. These are not additional native
build evidence. Original audit/handoff documents remain untracked; no real household data was uploaded.


## Final portable closeout rerun

After the content2026.10.2 bump and reference regeneration, the closing rerun passed:

- `DRYRUN_SCRATCH=native-followup scripts/swift.sh packages/DryRunCore test`: **317 tests / 50 suites**.
- `DRYRUN_SCRATCH=oct17-closure scripts/swift.sh packages/DryRunVault test`: **35 tests / 6 suites**.
- `pnpm --dir services/public-api test` and `typecheck`: **68 tests / 4 files**, TypeScript clean.
- `scripts/tests/mac-helpers.sh`, `bash -n` on all scripts, and `git diff --check`: passed.
- Docker Swift6.2 `swiftc -parse` on all **55 app/test Swift sources**: passed, syntax only.

Local logs: `/tmp/dryrun-closeout-{core,vault,backend,static,parse}.log`.
These final portable results do not change the hosted native failure or any pending simulator/device/human gate.
