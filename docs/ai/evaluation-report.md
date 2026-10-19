# Integrated Gemini evaluation — 2026-10-19

Portable implementation on Linux, based on `main` at `436b243276e0f333131a1813b580382971949748`. No iOS source was changed. The root `DryRun_AI_Implementation_Reference.md` is the supplied specification; no `.txt` copy exists in this checkout. See [implementation map](implementation-map.md) for the verified original flows and [Mac handoff](mac-integration-handoff.md) for exact integration points.

This is an implemented, synthetic-tested integration package, **not a production release or a completed native experience**. Production authorization, device integration, real-photo quality and human validation remain gates.

## Passed on Linux

| Check | Actual result |
|---|---|
| Existing baseline Core | 333 tests passed before changes |
| Final Core | 393 tests / 71 suites passed, Swift 6.2 Docker |
| Vault | 36 tests / 7 suites passed, including legacy/additive encrypted sidecar roundtrip |
| Private gateway | 41 tests / 6 files passed; TypeScript check passed |
| Unchanged public API | 68 tests passed; TypeScript check passed |
| Frozen rubric cases | 60/60 predicate/arithmetic cases passed: 40 development, 20 locked holdout |
| Recorded live-session replay | Both all-use and essential-only logs recomputed their original digest/snapshot offline |
| Controlled stress comparison | Same external well-failure schedule: water depletion 1800 → 4320 minutes after hypothetical storage intervention; original profile unchanged |
| Startup configuration | Actual server subprocesses rejected missing credentials and production authorization misconfiguration |
| Local tool seam | Scene, routes, resources and dependency inspection ran through the actual Swift host |

New regression coverage includes atomic save rollback, stale/duplicate commits, actor permissions, past-time scheduling, mandatory depletion, simultaneous phone/water depletion, route-start updates after movement, inventory unit conversion/dedup/unknown/inaccessible quantities, real-fact privacy minimization, concern review/dedup, resource cancellation/revocation, latest incomplete practice, host-anchored credit, rubric mutations/caps and Swift/TypeScript recorded contracts. Existing suites cover shared battery allocation, spatial variations, temperatures and all six hazard families. These passing suites do not establish physical safety or exhaustive state-space coverage.

## Live model tested — synthetic only

Official `@google/genai` 2.30.0, Interactions with `store:false`, routine model `gemini-3.1-flash-lite`, prompt/schema family v1 and draft `dryrun-rubric/0.1-draft`. SDK opaque steps/signatures stay only in bounded gateway memory. Structured outputs undergo full local validation after provider schema-subset validation.

**Adaptive rehearsal:** `adaptive-trace-all.json` and `adaptive-trace-essential.json` each contain four real model calls and two validated director turns. An actual committed water policy produces one versus three gallons at minute 720, with computed depletion at minute 900 versus 1800. Subsequent Gemini tool forecasts/proposals differ. The director chooses pacing/incidents from reviewed profiles; this is not a larger prewritten narration. Replay makes no model call. Host receipts override model prose; some recorded prose overstates an intended checkpoint when the host stops early at depletion. Do not present that prose as a computed state assertion.

**Connected pipeline:** two distinct fixtures completed inventory confirmation → projected simulation inputs → gaps → canonical personalized tasks → task-linked resource searches → executed challenges → four-pass council → Swift score compilation. The final expanded retained run used 20 calls and includes an actual user-action → Gemini preview/tool continuation → validated director commit for each household. Both exact retained source snapshots and committed commands subsequently reproduced the live receipt digest and score offline (`pipeline-replay.ts`). The infant/dog/device fixture prioritizes medical backup and water; the two-adult fixture omits infant/pet/device work. Confirmed five versus two gallons produced deterministic gaps of 26.50 versus 15.14 liters. Draft scores are 22.5 and 16.5625 with cap 59, not claims of household safety. MapKit search/results remain native-pending; these are meaningful bounded search strategies, not fabricated live listings.

**Council:** three development cases × three repeats = nine assessments, 36 calls. Policy-authored references, not qualified human adjudications. Baseline deterministic predicate agreement is 100% by construction. Raw one-reviewer agreement averaged 65.08%; raw council agreement 68.25%. Per-household means:

