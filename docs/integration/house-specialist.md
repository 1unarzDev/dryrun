# House editing integration slice

Owner: house_simulation; HOME-02, HOME-01, HAZ-01..03, UI-01, REL-01. Base 26332de with existing owner work preserved. No phone session used by this specialist; all native acceptance belongs to the exclusive designated reviewer on the plugged-in iPhone 16 Pro.

## Purpose and contract

A family corrects the selected room name/type or an opening classification directly on the existing home plan, then saves once. This improves the indoor exit/shelter decision by keeping the graph and shown opening classification aligned. Captured coordinates and IDs remain canonical. Simpler alternative considered: lists alone; retained canvas selection because it identifies the actual opening. Existing lists remain an accessible alternative.

Known inputs: actual saved graph/revision, selected element ID, recorded opening operability/access and shelter suitability. Unknown safety facts remain separate from valid capture dimensions. No exact exterior coordinate or disaster-safe route is inferred.

The editor callback is `@MainActor (HomeModel, Int?) async -> Bool`. The explicit `savedBaseRevision` init argument is captured once in State; nil means expected absence of a saved home. AppModel must compare current optional revision for equality, including nil, before persisting. The root owns AppModel/callers. Save snapshots the draft, prevents concurrent interactions and dismissal during persistence, and dismisses only after true. False preserves edits and exposes retry feedback. Cancel leaves persistence untouched. Pending marker edits apply before saving. Reclassification preserves ID/endpoints/floor/sides/width while clearing prior escape suitability; an open doorway cannot transfer operability evidence to a new door/window.

## Files

- apps/ios/DryRun/Spatial/ManualHomeEditorView.swift: awaited save, cancel, direct selected-canvas navigation, immediate opening-type control; remove room dimension/measurement/review controls and opening measured-width input.
- apps/ios/DryRun/Spatial/HomeRoomListView.swift: remove legacy room measurement/name-confirmation suffixes.
- packages/DryRunCore/Sources/DryRunCore/Spatial/HomeGeometryEditor.swift: transactional reclassification.
- packages/DryRunCore/Tests/DryRunCoreTests/OpeningReclassificationTests.swift: stable geometry/identity, escape-evidence invalidation, no-op/error atomicity, doorway operability guard.

## Shared scenario agreement

Retain the existing scenario-house-contract.md authority. Fire routes use supported indoor paths and do not certify outside accounting from intent. Tornado candidates require suitable recorded room plus reachable per-person route. Flood refuge requires supported floor/access facts, separate from a household leak. Maps may hand off a confirmed exterior exit to a labeled home-origin geographic preview; no door coordinate can be invented. These changes add no simulation movement store and no score credit. Scenario transitions/person-specific shelter/exterior accounting remain scenario/integration-owned acceptance gates.

## Evidence and remaining gates

Focused Swift test first capture run-ec0e901df1f045978fce9130e125467a returned exit 1; raw diagnostics requested from dedicated reviewer. Retried with authorized cache access through the same firewall: run-d42474b77f84479e9bffa4687d5d98eb returned exit 1. Source inspection subsequently corrected a new test assigning EvidenceValue instead of Bool to emergencyEscapeConfirmed; recheck still required. No protected output inspected. No Mac native build or physical verification claimed by specialist.

Required iPhone reviewer sequence: use hh-oak isolated example; select room and opening from canvas/list, ensure highlight follows; switch Door/Window and confirm geometry unchanged; Cancel/reopen unchanged; save/relaunch retains corrected classification and route refresh; inject failed write and stale revision (including an initially unsaved draft versus newly saved scan), verify draft retained and new saved graph protected; repeated Save no duplication. Check ordinary and accessibility text size. Real RoomPlan capture requires owner-assisted physical movement and must be recorded separately from imported synthetic capture tests.

## Lead house/simulation pass — branch lead/house-simulation (base cdb4098), 2026-10-21

Owner-authored record by the house environment and simulation lead. No phone or simulator launched; no AI output read. Milestone 5 of docs/goals/2026-10-20-beacon-demo.md, HOME-01, HOME-02.

