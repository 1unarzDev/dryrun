# Claude/Mac integration handoff

Baseline: `main` / `436b243276e0f333131a1813b580382971949748`. Linux implementation adds Core files under Models/AI*, Models/HomeConcernReview/IntegratedAIState, Ranking/PreparationTaskCatalog/HouseholdAssessment/PreparednessScorecard, Simulation/IncrementalSession/PlanStressTest, Session/ResourceStrategyRefresh and Spatial/AIPlanDiagram; adds a Swift executable, private Node service, rubric/contracts/fixtures/docs; makes `RunState.input/household/model` mutable for session-local action application; adds an optional encrypted `VaultPayload.integratedAIState`. No native source/PDF/navigation/RoomPlan renderer is changed. Reconcile newer Mac changes before applying shared-file edits. The three untracked owner-supplied reference/audit files are preserved.

## Commands and examples

From the repo root, run `scripts/swift.sh packages/DryRunCore build`, then the commands in services/ai-orchestrator/README.md. On Mac use `swift build --package-path packages/DryRunCore`; the library remains Foundation-only. The executable reads one JSON request per line and flushes one JSON response. Its default scenario path is relative to the repository root.

Initialization:

```json
{"op":"initialize","sample":"oak","scenarioID":"water-outage"}
```

The response contains `session`, `receipt`, eligible incident `profiles`, minimized `householdContext` and `homeScene`. Production native initialization uses a real `RehearsalInput`, a unique session ID, actual source versions and optional geometry. `sample` and the headless executable's fixed reference date are synthetic harness conveniences.

Commit a submitted action using the returned session:

```json
{"op":"commit","session":"<the session object>","commit":{"id":"input-uuid","actor":"user","baseRevision":1,"commands":[{"kind":"useStoredWater","value":"essential"}]}}
```

Here `<the session object>` means the actual JSON object, not a string. Other supported user commands: `allocatePower(target: equipmentID, value: compatibleBackupID|none)`, `moveTo(target: personID, value: actualRoomID)`, `assignHelper(target: personID,value: helperID)`, simulated `contact(target: contactID)`, explicit authored `choose(target: decisionID,value: optionID)` and `unsupported` for a recorded unsupported attempt. No arbitrary natural-language input is silently mapped to a default. Optional text/voice interpretation uses the source/input-bound UserActionIntent path described below.

Build a gateway request from the *committed* receipt, never a speculative user action:

```json
{
 "contractVersion":"dryrun.ai/1","requestID":"request-uuid","role":"director","synthetic":true,
 "context":{
  "binding":{"sessionID":"session-uuid","revision":2,"eventSequence":8,"contextDigest":"host-digest","householdRevision":4,"homeRevision":3},
  "snapshot":{"simMinute":720,"resources":{"res.water.stored":{"amount":3,"unit":"gal"}},"services":{"svc.water.supply":"unavailable"},"unmetRequirements":[],"unknowns":[]},
  "profiles":[{"id":"actual-eligible-profile-id","rule":"rule.external.set","minute":0}],
  "learningObjectives":["Investigate the current continuity dependency"],
  "lastAction":{"id":"input-uuid","kind":"useStoredWater","value":"essential"}
 }
}
```

The request above illustrates shapes; use actual IDs/fields from the receipt and eligible pack. The complete executable examples are the retained `fixtures/ai/adaptive-trace-{all,essential}.json` and smoke.ts. Public endpoints must never receive these private contexts.

`needs_client_tools` returns an opaque token, expiry, binding and `{id,name,arguments,cloudReturnPolicy}`. For `evaluateCandidateAction`, execute exactly one command or its requested batch through `SessionToolRequest`/`session.preview`, with the same base revision. Spatial batches must include the advance that applies the incident. Send `/v1/continue` with token, exact binding/callID and the minimized `{binding,snapshot,contextDigest,preview?}` result; preview contains only typed scene/route IDs and director state. Do not commit the preview. Never forward a MapKit result as this payload. Final `completed.proposal` is a versioned envelope containing ID/requestID, actor, baseRevision, embedded binding, commands, purpose, evidenceIDs/assumptionIDs, requested nextBoundary and presentationIntent. A `needs_user_action` response makes no provider call; keep the existing scene awaiting submitted input. Decode `DirectorProposal`, call `commit(to:binding:library:persist:)`, atomically save the candidate, then render **the returned receipt**. Core validates actual feasibility even when the JSON schema passes.

## Native state and screen placement