| Case | One reviewer | Council | Raw reviewer critical false passes across three runs | Raw council critical false passes |
|---|---:|---:|---:|---:|
| household-01 | 64.29% | 64.29% | 0 | 2 |
| household-02 | 92.86% | 90.48% | 0 | 0 |
| household-03 | 38.10% | 50.00% | 3 | 9 |

Mean full council latency was 20.89 seconds per repeat. The council added calls and cost and **did not improve critical-gap detection**. Three cases are too few for a general quality claim; repeats are not nine independent households. `reconcileCouncil` now exposes unsupported status changes as disagreements and compiles accepted statuses from frozen host predicates. Offline reconciliation of all nine retained live results yields **zero accepted critical false passes**, without additional model calls. This guard cannot discover missing real-world evidence. Raw recommendations never grant points or overwrite facts. Live council holdout, broad bias/language/evidence-order/identity tests and independent human references remain unrun.

**Vision:** six explicitly synthetic diagrams, with hard negatives, partial views, poor light and adversarial text. After enforcing actual hazard IDs and approved guidance-source IDs, Flash Lite matched intended concern categories/abstentions in **3/6** cases. It raised false concerns for clear, rug-lookalike and poor-light fixtures. Earlier 5/6 category-only results did not check valid scenario/source associations and are not the current result. A subsequent six-call comparison with `gemini-3.8-flash` matched **5/6** on the same cases, still raising a false concern for the rug lookalike. The synthetic development server now configures that stronger model for HomeObserver; this small comparison is development evidence, not a held-out vision benchmark. No real room, RoomPlan capture, localization IoU, calibration projection or consented family photo evaluation occurred. A box remains in submitted-image coordinates; review does not create a verified exit or a measured clearance.

**Inventory intake:** two live typed synthetic notes matched 2/2: one labeled two-liter bottle and one container with unreadable/unknown quantity. Observation evidence IDs are constrained to supplied intake/image IDs. Neither observation is automatically confirmed. Image-label inventory recognition has not been evaluated.

Successful retained Flash Lite calls have usage-estimated costs: adaptive all $0.001269, essential $0.001340; final connected pipeline $0.046377; vision $0.011005; repeated council $0.067675; typed inventory $0.000877. The stronger-model vision comparison is estimated at $0.061163. These are estimates at published token rates, not invoices or total development spend. Failed trials, overwritten development runs and retries outside retained runs are not included. Model quality is stochastic. Prompt v1 was refined during development; earlier traces do not contain a complete immutable prompt hash and should not be treated as a fully frozen benchmark.

## Synthetic-only evidence and remaining limits

The 60 cases specify distinct accepted predicate sets and descriptive household profiles. The scorer evaluates their explicit predicates, not 60 independently captured or fully materialized homes. Their file SHA-256 still matches `holdout-lock.json`; no holdout case was used to tune live council prompts. References and policy caps/weights are authored development expectations, not official safety thresholds or human-adjudicated ground truth.

Inventory observations remain proposals; explicit review is required for identity, quantity, usable amount and access. Water arithmetic and existing allocator/device arithmetic are implemented; there is no universal model for every food, medication, pet or fuel unit. Unknown specifications remain unknown. Dependency inspection covers shared power/helper/route/contact/transport relationships; executable profiles are bounded authored educational hazards, not a physical disaster simulator. `stress-envelopes-v0.json` permits current source-bound, host-computed shared-route findings to affect the existing escape predicate once; arbitrary-duration depletion and unsupported challenges remain advisory. Seeded incremental sessions now track per-container water consumption, expiry, current access and whole-container transfers; legacy unseeded sessions retain the aggregate adapter. Non-water consumption and replenishment remain unsupported. Authored and incremental scheduling adapters now use the same SessionTransitionReducer for initialization, time, incident effects and depletion; authored default choices remain isolated from incremental commits.