Reconciliation finding: the donor branch (5f95135) had wired the compact opening card into the editor and saved-version Undo/Redo into the Home tab; the integration merge kept the Core (ScanCorrections, HomeEditHistory, AppModel undo/redo) and the card view but dropped both call sites, so the card was reachable only inside "Check your scan" and saved-version Undo was unreachable. This pass restores them on the integrated editor rather than adding a parallel surface.

### Feature purpose — compact opening card in place (HOME-02)

- Household/situation: a family whose RoomPlan scan mislabeled an opening (door seen as window, doorway to the wrong room, a blocked door).
- Decision improved: which openings fire/tornado/flood routes may use, from the actual saved graph.
- Known inputs: captured opening ID/endpoints/floor/sides, scan snapshot, recorded operability. Unknown: whether a newly reclassified door opens without keys (kept unknown until answered in More details); exterior adjacency of a captured opening is the family's answer, never inferred.
- Why here: tapping the opening on the existing plan opens the existing contextual editor; the card replaces the earlier four-kind grid and the one-way "Mark as not usable" button, keeping identifiers home.opening.type.{door,window,opening} used by HomePersistenceUITests.
- Next step / taps: tap opening (1) → choose Door/Window/Open doorway/Not an opening (1) or Leads to (2) → Save (1).
- Observable benefit: both sides of the selected opening are tinted on the plan, so a Leads to answer is visible immediately; Restore what the scan saw returns the exact captured opening; Not usable is a toggle and is reversible (legacy rejected openings reopen as proposed, never silently verified).
- Simpler option considered: keep the list-only editor. Rejected: the goal requires a compact in-place card; lists stay as an accessible alternative. Leads to offers only same-floor rooms the captured opening touches (scan attach distance, ScanCorrections.leadsToRooms) plus Outside, so an answer cannot connect rooms the geometry does not join. Moving an opening to another wall stays under More details for hand-built homes only; scanned geometry is never edited by measurement.

### Feature purpose — immutable scan snapshot on Save

HomeEditTransaction.prepare now keeps the stored scanSnapshot when the saved draft is the same capture (same source and non-nil capture frame), so no draft path can rewrite what the scan saw. A rescan (new frame) or a replacement hand-built home brings its own. Revert whole home to scan (existing ScanCorrectionSection) therefore always reads the original capture.

### Feature purpose — blocked open doorway excluded from routes (correctness fix)

Found by the new card test: marking an open doorway Not usable (operable=false) still left it on planner routes, while HomeScenePresentation already drew it unavailable. EgressPlanner now excludes any opening whose operability is recorded false; HomeValidator no longer counts such a doorway as a verified ground exit. RouteResult.algorithmVersion is unchanged: only homes with an explicit false on a doorway change, and this pairing could not previously be produced from the UI. Scenario lead: shared route authority changed only for that case; no fixture or digest depends on it in the Core suite.

### Feature purpose — saved-home exit overlay and saved-version Undo/Redo on the Home tab

- Household/situation: after correcting the scan, the family wants to see that the way out changed.
- Decision improved: whether each resident's recorded starting room has a supported way out on the committed home.
- Inputs: saved home and household starting rooms only (never the draft); step-free need → wheelchair profile, the same rule as rehearsal and assessment. No scenario exclusions, no evidence or score credit (HomeCommittedRoutes is read-only).
- Presentation: the 2D plan draws each distinct route (legend "Practice route"); people without a route are listed with the planner's localized reason; a toggle hides the lines. Undo last change / Redo appear when saved versions exist (AppModel HomeEditHistory, last 20 per home, each step a new revision-checked save).
- Simpler option: rely on the Plan tab's saved panels. Rejected: those come from the last generated plan document, not the just-saved home.
- Scenario contract: this overlay is the committed-state view only; hazard-specific blocked states remain owned by SpatialExerciseState in rehearsal. No parallel movement store.

### Evidence (this pass)

