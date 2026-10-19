# Integrated Gemini evaluation — 2026-10-19

Portable implementation on Linux, based on `main` at `436b243276e0f333131a1813b580382971949748`. No iOS source was changed. The root `DryRun_AI_Implementation_Reference.md` is the supplied specification; no `.txt` copy exists in this checkout. See [implementation map](implementation-map.md) for the verified original flows and [Mac handoff](mac-integration-handoff.md) for exact integration points.

This is an implemented, synthetic-tested integration package, **not a production release or a completed native experience**. Production authorization, device integration, real-photo quality and human validation remain gates.

## Passed on Linux

| Check | Actual result |
|---|---|
| Existing baseline Core | 333 tests passed before changes |
| Final Core | 350 tests / 61 suites passed, Swift 6.2 Docker |
| Vault | 36 tests / 7 suites passed, including legacy/additive encrypted sidecar roundtrip |
| Private gateway | 12 tests passed; TypeScript check passed |
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

Inventory observations remain proposals; explicit review is required for identity, quantity, usable amount and access. Water arithmetic and existing allocator/device arithmetic are implemented; there is no universal model for every food, medication, pet or fuel unit. Unknown specifications remain unknown. Dependency inspection covers shared power/helper/route/contact/transport relationships; executable profiles are bounded authored educational hazards, not a physical disaster simulator. `stress-envelopes-v0.json` permits current source-bound, host-computed shared-route findings to affect the existing escape predicate once; arbitrary-duration depletion and unsupported challenges remain advisory. Dynamic per-container consumption/access after a room becomes blocked is not modeled; current inventory projection uses confirmed initial access. Existing authored runs and incremental sessions share RunState/routing/allocation rules but retain separate scheduling adapters; existing default choices are isolated from incremental commits.

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

Follow-up audit added physical-identity collision rejection on inventory edits, exact device-service practice grading, and generic deterministic gaps for explicitly recorded supply requirements (with subject, unit, expiry and accessibility checks). The final Core count is 350 tests. The owner-requested [fresh Codex wired-iPhone prompt](CODEX_WIRED_IPHONE_HANDOFF_PROMPT.txt) instructs independent testing and completion of the original full reference rather than trust in these results.
