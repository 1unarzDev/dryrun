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