- deterministic-tested: OpeningCardCorrectionsTests (9 XCTest) — every card answer sequence (type × Leads to × Not usable) per opening keeps captured endpoints, recomputes through RouteCache and Restore returns the exact scan portals and route; Not an opening leaves routes and restores in scanned order; Not usable reversible on manual homes; legacy rejected reopen; revert matches scan routes for every start room; snapshot immutable across Save with stale-base rejection; committed routes follow saved edits. ScanCorrectionsTests (7), HomeEditTransaction/OpeningReclassification suites pass.
- Mac-build: generic iOS unsigned build succeeded after the native changes.
- Not claimed: device-verified or live-reviewed. AppModel edit history is in memory for the app session (survives Save, not relaunch); persistence across relaunch would need an AppModel/persistence change owned by the orchestrator. New Home-tab strings (toggle label) fall back to English until locale packs (orchestrator/content scope) add keys.

### Phone checks requested (exclusive reservation, synthetic hh-oak, en then AX size)

1. Home tab → 2D plan: practice-route lines from each resident starting room; toggle hides them.
2. Tap pt-front on plan → card appears in place; plan tints Living room and outline; choose Window → checkmark moves, route line from the Home tab changes after Save; Undo last change on Home tab restores Door; Redo reapplies.
3. Tap interior door → Leads to lists only touching rooms + Outside; choose another → both sides tinted.
4. Toggle Not usable on, Save, confirm no route uses it; toggle off, Save, route returns.
5. Not an opening → returns to overview; Undo (draft) brings it back; Cancel discards all.
6. HomePersistenceUITests.testRoomAndOpeningEditsSurvivePhysicalAppRelaunch (uses home.edit, home.opening.type.window).
7. Inject failed write/stale revision: draft kept, message shown, no partial commit.
8. Owner-assisted gate: real RoomPlan scan of a room (person moving the phone) → Check your scan, Restore what the scan saw, Revert whole home to scan, Save, relaunch.

## Lead2 house pass — branch lead2/house (base bd6974a), 2026-10-22

Owner-authored by the house lead. No phone or simulator launched; no AI output, recorded response or fixtures/ai content read (regenerated fixtures/ai/native-bridge files were committed unread; they are Swift host-built wire written by DirectorGatewayBridgeTests). Answers wave-1 audit findings HOME-01 opening validation, the house items of the integration unresolved list, and F4 from report-prep15-v5-baseline-vs-investigation-repeated-review.

### Outside only for outside-wall openings (HOME-01, device finding LEAD-LEADSTO)

- Household/situation: a family correcting a scanned or sample home taps an interior door and could answer "Leads to: Outside"; the door then became a verified EXIT used by routes.
- Rule (Core, one place): `PortalAttachment.interiorRoomPair` finds two same-floor rooms the opening would join under the existing two-room attachment rule. If such a pair exists the opening is interior. `ScanCorrections.canLeadOutside` is the card's offer rule; the card shows Outside only for outside-wall openings (a recorded Outside answer stays visible so the picker never hides it) with a one-line explanation otherwise.
- Contradicted answers stay unverified: `setLeadsTo(... .exterior)` on an interior opening keeps the answer but leaves it `proposed` and returns false; Check your scan "That's right" (`ScanCorrections.confirm`) and `HomeConfirmation` exterior marking cannot verify it. Already-saved verified answers from the old editor are excluded by `EgressPlanner` (`portalNotVerified: outside answer on an opening between two rooms`), drawn unconfirmed by `HomeScenePresentation`, flagged needs-confirmation by `HomeValidator`, and not counted as a ground exit. No unverified exit is labelled usable.
- Simpler option considered: hide Outside only in the UI. Rejected: legacy saved data and the scan check would still verify it.

### egress-portal-graph/3

Bumped for the wave-1 operable=false doorway exclusion and the new contradicted-exterior exclusion; noted in scenario-house-contract.md with scenario-lead acknowledgement PENDING. AuthoredAdapterTests now projects only the route version label back to /2 before comparing the unchanged historical digests (and asserts the live version is current); every other byte must still match. Swift host-built native-bridge fixtures regenerate with /3; gateway native-bridge.test.ts passes on them.

