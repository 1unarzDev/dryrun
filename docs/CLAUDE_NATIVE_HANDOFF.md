# Native verification handoff — October 17 revision

Status: **Claude continuation requested; implementation is not complete. Native build failing; physical test pending.**
Authorized GitHub macOS CI has Xcode16.4/iOS18.5 and is exposing SDK issues, which are being fixed rather than
handed off as successful. See VERIFICATION for exact commits/runs. The owner confirmed this existing Mac
checkout will have a LiDAR-capable iPhone Pro and an Xcode signing account. No physical scan or installation
has occurred from this workspace. Historical October14 screenshots do not verify this revision.

## Session instructions

**Owner's latest direction:** Claude owns the next PDF/visual refinement and continued product pass.
Use [the copy-ready continuation prompt](CLAUDE_CONTINUE_PROMPT.md). Read
[the original /goal, preserved verbatim](goals/2026-10-17-family-preparedness.md) completely and independently
audit current implementation against it. This handoff is not a completion certificate. Use ideators and actual
UI/PDF inspection to improve map/home/icon visual communication, remove nested friction and finish the
connected rehearsal journey without feature bloat. Reconcile missed requirements, not just the latest diff.

Read `Dry_Run_MapKit_Codex_Handoff.md` if supplied by the owner, this file, `docs/VERIFICATION.md`,
`docs/REVISION_EVIDENCE.md`, and current instructions/uncommitted changes. The user requested a full connected
family-preparedness app and authorized commit/push. Preserve newer checkout work. No publishing, submissions,
outreach, real-home uploads, or deployments are authorized.

The owner confirmed the Mac already has a checkout. Inspect its instructions and local work first; reconcile
them with the pushed source without resetting or discarding newer Mac changes. Use `main` from `https://github.com/1unarzDev/dryrun`; record `git rev-parse HEAD` and `git status --short` before
changing anything. The latest Linux follow-up is the newest commit updating this handoff (find with
`git log -1 --format='%H %s' -- docs/CLAUDE_NATIVE_HANDOFF.md`). Evidence must identify the actual tested SHA,
plus any subsequent native fixes. Do not force-reset a checkout with changes.

For an unchanged checkout, inspect divergence before a fast-forward:

```bash
git status --short
git fetch origin
git log --oneline --left-right HEAD...origin/main
# Only after resolving any local changes/divergence without losing work:
git merge --ff-only origin/main
```

Suggested opening prompt: copy the complete contents of `docs/CLAUDE_CONTINUE_PROMPT.md` into the existing
Claude session. It includes the owner's original-goal link, explicit non-completion instruction, ideator/visual
workflow, privacy/safety boundaries and verification/commit requirements.

## Build and simulator

**Start here:** latest exact tested SHA `4a3bd60855cce77b99cc9f910323cd2dda24f4ed`, hosted run
https://github.com/1unarzDev/dryrun/actions/runs/39088361958 failed simulator and unsigned iphoneos builds at
`Maps/MapKitAdapters.swift:193`: NearbyDiscovery's non-Sendable task-group closure transfer. Resolve against
Xcode16.4/iOS18.5 (or the installed supported SDK) without removing independent category ownership or stale-result
guards. Other diagnostics may follow; no successful full target build or app/UI execution is claimed.
The existing workflow also offers `mode=build` for compile-only diagnosis and simulator/xxl inputs for screenshots.

```bash
scripts/mac/doctor.sh
scripts/mac/verify.sh
scripts/mac/screens.sh --xxl --locales en,es,vi
```

Requirements: a usable Xcode with Swift 6.1+, XcodeGen (`brew install xcodegen`), an installed iPhone simulator,
and Node/pnpm for backend checks. `project.yml` keeps **iOS 18.0**. Select the installed Xcode; do not raise the
minimum target to fix compatibility errors. Prefer an iOS 18 runtime too when available. Record Xcode, SDK,
runtime, phone size, and OS. Use `--sim-name` to select a device. Run the normal and a small phone separately.

`verify.sh` runs native core/vault tests, backend checks, build-for-testing, **DryRunTests** (persistence/map
fake-service/export/reminder tests), current **DemoJourneyUITests**, screenshot tours, and native demo PDFs. Inspect every
PASS/FAIL/SKIP in its SUMMARY; a bundle existing is not success. First resolve SDK/Swift 6 errors in
RoomPlan/MapKit/RealityKit/SwiftUI before polishing. Linux `swiftc -parse` never typechecked those APIs.

Current UI tests/tours were revised for Prepare/Rehearse/Plan and are **authored, unrun**. Correct the actual
app defect or obsolete selector with evidence, rather than disabling a failing gate. The tour must show the
intended screen, not just successfully attach a launch screenshot.

