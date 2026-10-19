# One provisional check, four frozen situations

Reference §12 asks for four equally weighted competencies in a short optional Practice check, graded before feedback and separate from adaptive training difficulty. The previous single-session capture could execute each individual anchor, but its source scenario could not support all four: initial response was water-outage-specific, adaptation egress-specific, and continuity power-loss-specific. The new `dryrun.practice-phases/1` plan fixes that executable coverage gap by freezing four independent situations under one attempt. It adds no new grading anchors or difficulty multiplier.

`practice-check-a/1` orders initial response, adaptation, communication, continuity. `practice-check-b/1` reverses the competency order. Their situation sources are water outage, home fire, water outage and freeze/power loss respectively. All use the same recorded household, home and inventory. The source scenes and incident prefixes must be prepared before beginning. The existing `dryrun.practice-anchors/2` grader remains authoritative; unsupported evidence stays unassessed in the fixed four-competency denominator. The continuity anchor currently covers documented essential powered equipment. Households without that relevant dependency or sufficient specifications remain unassessed for continuity; do not invent equipment or purchase requirements to earn points. The separate /2 plan below supplies a non-device continuity anchor; /1 remains frozen on its original evaluator. These draft plans remain **provisional**: the order variants have not demonstrated human-reviewed comparability or broad household suitability.

## Native integration

Create four distinct `SimulationSession` sources using the existing supported scenarios and the household's actual facts/home. Do not substitute the synthetic test layout for missing geometry. Each source must have no user commits, concern seed, preset choices or hypothetical intervention. Prepare the source's incident state through the existing host: water unavailable for initial response; a previously verified egress option now blocked for adaptation; the recorded contact channel for communication; power loss for continuity. Missing supported geometry/specifications/channel may make the answer unassessed; do not add facts or equipment to make a check pass.

Freeze all sources and the attempt in one private save before presenting any question:

```swift
try state.beginPracticeCheck(
    id: attemptID,
    variantID: "practice-check-a/1",
    sessionIDs: [waterSessionID, alternateRouteSessionID, contactSessionID, powerSessionID],
    library: library,
    persist: savePrivateState
)
```

Use `activePracticeCheckSession(attemptID:library:)` to obtain the next frozen source; it validates the whole plan and returns nil after completion. Use the existing `submitPracticeAction` transaction with one real submitted command, then `revealPracticeFeedback`, then `compileScorecard`. Do not pass credit or a before-feedback flag from the UI. The active source must be the phase source, not whichever session is currently selected elsewhere in Rehearse. The headless host checks that selection too.

One check retains `PracticeAttempt.source` as the first source for compatibility and adds optional `phaseSources`, ordered by the versioned variant. Every observation retains its committed action/revision/receipt digest and first anchored credit. All four sources are bound before any question. Until completion, no extra user or director commit may enter any source; guided adaptive training is a separate session. Source/phase substitution, uncaptured actions, reordered answers, duplicate sessions/actions, altered receipts/credit or a hypothetical concern seed fail revalidation. After all four observations, further training can continue without regrading the original answers.

Reopening begin resumes the latest incomplete attempt regardless of a newly requested variant or session list. Wrong and unsupported first responses persist. A newer incomplete attempt becomes the current practice assessment, with remaining competencies unknown; the older completed attempt remains history. A completed check's sessions cannot be reused for a new check. Preserve the original source snapshots across real household edits, or explicitly start a new check; never silently refresh one frozen situation.

Keep one optional check within existing Rehearse. Present the four situations as independent hypotheticals, not one combined fire/water/power emergency. Keep feedback concise, transitions clear, and manual/text, VoiceOver, translation and additional reading time available without coaching penalties. No reaction-speed, physical-ability, equipment-cost or LiDAR credit is introduced. Do not display a practice 100 as a safety claim or overall preparedness 100.