Practice uses narrow provisional host anchors and fixed denominators. Unsupported action/competency combinations remain unassessed. Variant comparability, a complete validated four-competency examination and native enforcement of pre-feedback timing are pending. Accessibility support does not reduce credit. A newer incomplete attempt cannot be hidden by an older successful one.

Contract tests cover the implemented strict transport paths; they are not exhaustive fuzzing, a security audit, full production load testing or all provider refusal/protocol variants. The server is loopback/synthetic-only and intentionally refuses production startup until a real installation authorization verifier is integrated. Provider free-tier limits caused earlier failed development runs; suites now run sequentially with pacing, call/spend limits and bounded deadlines.

## Native pending

Use [Mac integration handoff](mac-integration-handoff.md). Required: build against the actual newer Mac branch, preserve opaque encrypted AI state on every save, integrate existing Prepare/Plan/Home/Rehearse views, native map attribution/local explanations and search identity matching, App Attest/Keychain, separate cloud/photo consent, lifecycle cancellation/background/resume, selected-image transforms/redaction/deletion, scene synchronization, accessible practice controls and existing intentional PDF/card privacy selections. No Xcode, MapKit, RoomPlan, native PDF, camera, VoiceOver or connected-iPhone result is claimed here.

## Human review pending

Use [review protocol](human-review-protocol.md). Emergency-preparedness content, critical language/translations, manufacturer/clinical boundaries, rubric policy, practice anchors, accessibility needs and consent-based family usability require actual independent review. No responder, clinician, family or competition judge endorsement is claimed. Verify private paid-service handling and family-audience/under-18 provider terms before submitting real household data; the developer's age does not settle audience fit.

## Reproduce

From the repository root:

```sh
scripts/swift.sh packages/DryRunCore test
scripts/swift.sh packages/DryRunVault test -j 4
pnpm --dir services/public-api test
pnpm --dir services/public-api typecheck
pnpm --dir services/ai-orchestrator install --frozen-lockfile
pnpm --dir services/ai-orchestrator test
pnpm --dir services/ai-orchestrator typecheck
pnpm --dir services/ai-orchestrator eval
pnpm --dir services/ai-orchestrator exec tsx scripts/startup-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/replay-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/stress-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/pipeline-replay.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/council-reconcile.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/contracts.ts
```

Live synthetic commands require the server-side secret and should run **sequentially**: `smoke`, `DRYRUN_ACTION=essential ... smoke`, `scripts/pipeline.ts`, `scripts/inventory-eval.ts`, `scripts/vision-eval.ts`, `scripts/council-eval.ts`. See the gateway README for exact invocation/configuration. Native and human checks cannot be substituted with these commands.

Follow-up audit added physical-identity collision rejection on inventory edits, exact device-service practice grading, and generic deterministic gaps for explicitly recorded supply requirements (with subject, unit, expiry and accessibility checks). That audit passed 350 Core tests before the later slices below. The owner-requested [fresh Codex wired-iPhone prompt](CODEX_WIRED_IPHONE_HANDOFF_PROMPT.txt) instructs independent testing and completion of the original full reference rather than trust in these results.

## Follow-up: director tool integration

The gateway now offers the existing Swift scene/current-route/resource/dependency/counterfactual tools through strict revision-bound continuations alongside candidate previews. See [tool contracts and native adapter](director-tools.md). All six executed against the real Linux Swift host without changing its session; a deterministic two-continuation loop committed and replayed exactly. Gateway tests now total 19; TypeScript typechecking passed. The two retained adaptive traces and two connected household pipelines still reproduce their original digests/scores.

A live synthetic Gemini run (`director-tools-evaluation-live.json`) selected inspectDependencies, previewed an advance, returned a validated proposal and committed/replayed in three provider calls. This demonstrates live multi-tool continuation, not live selection of every tool. The first expanded-tools attempt was not retained; the subsequent four-call budget failure is retained in `director-tools-failure.json`. It repeatedly previewed instead of finishing and left the host unchanged. The final policy offers only a preview on the third call if still needed and disables more tools after the preview. No budget increase masked the failure. The new schema also rejects non-preview envelopes whose snapshot/digest differ from the committed source, wrong observation kinds, unknown fields and out-of-catalog profiles. Native integration and all previously listed limitations remain pending.

