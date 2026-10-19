# Wired-iPhone pass — October 19, 2026 (Claude on the Mac)

Inputs: `docs/ai/CLAUDE_WIRED_IPHONE_HANDOFF_PROMPT.txt`, `DryRun_AI_Implementation_Reference.md`, the UX
concentration audit and the Mac integration handoff, at `main` `26332de`. Work is on branch
`worktree-wired-iphone-pass`. Device: iPhone 16 Pro (iPhone17,1), iOS 26.6.1 (23G83), USB, Developer Mode, owner's
Personal Team. Xcode 27.0 (27A266a). Node 25.8.1. All households, homes and Gemini traffic in this pass are the
fictional demo data; no real household data was sent anywhere.

Evidence categories used below: **phone** (ran on the wired iPhone, screenshots inspected), **sim** (iOS simulator),
**Mac** (Core/gateway tests or scripts on macOS), **live synthetic** (real Gemini with fictional data),
**pending** (not done; reason given). "Passed" means the named test or journey ran; it is not a safety claim.

## What changed in the app

| Outcome / objective | Native state after this pass | Evidence |
|---|---|---|
| Persistence of AI state | `IntegratedAIState` (inventory, sessions, practice, concerns, scorecards) is saved inside every atomic household save; unreadable state is a recovery case; moving home keeps supplies/practice and drops old-home sessions/reviews | Mac unit, sim, phone (relaunch test over the real encrypted vault on device) |
| Personalised preparation (1) | Unchanged three-action Prepare list, now followed by the provisional scorecard | phone |
| Supply intake → gaps (3) | "What you already have": six reviewed kinds, unknown amounts stay unknown, usable and reachable recorded separately, one batch confirmation, Core gaps; recorded water total reconciled once, then the old gallon field is read-only | phone (4 usable, reachable gal → "Short by 8 US gallons") |
| Adaptive rehearsal (5) | Adaptive exercise on `SimulationSession` receipts (scene, routes, resources from the committed receipt), typed actions previewed by the host, resume after relaunch, failed saves publish nothing; `LocalDirector` (Core) is the offline director; guided authored rehearsal unchanged | Core (all 6 scenarios), sim, phone |
| Gemini director (5, objective 5) | Core `DirectorGatewayBridge` builds the strict minimized context and whitelisted tool results; TS gateway schemas accept them; Debug-only phone client (launch arguments, fictional households only) with an in-view opt-in naming Google Gemini and honest fallback | Mac (9 contract checks), phone (requests reached the gateway; see "Gemini" below) |
| Stress (6) | The reviewed home-fire envelope runs on device for the score; a shared escape chokepoint is named on the scorecard | phone |
| Scorecard (7) | Provisional score from `HouseholdAssessment` + rubric-v0 + practice; "Limited by…" only when the cap binds, otherwise "critical items not yet confirmed"; breakdown with Unknown/Partly/Gap, never green | phone (ranch 22, apartment complex 21, manufactured 17) |
| Practice check (7) | Four frozen situations from the household's own facts (practice-phases/2), first answer recorded before feedback, feedback marked revealed before shown, no reroll, unassessed ≠ wrong | Core, phone |
| Housing (objective 1) | Apartment complex (3 floors), manufactured, two-story, ranch: every floor in 2D and 3D captured | phone (24 screenshots) |
| Elevators in fire (objective 2) | Warning for the whole fire exercise in apartments/elevator homes; route uses shared stairs only; "No independent second way out" stated | phone |
| Markers (objective 3) | Tapping a marker opens its own editor; invalid coordinates keep the editor open with the marker unchanged; Save applies the visible position; a moved marker returns to "Location needs review" | phone |

## Test runs on the final build

| Suite | Where | Result |
|---|---|---|
| DryRunCore `swift test` | Mac | 485 tests / 89 suites passed (adds LocalDirector, gateway bridge, practice sources) |
| DryRunVault `swift test` | Mac | 39 / 7 passed |
| Gateway `vitest` + `tsc` | Mac | 89 tests / 13 files passed (adds Swift→Zod native-bridge contract); typecheck clean |
| Public API incl. EN/ES/VI translation drift | Mac | 68 / 68 passed |
| DryRunTests (app unit, incl. encrypted vault AI-state round trip, adaptive resume/failed save, inventory) | **phone** | 47 / 47 passed |
| DeviceAuditUITests (adaptive fire + water, every floor 2D/3D, scorecard ×4 homes, supply intake, marker relocation, practice check, large text) | **phone** | 8 / 8 passed; screenshots inspected |
| DemoJourneyUITests | **phone** | 10 / 11 passed. `testDescribeHouseholdReviewThenTarrantCountyHelp`: the on-device model correctly proposed "Mother · Oxygen concentrator", a dog and "Apartment · Renter" on the phone, then the test could not locate the county picker on iOS 26 (passes on the iOS 27 simulator; unchanged code; test-locator issue left open) |
| Full app suite | sim (iPhone 17e, iOS 27) | earlier run: all unit tests and UI journeys passed except the two since fixed (escape checks, elevator identifier) |

