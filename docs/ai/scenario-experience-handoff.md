> Integration target observed at commit/push: `origin/main` is `f9b296c` with eight newer wired-iPhone commits, including Core-session/Gemini integration. This Linux work is being pushed separately from base `26332de`; reconcile those native changes before integrating. Native-pending claims below describe this Linux checkout and verification scope, not an audit of the newer Mac implementation. Do not replace the newer session screen with the older authored-cursor screen wholesale.

# Claude / Mac handoff: scenario experience and readiness setup

Checkpoint: 2026-10-20, following the owner's additional 30-minute visual/experience slice. Continue the existing goal and dirty checkout; do not restart the implementation. Root `DryRun_AI_Implementation_Reference.md` is the complete specification. Sections 10 and 13 remain acceptance gates, not claims satisfied by this preview.

**No live provider calls were made in this slice.** Conserve the remaining Gemini/Groq quota for Claude. Prior complete and partial live evaluations still have unresolved quality failures; see [current corrective handoff](mac-corrective-handoff.md) and [coverage report](six-scenario-coverage.md). The broader native corrections, PDFs/cards, offline use, practice persistence and score integration remain required.

## First Mac steps

Run `scripts/mac/verify.sh --quick` to generate/build with Xcode and expose actual SwiftUI type errors; Linux could not perform that check. Launch the connected phone with `scripts/mac/device.sh -- -demoHousehold hh-oak -demoTab rehearse`, then tap each hazard normally to test setup. `-demoScenario` intentionally starts directly and therefore does not verify the new questions. Use existing signing/device selection options from `scripts/mac/device.sh`'s header as needed. After build fixes, connect the durable incremental receipt as described below and run the six-row phone checks; do not label the authored cursor as AI integration.

## Delivered code and exact integration surface

- `packages/DryRunCore/Sources/DryRunCore/Simulation/RehearsalExperienceDesign.swift`: shared six-hazard objectives, scene/debrief keys, localized setup questions, strict option-to-authored-variant mapping, current-state resource graphics and read-only scene projection. Rejects unknown options/questions/packs and mismatched experience hazards. Focus answers change screen emphasis only. No score or household commit occurs.
- `apps/ios/DryRun/Rehearse/ScenarioExperienceViews.swift`: new native setup and six separate receipt-capable scene compositions. Explicit same-page questions, relevant recorded assistance/equipment/storage/water context, optional fire origin/water-affected room, accessible selection controls. Unknown water is distinct from empty; resource fill requires compatible units and a finite positive recorded baseline. Water gets a volume reservoir; freeze gets heat/power/reserve readings; heat gets cooling and available room ranges.
- `apps/ios/DryRun/Rehearse/RehearseViews.swift`: normal entry opens setup instead of immediately starting. Explicit demo launches preserve the prior direct-start path. Replay reopens setup, retaining variant and geometry assumptions. Existing fire/tornado/flood floor-plan, room list and 3D views stay in place, with hazard-specific objectives/titles. Thermal/water authored runs use the new status scene. Debriefs add each hazard's learning objective and review focus. Removed a stale generic measurement-confirmation sentence while retaining genuine missing access/opening facts.
- `content/scenarios/heat-grid-strain.json`: additive `cooling-followup` variant and `choice.heat-grid-strain.powered-evening`. New setup's no-rotating-outage answer records **both** `no-rotating-outage` and `cooling-followup`. It yields a second cooling-arrangement decision while electricity remains available. Stay/relocate uses existing host feasibility and consequence rules; a missing destination remains a gap. Historical no-outage inputs without the opt-in tag retain their original schedule.
- `content/locales/{en,es,vi}/{native,scenarios}.json`: 138 experience keys plus six new heat follow-up strings per locale. Translation-baseline hashes record their source wording; **language/safety review remains pending**.
- `packages/DryRunCore/Tests/DryRunCoreTests/RehearsalExperienceDesignTests.swift`: real pack execution for every offered option, source preservation, two-decision checks, private-well applicability, bounds/units, future-event exclusion, advisory persistence, receipt projection, serialization and all-language resolution. Export includes 12 actual authored runs against unchanged Oak/ranch facts. `AuthoredAdapterTests.swift` preserves the original captured alternate-input choice dictionary by excluding the new opt-in question; the original 24 result hashes are unchanged.

The current native execution path is still `RehearsalCursor` over authored results. **It is not the incremental Gemini director.** No invented individual arrivals or temperature ranges are filled into this authored path. Fire/tornado/flood keep their working spatial renderer rather than acquiring an extra generic status panel. `HazardStatusScene` already has all six compositions for the incremental integration.