### Saved-version Undo/Redo survives relaunch (separate AppModel commit)

`IntegratedAIState.homeEditHistories` (optional, omitted when nil so existing sidecar bytes and digests are unchanged, never projected into AuthorizedAIContext). AppModel writes the home and its history in the same atomic vault save, reloads it whenever the sidecar changes (load, save, reset, family switch), and keeps an in-memory copy only if an unreadable sidecar must be preserved. Limit stays 20 versions; each entry is a full HomeModel (scan snapshot included), so a heavily edited scanned home enlarges the sidecar — watch on device.

### Home tab route toggle localized

`spatial.show-exit-routes` (en/es/vi) via SpatialStrings; plus `spatial.card.outsideInteriorNote` and `spatial.card.outsideNeedsCheck`. es/vi are author translations, not native-speaker reviewed.

### F4 shared example-home annotations

All example families get the sample ranch, whose medical marker depicts Oak's oxygen concentrator. `SampleHomes.forExampleHousehold` keeps a medical-equipment marker only when the family records equipment of that purpose (fictional homes only; personal homes untouched). Applied in AppModel.useSampleHousehold/preview and in NativeGatewayInputExportTests (the v5/v6 corpus exporter); frozen v5 bytes are untouched. Not applied to DryRunHost `initialize` (gateway synthetic host) to avoid drifting gateway host traces this wave — follow-up for the integration owner. Devices that already loaded Lake/Pine keep the stray marker until the family is chosen again.

### Evidence (this pass)

- deterministic-tested: OutsideAnswerAndHistoryTests (8 XCTest: offer rule across every sample home, interior Outside stays proposed and off every route for every start room, legacy verified answer excluded with /3, outside-wall answer confirmed, one-room scan opening still offers Outside, history sidecar round trip and historical decode, history absent from provider context, F4 marker projection); ScanCorrectionsTests updated to the new contract; OpeningCardCorrectionsTests unchanged and passing.
- Full Core `swift test` via firewall: run-0467538abf1f49b0a218ee9013169912 exit 1 before the AuthoredAdapterTests projection (per-suite bisection: only AuthoredAdapterTests, run-480dac069a114a6386426796995b22cb); after the fix run-57a6e050a2cd48e98231a20537195011 exit 0.
- Gateway: `vitest run test/native-bridge.test.ts` run-dc96a1c2369a439893cb324158f22264 exit 0. Full gateway suite not rerun.
- Mac-build: xcodegen generate + `xcodebuild build-for-testing -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO` TEST BUILD SUCCEEDED (includes new AppPersistenceTests.testSavedHomeUndoRedoSurvivesRelaunchAndResetsWithTheHousehold, compiled not executed).
- Not claimed: device-verified, native unit tests executed, scenario-lead acknowledgement.

### Phone checks requested (exclusive reservation; clean install or Settings reset, synthetic hh-oak, en then es/vi, standard and AX size)

1. Clean-state doorway Not usable: Home → edit → tap pt-living-kitchen (open doorway) → Not usable on → Save; Home tab 2D plan with routes on: no route uses it, opening drawn unavailable; Not usable off → Save → route through it may return.
2. Interior door Outside blocked: tap pt-living-hall → Leads to lists the room on the other side only (Hallway or Living room) — no Outside; explanatory footnote shown. Tap pt-front → Outside offered and selected.
3. Legacy data (only if a pre-fix vault exists on device): an interior door saved as Outside shows "Needs checking", is drawn unconfirmed, no route exits through it; choosing the room restores the connection.
4. History after relaunch: rename a room → Save → Undo appears → force-quit and relaunch → Undo last change still present and restores the name → relaunch → Redo present and reapplies; choose Lake → no Undo/Redo.
5. Route toggle label reads "Show the way out from each starting room" / es / vi, wraps at AX size.
6. F4: choose Lake, then Pine → Home tab Safety markers have no "Oxygen concentrator"; Oak still has it.