## Defects found on the phone and fixed

1. **Escape checks wiped by a room rename.** Recording the dwelling type made every home edit look like geometry
   changed. Fixed in `HomeGeometryEditor.requiresNewEscapeCheck`; app test.
2. **Elevator warning missing before the fire is placed**, and its identifier swallowed by the scene container.
3. **3D view cropped/over-zoomed on upper floors** (third-floor unit, upstairs): the dollhouse did not subtract the
   floor elevation introduced by the Linux `point3D` change. Fixed; all floors re-captured on the phone.
4. **Adaptive exercise asked "the smoke alarm sounds, what is the first move?" before the alarm event** (local
   director skipped same-minute events when a choice was already due). Fixed; Core ordering test across 6 scenarios.
5. Duplicate "you chose" card; decision shown with no situation context; raw key `adaptive.req.relocation`.
6. Scorecard said "Limited until confirmed" when the 79 cap did not limit a score of 21.
7. Floor pickers listed the third-floor unit before the shared ground floor (data order, not level order).
8. **Marker list opened the general editor instead of the tapped marker** (stale sheet selection). Item-driven sheet.
9. Supply entry: decimal pad had no way to dismiss; two menu pickers per item; unhelpful "not enough recorded".
10. Gateway: the director proposed `startIncident` again while an incident was active; the repair message never
    said why, so every mid-exercise turn failed validation. `director/8` adds the rule and a specific repair reason.
11. Large text (AX-L): the "Provisional" pill hyphenated beside the score; the adaptive header squeezed two
    labels into narrow columns. Both now stack when they do not fit.
12. Caught by Core before release: an empty `inventory.unit.count` string in all three languages made ES/VI
    count as incomplete (no longer selectable). The key is removed; counted items show no unit word.
13. Test-only: `HousingDemoTests` did not compile (Linux-authored); `device.sh` passed `-demoLocale` to devicectl.

## Gemini on the phone

- Mac, live synthetic: `smoke.ts` on the native macOS host passed (5 calls, revision 6, exact replay; trace
  `fixtures/ai/adaptive-trace-all-mac-v1.json`). One quality defect retained: the second purpose claims a wait
  "until the next checkpoint at 24 hours" while the committed receipt stayed at minute 900.
- Mac, live synthetic, native request: the Swift-built fire request first failed validation (defect 10); after
  `director/8` Gemini returned a valid `advanceIncident` + `advance` + `requestDecision` tool preview.
- Phone, first attempts: after Local Network permission, requests reached the gateway, but from 14:24 UTC both
  models returned **503 "high demand"** and the original key was free tier (20/day on 3.8-flash, exhausted). Every
  turn fell back to the on-device director, which the app stated on screen. Two replacement keys failed with 402
  "prepayment credits depleted" (a billed AI Studio project is not funded by Google Cloud trial credit) and 403
  "requests … are blocked" (API restriction). A free-tier key on a project without prepaid billing worked.
- **Phone, live (19:16 UTC, `gemini-3.1-flash-lite`, fictional apartment complex, home fire, capped at 2 turns):
  passed.** Family answered "get out" → Gemini's tool preview first proposed `startIncident` again, the `director/8`
  repair corrected it to `advanceIncident` → the phone executed the preview through Core and continued → Gemini's
  final proposal `advanceIncident(fire-origin@1), advance(2), requestDecision` was validated by
  `DirectorProposal.commit` and saved. The scene showed each person's route via the shared corridor/stairs "still
  clear in this exercise", "No separate second exit is modelled", and paused for the family. The same journey also
  passed on the iOS 27 simulator (19:13 UTC). Gemini's narration is shown only as labelled unverified text.
- Requests used: about 6 Gemini calls across both runs; well within the free allowance.

## Remaining, not done in this pass

- Feature roles (preparation, resources, home review, council) are not wired
  natively; `/v1/features` is untouched on device.
- Nearby-resource strategy with MapKit (outcome 2), image capture/redaction/concern review (outcome 4), site hazard
  editing UI (objective 4): not integrated natively in this pass.
- Production authorization (App Attest), provider terms/billing review for real households: not started.
- VoiceOver walkthrough, largest Dynamic Type and smallest-phone checks of the new screens; ES/VI wording is a draft
  needing human review; human safety/rubric/fairness review of the score and practice check; real RoomPlan scans.