To connect the incremental native screen, construct `RehearsalScenePresentation` from **one durable receipt**:

```swift
guard let scenario = library.scenario(session.initial.scenarioID) else {
    throw SessionError.invalidCommand
}
let presentation = try RehearsalScenePresentation(
    hazard: scenario.hazard,
    snapshot: receipt.snapshot,
    baseline: initialReceipt.snapshot,
    experience: receipt.experience,
    visibleEvents: receipt.events
)
```

Here `library` is the loaded `ScenarioLibrary`, and `initialReceipt` is the stored initial receipt of this same session. Bind `HazardStatusScene(presentation:household:home:focusedServiceIDs:isHouseholdLeak:)` to that session's frozen household/home. Use the receipt's spatial state/routes for the first three hazards; show actual outside/accounted/sheltered rosters. Do not read edited `model.home` into an old receipt or derive arrival from a route preview. Authored projection additionally receives the result's `snapshotHistory`; it fences events by the current snapshot boundary and visible cursor events so an advisory persists without revealing future events. A successful service restoration does not itself clear an advisory.

Before publishing an AI choice, finish the existing gateway-owned whole-sequence `validateSuggestedActions` continuation described in [director tools](director-tools.md). Only the selected command sequence enters the host's atomic user commit. Keep its durable action receipt and existing practice/score flow. Provider switching, setup answers and previews must never reset the session, replenish supplies or earn competency credit.

## Readiness and visual checks on the iPhone

Use the same synthetic Oak/ranch for all six, then mutate only the fact noted. Ordinary navigation is necessary to test setup: `-demoScenario` deliberately bypasses it. An in-memory demo household with `-demoTab rehearse` lets you tap the scenario cards without using a real family's data.

| Scenario | Setup controls and real assumptions | Observable scene / decision checks |
|---|---|---|
| Home fire | Standard/hallway smoke; recorded/blocked second exit; optional ignition room | Change origin between occupied bedroom and usual exit path. Map's affected rooms, excluded connections and current route follow the cursor. Replay retains the selected origin. Incremental connection must show actual outside/accounted people separately; no reentry or multi-hour battery objective. |
| Tornado | Recorded/night timing; recorded/damaged home | Shelter/approach and window exposure stay visible, with a shelter objective rather than outside meetup. Test helper alone versus accompaniment using the retained branch trace; only host-committed arrivals count. Manufactured-home/inaccessible-shelter limits remain explicit. |
| Flash flood | Regional/leak; extent unknown/home-flooded for regional mode; access/water screen focus; optional affected room | Regional flooding uses affected-room/access routing, never the tornado lowest-room objective. Leak hides regional extent but still has two setup questions. It must not inherit regional road closure/displacement. Check both leak decisions remain available. |
| Freeze / power loss | Standard/extended outage; warmth/power screen focus | Heat and power order reflects focus; actual backup/device/phone reserves stay unit-aware. No invented temperature appears in authored mode. Incremental mode uses real illustrative range and actual energy consumption. Missing cold-storage documentation stays unknown. |
| Heat / grid strain | Rotating/no rotating outage; cooling/water screen focus | No-outage setup records both tags and reaches **two** decisions. Compare feasible recorded relocation with staying, then remove destination and confirm relocation is blocked. Power is initially available; no automatic blackout. Room ranges only appear when supplied by the receipt. |
| Water outage | Municipal: distinct advisories + independent power condition. Private well/unknown source: supply/power focus + independent power condition | No municipal advisory picker for the private-well household. Mutate only source to municipal to exercise boil/do-not-drink/do-not-use. Reservoir/current quantity persists through later steps; unknown isn't zero; restored flow doesn't clear advisory. No rising-floodwater room scene. |

Across all six: normal and largest supported Dynamic Type, narrow iPhone, English/Spanish/Vietnamese, VoiceOver selected-option announcement, 44pt targets, Reduce Motion, light/dark appearance. Confirm no duplicate generic scene pushes choices needlessly below the map. Check current-event and pending-decision scrolling. Change water source while setup is open: stale advisory answer keys are pruned; no unusable hidden answer blocks Start. Edit or replace the home before a new setup: stale room selections clear. An active session still displays its frozen original home.

Replay and leaving/reentering the screen must not silently change household facts, complete preparations or alter scores. After actual practice completion, run the persisted-attempt/queue/score checks from the main corrective handoff. Recheck PDFs and family cards. RoomPlan hit testing and durable native room Save/relaunch remain separately pending.

## Runnable traces and review artifact