Manually verify these connected journeys (record exact results and errors):

1. Fresh **real vault** install: create personal household → skip address/scan → add structured international
   contact → open family card without devices → select critical fields → preview/share/print → force quit/relaunch.
   Confirm data persists, no fictional home is attached, and spatial guidance says layout unavailable.
2. Family editor: self/name/relationships/unknown age, second resident, critical information, no phone contact.
   Switch equipment/backup types in both entry points; intentional custom name survives; adding backup does
   not confirm compatibility/setup. Test medicine-only and mixed refrigeration/electric needs.
3. Address/map: Texas, other US, non-US, rural, skipped/manual/unresolved. Deny GPS and search near confirmed
   home; automatic bounded discovery, cancel/retry/radius expansion, rapid address/category changes. Home and
   two meetups remain after sheet dismissal/relaunch. Edit/delete through every entry point. No Texas fallback.
4. Save one factual preparation → it closes automatically; independent device tasks remain separate. Failed
   write retains draft and old state. Review/Undo where supported. No generic Done certifies a physical fact.
   Change a recorded alarm location/availability: check/coverage/awareness must reopen; notes alone preserve them.
   Solo card review must not imply joint family review. The new core helper tests are portable, native forms unrun.
5. Rehearse fire/flood/tornado from beginning: one current scene, person selection, origins/starts, choices,
   earlier-stage review, inaccessible/no-route outcomes, Reduce Motion. Current blocked route disappears;
   comparison changes only hypothetical facts. Verify all six scenarios remain reachable.
6. Live Plan changes after contact/address/place/home edits; export selected content, qualified exact route
   geometry, separate indoor/neighborhood panels. Force snapshot failure/offline. Share and Print use identical
   preview data. Long notes paginate fully (end marker), Letter/A4/grayscale, EN/ES/VI, large family.
7. Share lifecycle: open activity sheet, background, cancel/finish; file survives while activity needs it, then
   is purged. Repeat Print completion/cancel. No private fields in public-service requests or diagnostics.
8. VoiceOver, small display, large Dynamic Type, contrast/light/dark and text/list alternatives. Record actual
   time to first useful card and a rehearsal; 90 seconds and 2–4 minutes are targets, not measured claims.

Follow-up native gates authored but not run: 9 AppPersistenceTests, 3 MapRequestTests, 7 PlanExportTests and
5 ReviewReminderTests, 7 PlanGenerationPrivacyTests, 3 MapDirectionsRequestTests and 7 RehearsalNamesTests and 1 RoomPlanMappingTests (42 total), plus 7 DemoJourneyUITests and screenshot tours. The reminder fake tests suspend
authorization/add, cancel as Delete Everything does, then resume to check no late reminder remains. Exercise actual
system permission denied/granted, one-time delivery, relaunch, cancellation and successful/failed Delete Everything.
No permission request or schedule is allowed merely by opening Settings/review.

The home canvas now has constrained shape-preserving resize/move, explicit additional levels/first rooms and
separate stair landings. Confirm that independent captured walls remain after another room changes, added/deleted
rooms have current outlines, and corrected rooms/doors/stairs stay unavailable until independently reviewed. Test
selection reset/Undo/draft/failed save, and shelter invalidation after grade/window/lower-level changes. Hosted SDK checks now compile these source paths; full target success and visual execution remain separate gates.
Coordinate/scale assumptions still require device measurements.

## Physical installation and scan gate

```bash
DEVELOPMENT_TEAM=<TeamID> BUNDLE_ID=com.<unique>.dryrun scripts/mac/device.sh
```

Owner signs into Xcode, trusts/connects the iPhone and enables Developer Mode. The script detects valid signing
teams when possible; see its signing hints. No Expo Go server can run this SwiftUI/RoomPlan app. Use native
Xcode/device installation; Expo would require a different client and cannot supply this native capture flow.

Follow `docs/DEVICE_CHECKLIST.md` on a consenting LiDAR-capable iPhone Pro. Native target must compile and the
installation path must work before saying **Ready for iPhone testing**. Say **Device verified** only with an
actual scan, review, assignment, persistence, rehearsal, and export record. Unsupported/manual fallback is a
separate device check. Keep real geometry/addresses/medical information local; share fictional screenshots only.

## Return evidence

