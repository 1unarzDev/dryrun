# Verification record — October 17 revision

**Implementation prepared; native build and device test pending.** This record covers the settled integrated
sources committed with this file, following `e43f9acf4e1f533a6ebba32324256cf8a1b1144c`. Identify the exact SHA
with `git log -1 --format='%H %s' -- docs/CLAUDE_NATIVE_HANDOFF.md`; native evidence must name the actual tested
SHA and any local changes. The original revision baseline was `2a8ab385a113cbcebcb8dc5a594d8ed8bacdd5b3`.
The owner's two untracked root audit/handoff documents were read fully and preserved outside the commits.

## Actual platform and results

Linux x86_64, Docker `swift:6.2` (Swift Testing 6.2.4), Node/pnpm and portable Python/Poppler tools.
No Xcode, iOS SDK, simulator, physical iPhone or LiDAR hardware was available. The owner confirmed that the Mac
handoff uses an existing Claude session and checkout; see [CLAUDE_NATIVE_HANDOFF.md](CLAUDE_NATIVE_HANDOFF.md).

| Executed command/check | Settled-source result | Local log |
|---|---|---|
| `DRYRUN_SCRATCH=root-plan scripts/swift.sh packages/DryRunCore test` | **306 tests / 47 suites passed** | `dryrun-closure-core-final.log` |
| `DRYRUN_SCRATCH=oct17-closure scripts/swift.sh packages/DryRunVault test` | **35 tests / 6 suites passed** | `dryrun-closure-vault.log` |
| `cd services/public-api && pnpm test && pnpm typecheck` | **68 tests / 4 files passed**; TypeScript clean | `dryrun-closure-backend.log` |
| Docker Swift `swiftc -parse`, every app/app-test/UI-test Swift file | **54 sources parsed**; syntax only, no SDK typecheck | `dryrun-closure-parse-final.log` |
| `git diff --check`; `bash -n` all shell scripts; Python AST parse all artifact scripts | Passed | `dryrun-closure-static.log` |
| `DRYRUN_DUMP=1` core dump, portable PDF generation and text/render audit | Seven fictional JSON snapshots; **14 Letter/A4 PDFs**; all text checks pass | `dryrun-closure-pdfs.log`, `dryrun-closure-pdf-audit.log` |
| Native iOS build / native XCTest / simulator UI / live Apple services | **Not run** | Mac pending |
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

There are **39 authored native XCTest methods**: AppPersistence 8, MapRequest 3, MapDirectionsRequest 3,
PlanExport 6, PlanGenerationPrivacy 7, RehearsalNames 7, ReviewReminder 5; also **5 DemoJourneyUITests** and EN/ES/VI
screenshot tours. **Zero ran on iOS in this revision.** The in-memory fresh-install UI journey is not proof of
real-vault force-quit/relaunch. Syntax parsing cannot establish SDK API/concurrency or selector correctness.

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