```bash
# Full offline suite, including six-hazard branching, continuity and replay
scripts/verify-ai-portable.sh

# Generate 12 current-state/setup traces directly from Core; no model calls
DRYRUN_WRITE_FIXTURES=1 scripts/swift.sh packages/DryRunCore test --filter RehearsalExperienceDesignTests

# Regenerate the 24 actual incremental branch receipts if necessary
pnpm --dir services/ai-orchestrator exec tsx scripts/six-hazard-branches.ts

# Build a self-contained interactive review page from those actual fixtures
python3 scripts/render-rehearsal-experiences.py
```

Open `artifacts/ai/rehearsal-experience-preview.html`. Each hazard supports both decisions and Before/Choice A/Choice B. `?decision=1&branch=1` opens later Choice B comparisons. This is a **portable design/data preview, not native rendering**. `fixtures/ai/rehearsal-experience-review.json` contains the Core-exported setup and 12 actual authored scene traces. The branch report uses the same explicitly mutated municipal household across all six; setup traces retain the original private-well Oak. The preview states this distinction rather than blending the facts.

Linux Firefox screenshots reviewed the default board and later branches; a narrow 430px render was also produced. The browser artifact is not a substitute for SwiftUI screenshots or iPhone usability. No CDN, model, remote image or network data is needed to open it.

## Acceptance status

- **Linux-tested:** portable setup/projection logic, real authored variant runs, current-state exports, retained 24 incremental branch comparisons, replay/conservation and full offline regressions (exact latest results added in checkpoint below).
- **Live-model-tested:** no new tests in this slice. Earlier live results retain their explicit semantic/provider failures. All-six live quality and useful sourced Groq discovery remain open.
- **Synthetic-only:** all development households, home geometry, resources and branch traces here.
- **Native-pending:** SwiftUI typechecking/build, native interaction/layout, incremental-screen wiring, actual RoomPlan and durable Save/relaunch. Linux performed Swift syntax parsing only.
- **Human-review-pending:** emergency content, assistance/clinical/manufacturer boundaries, translations and family usability.

### Verification checkpoint

The preceding full offline suite `/tmp/dryrun-portable10-final.log` completed with exit 0 before this visual slice. For this slice, `/tmp/dryrun-visual-portable-final.log` passed Core **533 tests / 95 suites**, Vault **39 / 7**, public API **68**, gateway **199 / 24**, TypeScript and the included offline evaluators; **the complete process exited 0**. A subsequent focused run `/tmp/dryrun-experience-final-tests.log` passes **10 / 1**, adding the powered-heat follow-up's feasible and missing-destination branches after the full portable run. The final complete Core rerun `/tmp/dryrun-experience-core-final.log` then passes **534 / 95**, exit 0. Public API/localization tests were repeated after the final source-baseline addition: **68 passed**, exit 0 (`/tmp/dryrun-experience-public-tests.log`). No new model evaluation was launched.

Native files passed `swiftc -frontend -parse` in the Swift 6.2 Linux container (`/tmp/dryrun-native-scene-parse.log`). This establishes syntax only, **not SwiftUI typechecking, Xcode build, RoomPlan behavior or actual Save**. Existing harmless Swift/Node deprecation warnings remain in the logs.

Keep the new/untracked Swift file, Core source/test, fixture, renderer and this handoff when transferring the working tree. A tracked-files-only `git diff` omits new files. Do not overwrite the existing dirty changes or treat this as a clean standalone patch of the entire goal.

Logs and machine-readable results are retained under `artifacts/ai/scenario-experience-checkpoint/`. The review screenshots are `artifacts/ai/rehearsal-experience-before.png` and `artifacts/ai/rehearsal-experience-after.png`; both are Linux browser renders.

Screenshot “before/after” refers to the state before/after an actual branch, not to old/new iOS app versions.

Final source audit replaced the nonfunctional fire-night setup option with the actual `hallway-smoke` variant; tornado night describes its implemented alert-continuity check. Core 534/95 and public 68 were rerun successfully after this correction. The Core review fixture and HTML were regenerated.

## Completed-run debrief follow-up

The following additional implementation belongs with this scenario slice:

