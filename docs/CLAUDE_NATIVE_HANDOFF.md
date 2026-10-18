# Native verification handoff — October 17 revision

Status: **Implementation prepared; native build and device test pending.** This Linux pass has no Xcode,
iOS SDK, simulator, LiDAR hardware, or real-household usability observations. Historical October 14 simulator
results do not verify this revision. Continue implementation when native checks expose defects; do not merely
run the scripts and mark the brief complete.

## Session instructions

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

Suggested opening prompt for the existing Claude session:

> Read docs/CLAUDE_NATIVE_HANDOFF.md, VERIFICATION.md, REVISION_EVIDENCE.md and current repository instructions
> completely. Reconcile this Mac checkout with origin/main while preserving local work. Continue the October 17
> DryRun revision through the installed-SDK native build and simulator journeys; fix failures, capture current
> fictional screenshots/PDFs, and prepare/install the iPhone build when signing/hardware allows. Keep iOS 18,
> privacy and deterministic routing. Record exact SHA/SDK/device results. The owner authorized commit/push,
> with no publishing, third-party outreach or private-home uploads.

## Build and simulator

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

Follow-up native gates authored but not run: 8 AppPersistenceTests, 3 MapRequestTests, 4 PlanExportTests and
5 ReviewReminderTests (20 total), plus 5 DemoJourneyUITests and screenshot tours. The reminder fake tests suspend
authorization/add, cancel as Delete Everything does, then resume to check no late reminder remains. Exercise actual
system permission denied/granted, one-time delivery, relaunch, cancellation and successful/failed Delete Everything.
No permission request or schedule is allowed merely by opening Settings/review.

The home canvas now has constrained shape-preserving resize/move, explicit additional levels/first rooms and
separate stair landings. Confirm that independent captured walls remain after another room changes, added/deleted
rooms have current outlines, and corrected rooms/doors/stairs stay unavailable until independently reviewed. Test
selection reset/Undo/draft/failed save, and shelter invalidation after grade/window/lower-level changes. These native
controls and SDK coordinate assumptions have not been typechecked or visually exercised in Linux.

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