## Follow-up: exercise inventory and exact scores

Seeded incremental sessions now settle the existing RunState water draw into deterministic per-container balances. They recompute access from committed occupant positions, geometry and hazard exclusions, support whole-container user take/move/drop transfers, and stop at conservative minute expiry boundaries. A blocked container retains its physical quantity while contributing zero accessible water. Unknown quantities/access remain unknown. Real ledger and household source snapshots stay immutable. Existing legacy sessions retain their aggregate behavior and exact original receipt digests. See [exercise inventory](exercise-inventory.md) for constraints and native requirements.

The final Core run passed **357 tests in 62 suites**. Tests include paired blocked-storage vs transferred-stock branches, mixed-unit conservation, fractional expiry, duplicate/permission rejection, persistence rollback and decode/replay. `inventory-session-eval.ts` repeated confirmed intake → submitted transfer → incident → stress against the running Swift host: blocked branch 0 accessible gallons, transferred branch 5, identical real source facts, exact receipt replay, source-inventory-bound stress. This is synthetic domain evidence, not real-room or phone validation.

Re-running the scorer exposed last-decimal floating-point variation from Swift dictionary traversal. ScoreCompiler now accumulates criteria and domains in stable ID order. `score-stability.ts` verified all 60 frozen cases across three independent Swift host processes, including reversed rubric inputs, with exact numeric equality and identical SHA-256 result hashes. The rubric policy/weights and expected-case lock were unchanged. New local evaluation/replay artifacts reflect the deterministic arithmetic order; earlier raw live scorecards remain recorded evidence.

The fresh **live synthetic connected pipeline** also passed for both households in **22 Gemini calls**, retained separately as `integrated-pipeline-inventory.json`. Both source sessions contain frozen inventory; Gemini selected evaluateResources then evaluateCandidateAction before each commit. Offline replay matched each live receipt and the same overall scores (Oak 22.5; Lake 16.5625). This adds integrated evidence, not native or human validation.


## Follow-up: policy, spatial control and actual decision pauses

The stored `dryrun.director-policy/1` now enforces primary hazard allowlists, one supported active spatial incident, a finite horizon, scheduled/pending budgets and allowed forward profile-stage transitions. Model-directed startIncident selects a real room for fire/flood, while the host computes affected spaces/portals and routes. Tornado warnings retain their regional meaning and cannot invent an indoor origin or a new shelter. Policy sessions synchronize scene routes after user movement. `waitUntil` evaluates finite host predicates and reports satisfaction, an intervening mandatory boundary, duration expiry or policy horizon. Verified adjoining operable-door closure is a user-owned exercise posture; no spread-delay or preparedness credit is inferred.

`requestDecision` is now a host pause rather than an ignorable narration command. It must be last; further director effects require a committed user action. The gateway returns needs_user_action without spending a model call during that pause. Explicit user finish remains possible. Actual committed choices now override earlier hypothetical intervention-choice defaults. Large finite resource quantities cannot overflow integer depletion time. New EN/ES/VI action feedback is draft content version 2026.10.3 and keeps language-selection completeness intact.

The final Core run passed **372 tests in 65 suites**; gateway/provider/envelope tests passed **33** and typechecking passed. The offline spatial fixture executes a real occupant move, route inspection, applied scene batch preview, full source-bound proposal-envelope commit and exact replay against Swift. Generated contracts include required fields per command kind, policy/state, minimized preview and full proposal envelope. Metadata labels nextBoundary as requested and narration as an unverified proposal; rendering must use the committed receipt.

The live synthetic spatial run chose the kitchen, previewed its applied scene/routes, proposed a reviewed-profile incident plus time advance and a terminal decision, and replayed exactly in **two Gemini calls**. Source household/home remained unchanged and the receipt is awaiting user input. Earlier failed development attempts exposed lost oneOf schema alternatives, insufficient command fields, unhelpful scheduling-only previews, invalid stage IDs and a whitelist that rejected supplied subject IDs; the retained `spatial-policy-failure.json` is one of these failures, not an exhaustive failure log. The provider subset converter now retains union branches, tool errors pair to the original call ID, one repair stays inside the four-call/90-second limit, and known source subject/geometry IDs can be referenced. These tests do not validate free-text narration or prove physical safety. Some purpose text still overstates route confirmation: keep it labeled unverified and use actual route/unknown fields.