- `packages/DryRunCore/Sources/DryRunCore/Simulation/RehearsalDebriefEvidence.swift` projects a **finished authored cursor** into final hazard-specific route/service/resource/advisory/relocation evidence. Routes come from the final spatial snapshot, not the fire evaluation history; this prevents repeated people and stale available routes. Incomplete runs or missing final snapshots are rejected. No facts, inventory, practice evidence or scores are changed.
- `RehearsalDebriefOutcomes` in `apps/ios/DryRun/Rehearse/ScenarioExperienceViews.swift` renders this evidence inside the existing debrief in `RehearseViews.swift`, using the run's frozen household. It labels feasibility as evaluation rather than arrival. Fire retains second-way-out limitations; tornado and flood use their own interior objectives; thermal hazards show relevant services and reserve deltas; water shows final volume and continuing advisory. Relocation uses actual `rule.relocation` events, including blocked outcomes; transport availability alone never establishes departure.
- `RehearsalDebriefEvidenceTests.swift` executes all six against unchanged Oak/ranch, explicitly answers reached decisions, verifies final snapshot identity and one route per person, round-trip/replay, used/blocked/unrecorded relocation provenance, final advisories, unknown-versus-empty water, and rejection of missing/incomplete outcomes. `fixtures/ai/rehearsal-debrief-outcomes.json` is a **synthetic engine export, not model output**.
- Eight additional EN/ES/VI experience strings (146 total) cover these outcomes. Human translation/content review remains pending. The rehearsal recommendation row's effort badge now uses the urgent red tint for unmet essential requirements, including No cost; check it together with Prepare's existing urgent styling.

Exact additional Mac checks:

1. Build/typecheck the new views and Core source with the existing Xcode target; reconcile source inclusion if the project uses explicit file membership. Linux syntax parsing does not validate SwiftUI types.
2. Finish each hazard through ordinary UI choices and inspect `debrief.outcomes.<scenarioID>`. Back navigation during an unfinished run must not display fabricated final outcomes. Check one row per person; a later unavailable fire route must not be replaced by an earlier available evaluation. Neither route availability nor the generic objective text may imply an actual arrival.
3. For heat with no rotating outage, compare stay versus the recorded accessible cooling destination, then remove that destination. Expect unrecorded, used and blocked relocation respectively. Inspect reserve values/deltas against the actual final receipt/snapshot, with consistent units.
4. With municipal water, finish boil/do-not-drink/do-not-use runs and confirm the advisory remains at debrief, even if tap service recovers. Unknown stored water must display Unknown; recorded zero must display zero. No assumption about clinical fluid needs is added.
5. Check Dynamic Type, VoiceOver reading order, narrow width and all three locales on these new outcome rows. Finish/reopen/replay must not create practice credit or reset unrelated evidence. Actual practice completion still uses the existing persisted-attempt path, not this read-only summary.

Regenerate the six authored outcome traces without provider calls:

```bash
DRYRUN_WRITE_FIXTURES=1 scripts/swift.sh packages/DryRunCore test --filter RehearsalDebriefEvidenceTests
```

These additions do not resolve the pending incremental native session/director integration, live-model quality gates, human review, or iPhone/RoomPlan/Save verification above.

Final debrief verification: **539 Core tests /96 suites passed**, **68 public/localization tests passed**, native Swift syntax parse passed. Full logs, checksums and machine-readable status: `artifacts/ai/scenario-experience-checkpoint/debrief/`. No provider calls were made. SwiftUI typechecking, Xcode build, iPhone interaction, RoomPlan/Save and human review remain pending.

## Route-detail follow-up

`HomeScenePresentation.routeSteps(_:in:localizer:alternative:)` now formats real computed room sequences against the exact home fingerprint/revision/algorithm that produced them. Outdoor egress ends outside; interior shelter and higher refuge end in the recorded destination. Mismatched/legacy/unavailable results return no route copy rather than relabeling an old path. `routeElementLabel` identifies shared rooms, portals and connectors with floor-disambiguated human labels and localized unknowns; connections are not all called doors.

`RehearsalDebriefOutcomes` now receives `result.input.home`, shows the primary sequence, fire's computed alternative and named shared bottlenecks, and retains the unknown-route-facts caution. Its native argument change is required at the call site in `RehearseViews.swift`. The active spatial scene also restricts `rehearsal.routeRedundancy` to outdoor egress: previously an interior tornado/flood route with no alternative could incorrectly display the fire second-way-out badge. The unchanged general spatial renderer, map and room inspector remain in place.

Additional Mac checks: fire shows its actual evaluated paths and any shared connection; tornado and flood show indoor destination paths without fire's second-exit warning; two identical room names on separate floors remain distinguishable. An unconfigured flood home with no refuge keeps its missing-route result. A synthetic two-story home with explicitly recorded higher destination can show that destination without claiming arrival. Change a home label after a run: the completed run retains the original label; a mismatched route must never acquire new labels. Check EN/ES/VI and VoiceOver for new path copy. Three extra locale keys bring the experience-key total to149; translations remain human-review pending.