Return a branch/commit with native fixes, build/test logs, redacted environment, failures/skips, new fictional
screenshots/recordings, inspected native PDFs (including long notes), and completed device checklist when hardware
exists. `artifacts/mac-*/` has local xcresults; tarballs omit xcresults because they may contain private host/device
identifiers. Inspect/redact attachments before sharing. Do not erase errors or replace unrun checks with old results.
Update VERIFICATION, UI_AUDIT, REVISION_EVIDENCE and this handoff with exact commands, SHA, counts and remaining
hardware/human limits. Safety and translation professional review remain pending unless actually obtained.

## Latest connected-state closure to exercise on the Mac

Settled-source portable result: **317 core / 50 suites, 35 vault / 6 suites, 68 backend / 4 files**, clean
TypeScript and 55 app/test Swift sources syntax-parsed. **The 42 native XCTest methods, seven UI
journeys and screenshot tours still await successful app compilation and execution.** The last Linux commit updating this file contains these changes.
Do not substitute historical results. See VERIFICATION for the failed-and-fixed migration regression record.

1. Begin all six hazards without home geometry. Household decisions and continuity should remain useful;
   no fictional scene, routes, stairs or shelter may appear. Test intentional absence through actual vault relaunch.
2. Alarm readiness agrees in Prepare/fire with and without a layout: presence, location, coverage reviewed,
   explicit functional check. A verified marker alone is insufficient. Review Recorded preparations through
   direct editors; contact/place save closes only its actual task. Two medical subjects stay independent.
3. Backup source ownership/assignment never confirms device testing, compatibility, safe generator placement,
   solar islanding, output/shared load or runtime. Exercise unknown-first and second-device allocation; cold-only
   medicine needs storage/availability and selected notes without electrical runtime. Wheelchair transport matters.
4. Same-home rescan keeps home/address/meetups but uses source room/frame lineage to remap residents. Unrelated
   ordinal collisions clear assignments. Window inventory/legacy Boolean alone authorizes nobody; suitability
   is person-specific. Helper reach cannot cross walls or incompatible portals/stairs.
5. After interruption process retained valid RoomPlan groups. They must freeze their originating frame/group,
   invalidate the active session before stop and reject late callbacks. Failure retains the draft; unrelated frames
   never merge. Verify actual installed SDK/parent/category/transform/story/structure assumptions and measurements.
6. Compare a local household leak and regional flooding. Leak events/choices/plan headings/instructions must not
   borrow regional roads, well/outage, displacement or higher-refuge assumptions. Fire origin/start exposure and
   selected shelter routes stay canonical. No-layout hazards remain explicitly unknown spatially.
7. Select practiced scenario export after changing origin/starts/choices/seed. A matching real exercise is reused;
   hypothetical comparison edits never become facts. Selected preview and direct Share/Print use the same newly
   persisted content; failure never falls back to an older sensitive document. Controls stay locked while preparing.
8. Inspect family card before diagrams in phone preview. All relevant start/path/destination/affected/exposed
   floors appear, including no-route stages. Primary solid/alternative dashed, current exclusions/start marker and
   route qualifications agree across phone/2D/3D/PDF; old route history never reappears. Letter/A4 propagates from
   selection through preview toolbar share. Long text and map failure cannot hide contact/meetup details.
9. No-op/unit-only address correction preserves explicit coverage; actual geographic correction clears it.
   Official text-only resources open shared save/contact/directions details; saved source metadata survives
   relaunch. Near/backup meetup pins precede optional resource limits, with matching text numbering.
10. Legacy verified named indoor meetup migrates to text-only SavedPlace without inventing a pin; generic raw
    marker labels do not. Edit its name/finding instructions in the canvas, save and relaunch; every card/task
    updates. Delete explicitly and verify it stays deleted. Rescan/replacement/lost room preserves geographic plans.
11. Rapid destination/origin/mode/home/category changes reject late GPS/directions/discovery responses. Test real
    Apple unsupported routes, GPS denial, map-snapshot failure and Apple attribution. Retained essential text works
    offline; live search/routes/tiles are not promised.
12. EN/ES/VI forms, selected values, scan coaching, alerts' English fallback, dates/decimals/plurals and card source
    notices; US versus VN/FR/unknown water uses gallons only for US and otherwise litres. Proper names/critical
    notes remain exact. Explicit US/CA service numbers are sourced; unknown foreign locations do not default to 911.

Reference examples: seven JSON documents and 14 ReportLab Letter/A4 PDFs, with two-page cards, five-page long
card and 24-page full plans. Core-computed current home panel descriptors are included in the reference-only JSON
envelope. These intentionally spacious layouts are not native output or page-count targets. See output/README
for actual inspected pages. A room-name/furniture ordering issue was fixed in reference and native renderer
source; native figures still need visual inspection. Translation/safety expert review and real-household timing
remain pending. The owner’s Mac checkout must retain its own uncommitted/newer work during integration.