- `AppModel.updateHousehold` already saves before publication and invalidates derived results. Keep that order. Add `IntegratedAIState` to `PrivateSnapshot` and preserve `VaultPayload.integratedAIState` during **every** save/load; add encrypted relaunch tests. Use `confirmInventory` for one review batch, with household and inventory revisions. Do not add the legacy water projection to the same ledger again. Existing manual totals need explicit reconciliation into inventory rather than a second independent quantity store.
- Prepare: keep the short slate. `PreparationTaskCatalog` projects current `BaselinePreparedness` recommendations with existing action+subject IDs and `PreparationEditTarget` ownership. Gemini selects/personalizes within it; Core retains predicates/editors and critical continuity constraints. Inventory extraction produces proposals, not ownership or usable quantities. Show quantity/location/condition uncertainty in one concise batch review. Reuse existing description intake/on-device fallback.
- Plan: refresh resource strategy only for normalized gap, transport/budget and region changes. Debounce input; use `ResourceStrategyRefresh` generation tickets. Geocode the saved address and resolve jurisdiction locally; let users correct ambiguity. Keep native search origin/fingerprint separate. Run bounded category searches using existing MapKit adapters; rank by actual returned fields and travel constraints, show a few markers with a local task-gap reason and unverified stock/activation/access. Retain useful results while refresh fails. No automatic calling, buying or navigation. Outside source-pack coverage uses ordinary category candidates with honest uncertainty.
- Match independent official records to map places only after stable identity or complete name/address/location checks. Similar names/nearest matches cannot transfer capabilities. The seven reported Tarrant records retain their checkout `needsReview` status. Reverify actual records; do not claim national coverage. Do not insert Google grounding/Places data in durable resources or Apple map/PDF content.
- Home: use minimized graph plus `AIPlanDiagram` for annotated floor context; keep native home renderer intact. Offer selected keyframes or a short post-scan photo pass. RoomPlan is not assumed to persist a photo tour. Capture actual camera pose/intrinsics/depth and submitted transforms if projection is implemented. Redact, strip metadata, preview selected photos and offer deletion/manual review. Digest exact submitted bytes. Normalized boxes are `[ymin,xmin,ymax,xmax]` in that image. Without aligned calibration/depth, findings stay in image space. Redacted/unseen regions are never negative evidence.
- Concern review: call `ConcernLedger.shouldOffer` to suppress repeated evidence, then Confirm / Not an issue / Not sure. The explicitly confirmed issue can create a linked task/scenario fact; uncertain exercise use needs separate permission. A new photo/digest may justify another review. No “all safe” conclusion, automatic emergency alert or direct graph exit creation.
- Rehearse: migrate from full-run cursor revelation to incremental receipts. Preserve scene-first key moments and existing renderer symbols. Scene hazard fields, exclusions, resources and route overlays must come from the same receipt. Wire only real submitted intents to user commands. The director can schedule eligible reviewed profile templates and pacing commands; available templates are **not already scheduled events**. Show source revisions, and on edits cancel/fork or clearly retain the original snapshot. Never silently mix revisions. Simulated time stays fixed during network delay/backgrounding.
- Plan/debrief: show the most useful few executable stress findings, exact assumptions and shared dependencies. Controlled retest reuses `StressTestFinding.schedule`; a newly directed exercise is not a controlled comparison. Hypothetical improvements never complete real tasks.
- Score: `HouseholdAssessment` → accepted predicates → `IntegratedAIState.compileScorecard`. Display draft rubric version, provisional overall/preparation/practice, coverage, cap reasons and three next improvements. Unknown is not failure or N/A. Council disagreements are concise review proposals, never votes turning facts true. The latest eligible practice attempt governs; resume it after interruption. Only pre-feedback committed actions matched to reviewed competency anchors earn practice. Guided exercises do not earn score by count/difficulty. Keep text/manual/VoiceOver alternatives equivalent; no reaction-speed score.

## Authorization, consent and lifecycle

The current server is synthetic-only and loopback. Production intentionally fails closed. Implement the App Attest-compatible handshake: server one-time nonce → native key ID/attestation/assertion over nonce+installation+scope → server verification of Apple chain/app identity/environment/nonce/counter → short-lived scoped installation session. Bind refresh/continuation to installation, operation, revision, tool/call ID and expiry. Store installation keys/tokens in Keychain, never the Gemini key. A real production verifier is an explicit remaining integration dependency; fixture tokens are never a substitute.