The local-only projection `{variantID, phaseSources}` has `practicePhasePlan-v1.schema.json`; it does not go to Gemini. Existing /0 single-session attempts and source/evaluator migrations remain supported unchanged. New /1 variants require all four source records; stripping that metadata cannot fall back to the single-session path. Keep the full state in the existing encrypted Vault sidecar.

## Runnable evidence

Build Core and run:

```
pnpm --dir services/ai-orchestrator exec tsx scripts/practice-phases-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/practice-phases-replay.ts
```

`fixtures/ai/practice-phases.json` contains synthetic sources, the frozen plan, action/receipt/feedback checkpoints and final persisted states. Four independently correct committed answers produce practice 100 with 4/4 assessed. A wrong first response followed by three correct responses produces 75 with 4/4 assessed; interruption cannot erase the zero. The scorer's 10% maximum practice contribution, caps, denominator and provisional label are unchanged. No new Gemini calls occur.

Core tests cover four-competency execution, JSON restoration, latest-incomplete selection, first-answer preservation, save rollback, source/credit tampering, unknown anchors, chronology and stimulus changes. A Vault test encrypts the completed wrong-first attempt, restores all four sources/answers and verifies no attempt IDs/variant/canary appear as plaintext on disk. Linux uses swift-crypto; Apple Keychain, CryptoKit and actual app lifecycle remain device checks.

## Pending checks

The Mac must audit startup/persistence timing before any prompt or feedback, resume at each boundary, wrong source selection, a real household/home edit mid-check, cancellation/backgrounding and all input/accessibility paths on the wired iPhone. Human review must assess short-check wording, fairness, unsupported situations and variant comparability. These are synthetic host/workflow proofs, not human-validated scoring or native usability acceptance.

## Non-device plan /2

`practice-check-a/2` and `practice-check-b/2` retain the four-source capture transaction and pin `dryrun.practice-anchors/3`. The order is unchanged, but initial response uses the authored home-fire first decision, adaptation uses home-fire, and communication and continuity use separate water-outage sources. Freeze a committed fire cue before the initial question and computed unavailable water before continuity. Read `content/ai/practice-check-phases-v2.json` and `practice-anchors-v3.json` before constructing sources. Choose an appropriate supported context; do not silently replace an interrupted attempt or invent stock, routes, contacts or equipment.

The fire anchor grades the decision to prioritize escape, not physical egress success. The continuity anchor requires positive known recorded water and an actual host-demonstrated conservation consequence. Two isolated host projections compare essential/all use under the same pending schedule over at most 60 simulated minutes or an earlier mandatory boundary. Essential earns one and unrestricted use zero only when the host demonstrates greater remaining stock at equal time or later depletion. Unknown/zero stock, insufficient horizon or no demonstrable difference remains unassessed. This existing educational doubled-use assumption is not medical rationing advice. Actual stock adequacy contributes separately to preparation criteria; quantities do not add practice points.

Use the same API example with variant `practice-check-a/2` and source IDs ordered `[fireDecisionID, alternateRouteID, contactID, waterContinuityID]`. All /1 source/first-answer/feedback/persistence restrictions apply. /0 sources without evaluatorVersion retain anchors/1; explicit /2 evaluators retain their old semantics. Never relabel a historical source. The /1 phase plan always pins anchors/2, independently of the latest default.

Run `scripts/practice-nondevice-eval.ts` and `scripts/practice-nondevice-replay.ts` through tsx after building Core. `fixtures/ai/practice-nondevice.json` records no powered devices/batteries, correct practice100 versus unsafe-first75, 4/4 assessed, resume without reroll, and exact source/action/receipt/score replay. Its isolated resource proof preserves the original5gal source at minute0 while projecting essential4.96gal versus all4.92gal at minute60. Core tests cover unknown/zero supplies, later depletion, legacy grading, no physical-ability scoring, budget invariance and unchanged confirmed inventory consumption. No model calls occur.

This supported path does not establish universal household coverage or comparable variants. Missing verified geometry, usable contact/channel or known water still leaves the corresponding competency unassessed. Human safety/language/fairness review and all wired-phone integration checks remain pending.
