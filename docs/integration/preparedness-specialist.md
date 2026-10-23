# Preparedness and assessment specialist

Owner: `preparedness_assessment`; base `26332de`, shared working checkout. Requirements SCORE-01, PREP-01 and STRESS-01; focused implementation addresses SCORE-01. Read integration reference including §§2A and 12–14 and source/ledger/work-order/shared scenario contract. No protected app output or native sessions inspected.

## Purpose and contract

A family returning for a short water or equipment continuity check should retain demonstrated route and communication competencies. A new independently demonstrated mistake must replace the earlier result for that competency. Starting or receiving coaching during another check must not erase unrelated independent evidence. Benefit appears in the existing score refresh, with no added taps or navigation.

Inputs: eligible practice attempts already reconstructed from committed source traces by `eligiblePracticeAttempts`, fixed rubric and four competency IDs. Unknown or unsupported responses remain unassessed. `PracticeCapture`/`PracticePhases` continue to validate immutable sources, chronology, feedback and atomic persistence. No source validation, numeric weight, preparation criterion, inventory fact or route authority changed.

Simpler option considered: retain the latest whole attempt. Source inspection proves it discards all earlier route/communication evidence when the latest check covers only continuity. Per-competency replacement uses the existing records and fixed four-by-25 budget, without a new score store/schema. Orchestrator approved this contract and the one existing authored test update.

## Changes

- `packages/DryRunCore/Sources/DryRunCore/Ranking/PreparednessScorecard.swift`: validate every attempt, visit in sequence, replace only independently assessed eligible competencies; ignore coached, feedback-exposed and archived answers for replacement. New independent failures replace prior passes. Unanswered competencies retain prior evidence.
- `packages/DryRunCore/Tests/DryRunCoreTests/PracticeEvidencePreservationTests.swift`: short continuity preservation; sequence-order independence; contrary evidence; coached/unanswered/archived/feedback-exposed attempts; repeated checks; duplicate identity/sequence; invalid historical entries.
- `packages/DryRunCore/Tests/DryRunCoreTests/IntegratedAITests.swift`: update legacy assertion which encoded destructive whole-attempt replacement. Prior full pass followed by one independent initial-response failure now yields 75 with four assessed competencies, instead of zero with one.

Single evaluator-version scorecard field retains its existing latest-attempt provenance behavior. Complete per-answer version provenance remains in source-bound attempt records. No prompt version changed; no inference experiment claimed.

## Acceptance and verification

Predetermined criteria: continuity-only success after three other successes yields 100/4; replacing communication success with independent failure changes only 25 points; ineligible or empty later attempts leave prior 75/4 intact; repeated success never increases the fixed budget; duplicate attempt IDs/sequences and invalid historical answers reject.

Exact test command: `python3 scripts/review/firewall.py capture --timeout 600 -- swift test --package-path packages/DryRunCore --filter 'PracticeEvidencePreservationTests|PracticePhaseTests|PracticeCaptureTests|PracticeNonDeviceTests|IntegratedAITests'`.

Receipt `run-2bb37efe916e46998cf8d02835a407f7`: failed, exit 1, 6278 ms. Protected logs untouched; dedicated reviewer diagnostics requested from orchestrator. No passed-test or build claim yet.

Escalated retry for known Swift cache sandbox requirement: same command, receipt `run-0cb4b366e8384e1a9d2067a7126d572a`, failed exit 1, 2392 ms. Logs remain protected; released diagnosis required before concluding cause.

No native access requested or used. Physical iPhone 16 Pro verification remains with the serial orchestrator/reviewer queue: complete practice, observe all score surfaces, reopen, confirm completed check retirement and targeted next practice. Source work does not establish iPhone behavior. Inventory/prioritization/stress-test breadth remains unverified by this narrow fix. Existing immutable-source checks were retained; automatic material-home-revision evidence invalidation is not established by this report.

Next owner: orchestrator obtains released run diagnostics, then delegates narrow fixes/retest or integrates this patch and executes physical score/retirement checks through output reviewer. No protected response copied into code, tests or report.

---

## Lead pass 2026-10-21 — branch `lead/preparedness-assessment` (base `cdb4098`)

Claude-led Mac workflow, preparedness and assessment lead (PREP-01, SCORE-01, STRESS-01 inventory side). No protected output, provider response, AI-bearing capture or replay recording was opened. No phone or simulator launch. Core-only test runs below involve deterministic suites only; the full Core run went through `scripts/review/firewall.py capture`.

Reconciled first: milestone 3 smart shopping list (`Shopping/ShoppingList.swift`, `content/prices/tarrant-v1.json`, `Next/ShoppingListView.swift`) already exists on this branch with per-household quantities, dated sourced price ranges, Budget/Complete kits ordered medical → life safety → basics and benefit per dollar, and check-off into confirmed inventory. Family-facing rubric-version text is already absent: `ScorecardCard` no longer renders `score.version` (key kept in locale files, unused). Urgent task rows already tint the effort pill and scenario icons with the urgent colour and keep the warning icon in a fixed trailing column beside the chevron (`NextStepRow`). Those were extended, not replaced.

### Feature purpose 1 — material-fact Prepare actions (PREP-01)