Before private cloud use, verify billing/data configuration and family-audience terms fit. Native opt-in must name Gemini/provider and categories shared; selected room photos require separate understandable review. Revocation cancels active work by token/requestID and stops new jobs; manual checklists, on-device intake, native search and saved plans remain available. Backgrounding can pause/cancel, persist the same session, and resume without resource drain or incident replay. Delete-all must purge new encrypted state and selected temporary images; provider retention cannot be promised zero.

Existing PDF/card export must use only accepted plan content and intentional privacy selection. Keep current native renderer and permitted attribution/snapshot behavior. Never export raw council output, model deliberations, room photos or Google-grounded answers automatically. EN/ES/VI safety wording remains human-review-pending; stable IDs stay untranslated. Verify VoiceOver order, Dynamic Type, keyboard/voice alternatives, unknown/provisional wording and numerical formatting.

## Exact iPhone checks still required

1. Compile both packages and Xcode app against the current Mac branch; preserve newer PDF, compact navigation, corrected mesh winding and room-type confirmation behavior.
2. Start layoutless and scanned/manual homes; confirm three tasks and inventory quantities once; failed vault write leaves facts/UI unchanged; relaunch retains new sidecar and existing card choices.
3. Save an ambiguous address, correct jurisdiction, change only a contact note (no strategy refresh), change a water gap (one debounced refresh), revoke opt-in during search (late response discarded, old useful markers retained).
4. Test no car, rural distance, no search results, outside source pack, unknown/closed service and similar-name official matches. Verify attribution, calling/navigation remains user-initiated, route estimates never imply flood clearance or tornado shelter suitability.
5. Run the recorded all/essential water traces on-device: at minute 720 balances 1 versus 3 gallons; all-use depletion interrupts at minute 900, essential at 1800. Scene/time/resource/route states agree with receipts. Background during Gemini call, duplicate continuation, edit home, timeout and offline fallback must preserve committed log and balances.
6. Fire/tornado/flood scenes: affected start room, missing stair, wheelchair, narrow/blocked portal, unconfirmed exterior window and no supported shelter all stay explicit; no invented route. Temperature is only scenario assumptions, never clinically safe exposure advice.
7. Capture rotated/cropped/redacted photos and no-depth photos; overlays refer to submitted image, no unsupported projection. Confirm/dismiss/uncertain review is reversible and deduplicated; deleting images removes temporary bytes. Poor views and detection absence never certify safety.
8. Check optional practice attempt interruption/restart, unsafe pre-feedback answer, accessible text equivalent and newer incomplete attempt. Unknown competencies remain denominator; old best score cannot hide current errors.
9. Compare a confirmed inventory improvement under the identical stress schedule and rubric version. Real task completion happens only through saved facts. PDF preview/export remains selected-content, attributed, readable and smaller-file behavior is preserved.
10. Obtain relevant preparedness, accessibility, manufacturer/clinical-boundary and family usability reviews using human-review-protocol.md; record actual reviewers and outcomes before claiming endorsement or validation.

## Additional portable entry points

`session.executeTool(SessionToolRequest(kind: .inspectScene, baseRevision: session.revision), library: library)` returns the authoritative receipt plus scene. `.queryRoutes` and `.evaluateResources` return the receipt's route/resource values; `.inspectDependencies` adds shared power/helper/route/contact/transport evidence; `.evaluateCandidateAction` previews one director command; `.runCounterfactual` executes supplied profile IDs with an optional `Intervention` under the identical external schedule. These are local read-only tools. The gateway director can request all six tools; see director-tools.md for strict observations and scope; do not serialize the full local tool response blindly into its minimized continuation.

Practice writes use the atomic capture path in [practice-capture.md](practice-capture.md), not recordPracticeAnswer (which now rejects all caller-created answers). Current anchors cover outage water policy, actual usable contact/channel, computed route adaptation and essential-device allocation. Unsupported combinations remain unassessed; native must use the same pre-feedback transaction and obtain human review before expanding anchors.

`FeatureRunner.council` returns raw independent `reviews`, raw `adjudication`, host-predicate `accepted`, and `disagreements`. Display only concise evidence-linked disagreements for review. Raw council false passes were observed in synthetic evaluation. Neither raw output nor majority agreement can grant points. The accepted list is a transport reconciliation, while Swift `ScoreCompiler` remains the numerical authority.