Existing water adaptive traces, both older connected pipelines, controlled stress results, inventory conservation and 60 frozen rubric cases still replay/pass. Exact score stability across three independent hosts remains unchanged. New spatial/pacing checks are synthetic only; real rooms, native lifecycle/consent and wired-iPhone interaction remain pending. Cross-pack simultaneous primary hazards, richer helper/transport outcomes, validated practice timing/competencies and production installation authorization remain explicit gaps. Human safety/language/rubric review is still required.

Authored API follow-up: RehearsalEngine.run now delegates to SimulationSession.authoredResult over the shared SessionTransitionReducer. An independent temporary comparison against the pre-adapter loop at 69c15e5 matched every encoded result field for 24 runs (two households, six hazards, default/alternate choices). Those captured hashes are frozen in authored-adapter-reference.json and tested without retaining a second implementation. The full 372-test Core run passed. Incremental spatial and original adaptive replays remain exact. Practice prefix replay now preserves the original inventory seed and director policy.

The first final-policy connected pipeline failed safely after Gemini selected an already-applied external outage as a spatial startIncident. integrated-pipeline-policy-failure.json preserves the failed operation and unchanged tool trace. The prompt now distinguishes external profiles from spatial stages, minimized snapshots include applied event IDs, and validation rejects duplicate applied IDs before client work. This does not guarantee reliable narration or model behavior.

Final connected retry passed for both synthetic households in **23 live Gemini calls**, retained as integrated-pipeline-policy.json. It used confirmed inventory, household-specific preparation, resource search plans/official evidence, executable stress, user-action-driven director tools, the full proposal-envelope commit, bounded council and deterministic scoring. Local replay exactly matched final receipts and scores (oak 22.5; lake 16.5625). This is a development retry after the retained failure, not a reliability-rate estimate.

## Follow-up: practice chronology and capture

The host now freezes practice source/variant before capture, atomically commits each user action with a derived first observation, persists feedback markers, and revalidates source/receipt/action prefixes before compiling score credit. Caller-created pre-feedback flags are rejected by the legacy recording API. Unknown anchors remain unassessed; coaching excludes credit. See [capture contract and migration](practice-capture.md). The final Core run passed **377 tests in 66 suites**; headless capture/restore/tampering checks passed with one supported answer (25 practice points) and three unknown competencies. This closes the portable capture chronology seam, not native enforcement or validated variant equivalence.

## Follow-up: submitted text/voice intent

[Intent contracts](user-action-intents.md) add source/input-bound interpretation, single-question ambiguity handling, user-only commands and an actual host commit before director continuation. Core rejects stale/mismatched/forbidden effects, preserves atomicity for infeasible compound attempts, and does not retain the raw transcript. Gateway tests cover unknown IDs, invented patches, bounded repair and cancellation. Live synthetic evaluation passed three input types (clear conservation, ambiguous identity/destination, impossible action) in three interpretation calls; a three-call director continuation then used dependency inspection and a real candidate preview, committed the full envelope, and paused at minute 360. Both deterministic and live fixtures replay exactly. These are small development checks, not semantic-accuracy estimates. The final full Core suite totals **381 tests / 67 suites**, gateway **39 tests / 5 files**, and Vault **36 tests / 7 suites**; native speech/consent/timing and human review are still pending.

The actual synthetic-only HTTP /v1/intents route also passed a live request and rejected unauthorized credentials, a duplicate request ID and non-synthetic input (user-intent-http-live.json). No bearer credential is retained in that artifact.

## Follow-up: committed helper consequences