Route-detail verification: **14 focused Core tests /2 suites passed**, **68 public/localization tests passed**, and final native Swift syntax parsing passed. Logs: `artifacts/ai/scenario-experience-checkpoint/route-copy/`. The prior full Core run (539/96) predates this additive route helper. These four new route-copy tests cover real fire/tornado paths, the default flood missing-refuge case and explicitly confirmed two-story refuge variant, stale-home fencing, safe labels and translated path endpoints. No provider traffic. SwiftUI/Xcode/device and human review remain pending.


Director follow-up: director29 now scopes final output effect fields to the already accepted preview. See the latest checkpoint in `evaluation-report.md`;205 gateway tests/24 and TypeScript pass, with0 new provider calls. Native still commits only an accepted gateway proposal through the existing durable host receipt path. Do not auto-copy preview commands into rejected proposals or reset a session on provider/schema failure. This is portable reliability work, not evidence that native AI integration or live semantic quality is complete.

## Preflight room choices and condition-effect audit

`RehearsalSetupView` now takes `refugeID` and `startingSpaceIDs` bindings; `RehearseViews.swift` passes its existing `refugeID` and `daytimeStarts`. The same existing start/replay path serializes them into `refuge:` and `start:` variants. Flood's optional higher-refuge picker appears on regional setup, excluding closets; local leaks hide it and never include its saved variant. A compact starting-room disclosure is available before Start for fire, tornado and flood. A selection remains a hypothetical starting assumption: it never updates sleeping-room assignments, confirms refuge suitability, changes geometry or credits practice. Unknown/recorded defaults remain available.

Native checks: select an occupied bedroom versus living room before fire/tornado Start and confirm each person's route uses the selected starting room. Replay retains the assumption. Use a regional flood on a known two-story home, select the water-entry room and higher refuge, then check actual host feasibility; merely choosing a room must not create missing documented suitability or floor relationships. Switch to local leak: refuge control disappears and no `refuge:` variant is submitted. Switch back: retained selection is visible again. Replacing/editing the home still clears stale room selections. Confirm largest Dynamic Type, VoiceOver labels and all locales for the collapsed/expanded starting-room section.

`everyConditionOptionChangesHostStateOrAnEvaluatedDependency` audits11 nondefault condition options across all six hazards using the same Oak/ranch, explicitly changed to municipal water for every row. It compares deduplicated service/resource/requirement/spatial-route states and actual evaluated rule sets; note text, stage/event IDs and duplicate snapshots cannot establish a physical difference. Display-focus options intentionally do not change simulation facts. `fixtures/ai/readiness-condition-effects.json` is an actual synthetic Core export, not a live-model result. There are now151 experience locale keys; review remains pending.

```bash
DRYRUN_WRITE_FIXTURES=1 scripts/swift.sh packages/DryRunCore test --filter RehearsalExperienceDesignTests
```

Preflight verification:11 Core tests/1 suite and68 public/localization tests pass; native Swift syntax parse passes. Audit records10 physical-state differences and one dependency-only night-alert check. Logs/status: `artifacts/ai/scenario-experience-checkpoint/readiness/`. No provider calls; native build/interaction and human review remain pending.


## Integrated offline checkpoint — 2026-10-20

`scripts/verify-ai-portable.sh` finished with **exit0** on the current `main` / `26332ded170f2fea414d581fb50d5de6f4093ab9` dirty worktree after the setup/scene/debrief, route-detail and director29 changes. Results: **Core544/97 suites, Vault39/7, public/localization68, gateway205/24, TypeScript**, plus every evaluator included by that script. This includes all-six common-home branching, practice persistence/retirement/score invariants, replay, bounded fallback and all-six synthetic provider continuity, lost-acknowledgement reconciliation, and recorded research-service rejection/synthetic repair. The final frozen pipeline receipts/scores replayed exactly. Logs and machine-readable status: `artifacts/ai/portable-current-checkpoint/`.

**Linux-tested:** the above portable/domain/protocol scope. **Live-model-tested:** no new calls/searches; the older retained live failures remain failures after state replay. **Synthetic-only:** development households, supplied HTTP/provider turns, branch/persistence fixtures and synthetic repair. **Native-pending:** SwiftUI typechecking/build, incremental AI screen wiring, iPhone layout/interaction, MapKit and RoomPlan/Save/relaunch. **Human-review-pending:** emergency content, translations, clinical/manufacturer boundaries and family usability. Fresh all-six semantic/provider quality and useful end-to-end Groq sourced discovery under injected Gemini429 remain incomplete. The full goal is not complete.

The [scenario handoff](scenario-experience-handoff.md) is the current visual/readiness/debrief integration guide. Preserve its new/untracked files; a tracked-only patch is insufficient. The browser preview was regenerated from actual synthetic fixtures; it remains a portable review artifact, not a native screenshot.