- Household and situation: any family whose recorded supplies, medication storage, sleeping floor or budget should change what "do next" means.
- Preparation improved: the baseline Prepare action now follows the recorded state. Recorded absent smoke/CO alarm, extinguisher, first-aid kit, flashlight or batteries → "Install/Get …" (effort low, budget and renter notes when recorded). Unknown → free check (unchanged wording). Owned without location → find it (existing `prep.location.why`). Owned extinguisher with a location but no check/family awareness → "Check the fire extinguisher" (maintenance), never a purchase. Recorded cold-storage instructions without a confirmed plan → "Plan outage storage for {device}" (continuity) instead of "record instructions". A person with a stair/mobility need whose recorded sleeping room is above the lowest floor → new life-safety `prep.stairPlan` (critical tier with no helper, unknown tier with a helper); multi-story home with no known sleeping room → one targeted question. Tight budget → within a tier, free steps before purchases after any medical dependency; tiers never cross.
- Known inputs / consequential unknowns: `PreparationFact.available/location/checkedAt/familyAware`, `Supplies`, `PoweredEquipment.storageInstructions/storagePlanConfirmed`, `Person.needs/sleepingSpaceID/helperPersonID`, `HomeModel.floors[].level`, `Housing.floorCount/tenancy`, `Supplies.limitedBudget`. Unknown stays unknown; never inferred from home type.
- Why this screen: same Prepare rows and existing focused editors. Stair plan opens the existing checklist editor (`stairPlan.person.<id>`), with the person named in the header.
- Next step / taps: unchanged, row → focused editor → Save.
- Simpler option considered: only changing the why text. Rejected because effort, tier, sequencing and the shopping list must agree with the same fact, or the row contradicts the buy list.
- Score effect: none added. Stair plan has no rubric predicate; tests prove the number and coverage are unchanged.

### Feature purpose 2 — shopping list honours ownership; check-off records it

- Owned items are never suggested as purchases (extinguisher, radio, first-aid kit via `BaselinePreparedness.recordedSupplyAvailability`); flashlights are sized one per person minus the recorded count.
- Checking off an extinguisher or radio now calls Core `IntegratedAIState.recordPurchase`, which records ownership only (no location, check or awareness) and the inventory item in one revision-checked save. Prepare then moves to "find it". `AppModel.markBought` is a three-line call-site change (orchestrator-owned file; flagged in the commit).
- Simpler option: leave the list and Prepare diverging. Rejected; the family would buy, check off, and still be told to "Get a fire extinguisher".

### Feature purpose 3 — fixed-rubric invariants (SCORE-01)

New `ScoreRubricInvariantTests` (golden households through the app's own assess → compile path): bounded/capped/provisional/repeatable for every sample; unknown is never confirmed and confirmed absence caps at the known-gap level; a critical known gap stays capped under added easy points; duplicate evidence (same container re-confirmed, same physical item under a second record, duplicate criterion) adds no credit or is refused; renaming people/devices/contacts, rewording locations/notes and changing language leave every number identical; a water improvement changes only the water criterion; a shopping check-off cannot enlarge the score budget. Short continuity check preserving route/communication evidence remains covered by `PracticeEvidencePreservationTests`.

### Files

- Core: `Ranking/BaselinePreparedness.swift`, `Ranking/RecommendationRanker.swift`, `Ranking/NextSteps.swift`, `Ranking/PreparationEditTarget.swift`, `Ranking/PreparationPresentation.swift`, `Shopping/ShoppingList.swift`.
- Tests: new `MaterialFactPreparationTests.swift`, `ScoreRubricInvariantTests.swift`; updated `RankingTests` (budget-aware order check), `ShoppingListTests` (flashlight shortfall).
- Locales: 18 keys in en/es/vi `common.json`; 36 baseline hashes for exactly those keys.
- Native: `Next/FocusedHouseholdEditor.swift` (stair plan labels/header), `App/AppModel.swift` (`markBought` → `recordPurchase`).

### Limits and follow-ups

- Prepare request content changes for affected sample families (task why/title keys, new stair task when applicable), so the Beacon preparation replay binding for those families will no longer match: re-record replays (`scripts/mac/pull-beacon-replays.sh`) after integration before filming.
- `prep.stairPlan` is not in `PreparationTaskCatalog` mapping (no rubric criterion), so Beacon cannot reorder it; native list shows it.
- Rehearsal-side use of the stair fact is the scenario/house pair's scope.
- Device checks requested in the lead return; nothing here is device-verified.

### Evidence (this pass)

- deterministic-tested: targeted suites run directly (no AI output involved): `swift test --filter 'MaterialFactPreparationTests|ScoreRubricInvariantTests|RankingTests|ShoppingListTests|HouseholdAssessmentTests|PreparationInventoryTests|PreparationEditTargetTests|OutageCardAndNextStepsTests|BaselineCoverageTests'` — 61 Swift Testing tests in 10 suites plus 5 XCTest cases passed.
- deterministic-tested: full Core `python3 scripts/review/firewall.py capture --timeout 1800 -- swift test --package-path packages/DryRunCore`, receipt `run-679963cc1d234f068810d2a7ad1886ec`, succeeded, exit 0 (receipt only; counts not viewed).
- Mac-build: `xcodegen generate && xcodebuild build -project DryRun.xcodeproj -scheme DryRun -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED. Not device-verified.