Current exercise helper assignments now drive deterministic helper-to-person reach and dependency inspection; reassignment from an unreachable helper to a reachable helper resolves the current reach requirement while retaining history. Shared simultaneous capacity remains explicitly unknown, with no invented clinical/load limit or scoring rule. See [helper reach](helper-reach.md) and retained synthetic helper-reassignment.json. Core passed **383 tests / 68 suites**, the headless paired assignment fixture passed, and original adaptive/spatial plus final-policy pipeline receipts still replay exactly. Native and live-model helper interaction remain pending.

## Follow-up: consistency and localization diagnostics

The live [council consistency probe](council-invariance.md) completed eight variations of one development case in 32 calls (estimated $0.06329825). Raw council criterion agreement ranged 42.86%–78.57%, with eight correlated critical false-pass observations across variants. Reconciled accepted assessments and deterministic scores stayed identical in every variant. This is not a statistical bias estimate, independent-household validation or proof of council quality. Spanish/Vietnamese variations affect evidence notes only, not the entire localized assessment.

Reanalysis of the retained six synthetic vision cases now reports localization (no new model calls). Routine Flash-lite: positive category recall 3/4, localization at IoU>=0.5 2/4, false-positive negatives 2/2. Stronger Flash: category recall 4/4, localization 3/4, false-positive negatives 1/2. Four positives are variations of one diagram, not independent real rooms. See vision-localization.json; image boxes cannot establish home-graph association or route safety.

The movement audit corrected a shelter/refuge overlay regression: after a committed interior move, the host preserves the recorded interior objective instead of replacing it with exterior egress; an infeasible move preserves that objective too. Core passed **384 tests / 69 suites**, including tornado shelter movement/replay and 24 frozen authored-run hashes. Native scene animation and failed-attempt feedback remain phone checks.

Inventory-image follow-up used three programmatic synthetic bottle-label diagrams in four cases: readable 2 L, unreadable quantity, duplicate images of one physical bottle, and adversarial instructions printed in the image. All four matched the development expectations in four live Gemini calls; unknown stayed null, the duplicate counted once, and injected text did not change the quantity. inventory-image-evaluation.json retains the outputs/usage; make-inventory-image-fixtures.py reproduces inputs. This is deliberately simple diagram/OCR evidence, not real packaging, expiry-label, camera or household-photo validation. Confirmation remains required before ledger facts change.

## Follow-up: concern review integration

The [concern transaction](concern-integration.md) now validates source home/image/task/scenario identity, persists review atomically, deduplicates repeated observations and exposes confirmed preparation links. Explicit user-selected adjacent opening IDs can seed a fresh hypothetical exercise; uncertain evidence requires separate permission. Pixel boxes never become geometry. Routes, movement, helper reach, supply access and spatial overlays share the same selected exclusions; source facts and score predicates stay unchanged. The headless fixture uses a retained live synthetic vision observation and passes review → task link → hypothetical route exclusion → scene synchronization → exact replay → dismissal. Core **387 tests / 70 suites**, gateway **41 tests / 6 files**, and typechecking passed. Legacy reviews need source re-review; native UI/photo/opening-selection and real-data validation remain pending.

## Follow-up: relevant resource refresh

[Normalized refresh inputs](resource-refresh.md) now include actual gap quantities/unknowns, canonical resource-task prerequisites and explicit dependencies, while excluding wording/order and unrelated household edits. Debounce invalidates stale work immediately and preserves useful plans. Returning to accepted inputs cancels newer pending work, fixing an overwrite race. Acceptance rejects wrong tasks, no-car driving, negative expansion and nonfinite ranges. Core **392 tests / 71 suites** and an actual inventory→arithmetic→key headless fixture passed; no new model call. Native timing/geographic fingerprints/MapKit cancellation remain pending.

Concern stress follow-up: frozen selected-opening assumptions now survive stress baseline, controlled retest and read-only counterfactual tools. sourceConcernDigest identifies this hypothetical scope; HouseholdAssessment excludes it from the scored robustness envelope. The integrated fixture and permission mutation test passed, source facts and score stayed unchanged, and Core totals **393 tests / 71 suites**. Existing stress, adaptive/spatial and final-policy pipeline replays remain unchanged.