For an actual home-specific director request, optional `context.household` and `context.homeScene` accept the same strict minimized snapshots as feature roles. Do not send names/contact values, address/map payloads or care notes. The connected pipeline demonstrates these fields. `SessionToolRequest.routeRequest` accepts Core `RouteRequest`, including interior destination purpose; unsupported geometry returns Core no-route evidence. `.queryRoutes` without it returns current receipt routes.

Retained runnable examples: [connected household pipeline](../../fixtures/ai/integrated-pipeline.json), [all-use adaptive trace](../../fixtures/ai/adaptive-trace-all.json), [essential-only trace](../../fixtures/ai/adaptive-trace-essential.json), [controlled stress comparison](../../fixtures/ai/controlled-stress.json) and [actual evaluation report](evaluation-report.md). `scripts/pipeline.ts` exercises the exact request/response shapes, including local preview suspension and validated commit.

Persist executable stress findings as derived results with their source binding, then pass them to `HouseholdAssessment.assess(..., stressFindings: findings, at: date)`. Only the versioned shared-route envelope currently affects a preparation predicate; stale source bindings are ignored. Present other executable failures as hypothetical findings without invented score deductions. For both household and inventory confirmation, pass the same captured `date` into the transaction so revision timestamps and derived state are stable.

Fresh-session owner prompt: [CODEX_WIRED_IPHONE_HANDOFF_PROMPT.txt](CODEX_WIRED_IPHONE_HANDOFF_PROMPT.txt). It requires independent reconciliation and wired-iPhone implementation/testing; portable results are evidence, not native acceptance.

`InventoryLedger.gap(for: RecordedSupplyRequirement, at:)` supports explicit reviewed household instructions using count/day/Wh or converted water units. Requirements must be consolidated by physical purpose; do not sum overlapping requirement gaps or independently promise a shared battery to multiple loads.

Follow-up portable tool integration: [director-tools.md](director-tools.md) specifies all six gateway read-only functions and minimized return envelopes. Implement its whitelist in the native continuation handler instead of assuming every request has `arguments.command`. `smoke.ts` and `pipeline.ts` now use the shared executable adapter. Only evaluateCandidateAction returns a preview; other tools return the unchanged session envelope plus a matching typed observation. Counterfactual baseline outcomes stay hypothetical. Test scene/route/dependency requests on the phone, cancellation between multiple tools, and source edits while a continuation is pending.

Follow-up exercise inventory: [exercise-inventory.md](exercise-inventory.md) specifies optional immutable SessionInventorySeed, derived receipt inventory, whole-container take/move/transfer actions, minute expiry boundaries and stress source binding. Native new-session creation must supply the confirmed ledger/reference date; resumed source snapshots must remain frozen. Test inaccessible storage vs supplies moved before an incident, unknown locations, failed routes, carried items, quantity conservation and duplicate/background replay. These exercise effects must never write back to household supplies.

Policy/action integration: [director-policy-and-actions.md](director-policy-and-actions.md) specifies the new-session factory, frozen policy, descriptors/current stage/pending context, startIncident/advanceIncident, typed command fields, batch previews with minimized scene consequences, waitUntil outcomes and user closeDoor posture. Use the factory for new exercises; preserve legacy source snapshots on resume. Wire each action into the existing scene rather than exposing commands or adding tabs. The live synthetic spatial trace and failed attempts are separate fixtures; verify on the actual phone.

Practice capture now uses [host-owned transactions](practice-capture.md). Use beginPractice with sessionID/library, submitPracticeAction, revealPracticeFeedback and IntegratedAIState.compileScorecard. The legacy recordPracticeAnswer rejects caller-supplied credit/chronology. Preserve optional source/observations fields, capture before UI feedback, and verify rollback/resume/coaching/retest on the phone. Imported provenance-free answers are unverified history, not eligible points.

Optional another-action text/voice now has [source/input-bound intent contracts](user-action-intents.md), synthetic-only POST /v1/intents, Swift ActionSubmission/UserActionIntent.commit, and NDJSON interpretCommit. Use these before the next director turn. Clarify ambiguity, retain unsupported attempts, discard stale/cancelled responses, and never show interpretation as a completed action. The live synthetic fixture demonstrates interpretation → committed action → Gemini tools → validated director commit. Wire native speech/input/consent and verify on the phone.

Helper commits now produce [current computed reach](helper-reach.md) in optional SessionReceipt.assistance; dependency inspection reflects the exercised assignment. Show reach independently from unknown shared capacity, sync after reassign/move/hazard changes, and verify on the phone. Never promote simulated helpers/positions to household records.
