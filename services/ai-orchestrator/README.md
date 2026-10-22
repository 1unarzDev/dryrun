# Private DryRun AI gateway

Node 22+ service, separate from the public-data Worker. The public API is unchanged. Synthetic-only development endpoints listen on loopback. Production fails closed: the App Attest authorization service, private-data billing/audience terms decision and native consent must be integrated before deployment. Fixture tokens cannot authorize production.

From the repository root:

```sh
scripts/swift.sh packages/DryRunCore build
pnpm --dir services/ai-orchestrator install --frozen-lockfile
pnpm --dir services/ai-orchestrator test
pnpm --dir services/ai-orchestrator typecheck
pnpm --dir services/ai-orchestrator eval
```

Live commands use only synthetic households and diagrams. Set `GOOGLE_AI_STUDIO_KEY` through server secret configuration, and a random `DRYRUN_DEV_TOKEN` of at least 24 characters for HTTP development. Never put either in iOS, fixture output or source. `.env.example` contains placeholders. `DRYRUN_MAX_USD` defaults to $0.25 per provider instance; `DRYRUN_CALL_SPACING_MS=5000` spaces calls within this process; actual model/project limits must be checked in AI Studio and can be lower. Run live suites sequentially, since separate processes do not share a rate limiter/budget.

```sh
pnpm --dir services/ai-orchestrator start
pnpm --dir services/ai-orchestrator smoke
DRYRUN_ACTION=essential pnpm --dir services/ai-orchestrator smoke
pnpm --dir services/ai-orchestrator exec tsx scripts/pipeline.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/inventory-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/vision-eval.ts
DRYRUN_MODEL=gemini-3.8-flash pnpm --dir services/ai-orchestrator exec tsx scripts/vision-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/council-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/contracts.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/stress-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/pipeline-replay.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/startup-eval.ts
```

`smoke` drives the actual Swift executable through NDJSON: initialize → incident commit → submitted action → host arithmetic → Gemini → local preview tool → same operation continuation → validated commit → next turn → offline replay. `pipeline` connects inventory gaps, three task proposals, resource strategy, executable stress challenges, council and deterministic score. `eval` checks 60 frozen policy fixtures using Swift; no duplicate TypeScript score engine exists.

HTTP POST `/v1/operations`, `/v1/continue`, `/v1/cancel`, `/v1/features`; Bearer fixture token required locally. Requests must specify `synthetic:true`, version `dryrun.ai/1`, unique request ID and strict minimized context. See generated JSON schemas under `content/ai/contracts` and `docs/ai/mac-integration-handoff.md`.

SDK 2.30.0 is pinned. HTTP role configuration uses `DRYRUN_MODEL` (routine), `DRYRUN_HOME_MODEL` (defaults to the evaluated 3.8 Flash) and `DRYRUN_ASSESSMENT_MODEL` (adjudication, defaults to 3.1 Flash Lite). All share one paced provider queue and spend budget. Standalone evaluation scripts select their explicitly recorded model. Interactions `store:false`, full transient protocol steps and signatures preserved. Only returned receipts/final proposals enter fixtures; no hidden deliberations. The provider sends a supported JSON Schema subset; full Zod bounds/references and Core semantics still apply. Missing credentials, refusals, invalid output, timeout and quotas return or throw typed unavailable errors; never clear valid local results. Model prose remains a proposal; render resource balances/scenes from the committed receipt.

Limits: 96 KB director HTTP body / 6 MB feature HTTP body, 4 inline images / 1 MB each inside a role runner, 90-second director operation, 4 model turns / one repair, 32 scheduled profiles / 128 commits / 8 pending events, 3 task/resource/stress suggestions, 3 first-pass council reviewers plus adjudication, 240-second council deadline. Gateway TTL deletes pending history even when idle. Cancel by continuation token or original request ID. Native cancellation should also abort its HTTP request and discard stale results.

MapKit candidates remain local. The official-source tools read independently shipped public records, never arbitrary URLs or shared household caches. The separate `/v1/research` operation now enables Google Search + URL Context using only a minimized locality/service brief. It retains attributed answers, citations, suggestions and inspection metadata as a temporary companion; it cannot populate unrestricted resource databases, Apple pins or PDFs. Google Places/Maps grounding, persistent provider file upload, external messages and purchasing tools remain disabled.

Follow-up portable checks: `pnpm exec tsx scripts/director-tools-eval.ts`, `pnpm exec tsx scripts/inventory-session-eval.ts`, and `pnpm exec tsx scripts/score-stability.ts`. See `docs/ai/director-tools.md` and `docs/ai/exercise-inventory.md` from the repository root. `DRYRUN_LIVE_TOOLS=1 pnpm exec tsx scripts/director-tools-eval.ts` uses synthetic data and the server secret. Set `DRYRUN_PIPELINE_OUTPUT=../../fixtures/ai/integrated-pipeline-inventory.json` for both `scripts/pipeline.ts` and `scripts/pipeline-replay.ts` to retain/replay a separate connected run without replacing the original trace.

Director policy/spatial checks: `pnpm exec tsx scripts/spatial-policy-eval.ts`, `DRYRUN_LIVE_SPATIAL=1 pnpm exec tsx scripts/spatial-policy-eval.ts`, then `pnpm exec tsx scripts/spatial-policy-replay.ts`. See `docs/ai/director-policy-and-actions.md`. `requestDecision` pauses until a committed user action; `needs_user_action` makes no provider call. Full proposal envelopes carry requested boundary and receipt-only presentation metadata, and the harness commits through the same Swift `DirectorProposal` method expected on native.

Local pre-feedback practice capture: `pnpm exec tsx scripts/practice-capture-eval.ts`; integration and migration in `../../docs/ai/practice-capture.md`. This runs against Swift and does not call Gemini or send local AI state to the gateway.

Optional submitted action interpretation: `/v1/intents` (synthetic-only); `scripts/intent-eval.ts`, `DRYRUN_LIVE_INTENT=1` for real synthetic Gemini and `DRYRUN_REPLAY_INTENT=1` for retained replay. See `../../docs/ai/user-action-intents.md`. Keep exact source/input binding and commit through Swift before any director continuation.

Additional diagnostics: `scripts/council-invariance-eval.ts` (32 live calls; run sequentially), `scripts/inventory-image-eval.ts` (four live synthetic-label cases), and `scripts/vision-localization-eval.ts` (offline reanalysis of retained boxes). Read evaluation-report.md for actual failures/limits; raw council and vision results are not accepted household facts.

Home review transport and portable task/scenario links: `scripts/concern-eval.ts`; read `../../docs/ai/concern-integration.md`. The fixture reuses retained synthetic Gemini vision output and real Swift route computations. New home responses include reviewProposals bound to exact manifest digests/home revisions; confirmation and hypothetical opening selection stay in the local host.

Resource strategy refresh: `scripts/resource-refresh-eval.ts` drives actual Swift inventory arithmetic and normalized local keys without a model call. Native scheduling contracts are in `../../docs/ai/resource-refresh.md`; geographic results/origin never enter this key or cloud tools.

Source-to-score checks: `scripts/assessment-policy-eval.ts` runs fresh synthetic shelter snapshots and actual food inventory confirmations through the Swift host under household-assessment/3; it makes no model call. `../../scripts/verify-ai-portable.sh` runs the consolidated offline portable checks. See `../../docs/ai/assessment-policy.md` for versioned source interpretation, score history and unknowns.

`scripts/source-assessment-eval.ts` checks 60 **actual source-household** combinations (40 development, 20 held-out source cases), separate from the original 60 explicit-predicate arithmetic fixtures. The source fixture/hash lock is committed; normal evaluation never regenerates it. `--generate` is creation-only and refuses to overwrite an existing fixture. Source references are policy-authored and not human-adjudicated; all cases share the sample ranch, so varied geometry claims rely on the Core spatial suite.

`scripts/source-council-eval.ts` is a **live**, paced development evaluation: three selected actual source households × three repeats × four reviewers/adjudication passes (36 calls before any repairs). It checks a five-criterion policy-authored reference subset and exact host score stability, retains raw failures, usage, cost and latency, and never consumes the locked source holdout. Run sequentially with other live evaluations; it uses the server-side key and existing spend cap.


Essentials intake follow-through: `pnpm exec tsx scripts/preparation-inventory-eval.ts` is offline and drives actual confirmation→gaps/tasks/resource-key/score through Swift. `pnpm exec tsx scripts/inventory-eval.ts` is a live synthetic eight-case preparation/4 evaluation, writing inventory-evaluation-v4.json. The live image equivalent writes inventory-image-evaluation-v4.json. Earlier recorded outputs remain historical. Native must explicitly confirm optional preparationKind with the item batch; generic categories confer no item identity.

Provider calls serialize with abortable queue/rate-limit waits. Cancellation before SDK dispatch makes no call or spend reservation; a cancelled middle job cannot let later requests overtake an active call. Late replies are rejected after accounting for reported usage. `test/provider-cancellation.test.ts` exercises this at a mocked official-SDK boundary; actual transport/device cancellation remains a separate verification gate.

`pnpm exec tsx scripts/official-resource-eval.ts` runs two live synthetic resources/3 queries (known source region and outside-pack), writing official-resource-evaluation-v1.json with calls/usage/cost estimate. The accepted reason is host-composed; model prose cannot establish facility capabilities. This is independent bundled evidence, never MapKit data or Google-grounded listings. Native identity joins and live capabilities remain separate checks.


Fallback/resume and action provenance: `pnpm exec tsx scripts/fallback-resume-eval.ts` is offline by default. `DRYRUN_RESUME_LIVE=1 pnpm exec tsx scripts/fallback-resume-eval.ts` resumes a retained synthetic live-model session through local pause/restoration and a new Gemini continuation. `pnpm exec tsx scripts/fallback-resume-replay.ts` verifies both committed traces without model access. Native should use Core's userActionContexts rather than guessing lastAction; the NDJSON response supplies lastAction and recentActions with source revision/command index and privacy minimization.


HTTP cancellation: `src/http.ts` is the transport adapter used by startup. It passes a request-connection AbortSignal into director start/resume, releases listeners, and leaves successfully delivered tool requests pending until continuation/cancel/TTL. Consumed tokens remain valid only as owner-scoped cancellation handles while their operation is active; they cannot replay. Feature roles reject late replies after abort and stop a cancelled council without extra reviewers. The 66-test gateway suite includes actual loopback HTTP disconnect/continuation/cancellation and split-UTF-8 requests, plus controlled late provider replies. This is synthetic transport evidence; real Gemini/URLSession lifecycle tests remain native-pending. No production verifier is configured by this factory.


Recorded household food-day exercises: `pnpm exec tsx scripts/food-session-eval.ts` is offline by default; `DRYRUN_LIVE_FOOD=1` uses real Gemini with synthetic data. `pnpm exec tsx scripts/food-session-replay.ts` checks both retained results without calls. The strict snapshot contract now permits day units; source foodPolicy selects versioned draw. See ../../docs/ai/exercise-inventory.md. The successful director/4 comparison used six calls, estimated $0.009718, and different final pacing for depleted/prepared stock. A retained four-call director/3 development failure exposed rejection of an exact supplied committed event ID, now fixed/tested. Native source persistence, scene/translation rendering and real-device lifecycle remain pending.

Controlled stock retests and failures: see [stress-retest.md](../../docs/ai/stress-retest.md) for the `initialInventoryItemIDs` minimizer, director/5 command roles and strict unavailable counterfactual observation. `scripts/stress-retest-live.ts` runs a bounded real-model synthetic case using the server key. `scripts/stress-retest-repair-eval.ts` and `scripts/stress-retest-replay.ts` are offline and included in `scripts/verify-ai-portable.sh`. Retained live failures and their actual cost/limitations are documented; green protocol replay does not certify narrative or device quality.

Four-situation provisional practice checks use local frozen sources and deterministic grading, with no Gemini call. Run `scripts/practice-phases-eval.ts` and `scripts/practice-phases-replay.ts` through tsx after building Core. See [practice-phases.md](../../docs/ai/practice-phases.md) for the API/contract, first-answer/source invariants, synthetic evidence and narrow continuity/human/device limits. Both commands are included in portable verification.

The non-device /2 practice plan adds `scripts/practice-nondevice-eval.ts` and `scripts/practice-nondevice-replay.ts` (tsx; Core build first), also included in portable verification. It pins anchors/3 while /1 remains on anchors/2. See practice-phases.md for contextual prerequisites, isolated host conservation proof and pending human/device review.

`pnpm exec tsx scripts/practice-order-eval.ts` runs and exactly replays both reverse-order practice variants after the forward fixture generators. It compares bound sources and correct competency credits and checks pre-feedback resume. Included in portable verification; synthetic execution consistency only, with human variant equivalence still pending.

Home context /2: `pnpm exec tsx scripts/home-scene-eval.ts` validates four actual-host safety-attribute/route cases, strict cross-language schemas and historical /1 support without model calls. See [home-scene-context.md](../../docs/ai/home-scene-context.md) for minimization, recorded evidence and native checks. Included in portable verification.

The local image-calibration companion is deliberately absent from cloud schemas. See [image-geometry.md](../../docs/ai/image-geometry.md) for Swift transform/provenance helpers, encrypted selected-frame metadata and exact native capture/deletion checks. Gateway tests reject accidental companion/matrix forwarding before provider dispatch.

Housing/site/marker expansion is documented in [housing-location-support.md](../../docs/ai/housing-location-support.md), with the current [Claude wired-iPhone handoff](../../docs/ai/CLAUDE_WIRED_IPHONE_HANDOFF_PROMPT.txt). `HouseholdContextSnapshot` includes dwelling/utility context and minimized site provenance; use `HomeSceneContext(home, household:)` to include host baseline routes/needs. Current source assessment is /6; frozen old cards retain their original assessment version.

`pnpm exec tsx scripts/housing-layout-eval.ts` runs six actual host cases without a key. Set `DRYRUN_LIVE_HOUSING=1` to additionally test Gemini interpretation and preparation/resource roles; live output paths are unique and existing paths are rejected. `DRYRUN_HOUSING_FEATURES_ONLY=1` limits a live run to preparation/resources for the three synthetic layouts. `DRYRUN_HOUSING_OUTPUT` selects a new path. `housing-director-eval.ts` runs a real committed-action/tool/validated-director loop for the apartment-complex fixture; `DRYRUN_HOUSING_DIRECTOR_OUTPUT` must also be new. These are synthetic tests, not phone/scan/safety certification.

`output-quality-eval.ts` inspects retained actual output with advisory field-specific word bands and claim-review flags. Override comma-separated `DRYRUN_OUTPUT_AUDIT_SOURCES` (filenames under fixtures/ai) and `DRYRUN_OUTPUT_AUDIT_PATH` for a separate report. It never truncates text or declares factual correctness from length. Raw council opinions remain review data; the app displays only accepted host evidence and score compilation.

`pipeline.ts` now preserves a timestamped default output and source hashes, refuses overwrite before starting a host/provider, and retains unique bounded failure diagnostics. `DRYRUN_PIPELINE_OUTPUT` selects an explicit new file. For exact historical accepted-score replay plus separately labeled current reassessment, set that same input on `pipeline-replay.ts`; `DRYRUN_REPLAY_OUTPUT` selects a separate replay-report path. Legacy food-session live cards did not retain their accepted predicates: their replay now explicitly checks the known /5→/6 single-family migration and numerical/status equality, without relabeling the frozen /5 card as an exact /6 artifact.


Apartment-fire regression: `pnpm exec tsx scripts/elevator-fire-eval.ts` executes actual committed fire states with stairs+elevators and elevators-only, asserting exclusions, exact replay and unchanged source. Set `DRYRUN_LIVE_ELEVATOR=1 DRYRUN_ELEVATOR_OUTPUT=../../fixtures/ai/<new-name>.json` for two synthetic live interpretations; paths cannot overwrite retained live evidence. The correct route booleans in v2 do NOT validate its unsupported window/causal prose. Native banners/graphics/posted building procedures remain wired-iPhone checks. Read [the concentrated-flow audit](../../docs/ai/ux-concentration-audit.md) for current prompt versions, native changes and integration gaps.

Use `DRYRUN_HOUSING_DIRECTOR_ELEVATOR_ONLY=1 DRYRUN_HOUSING_DIRECTOR_OUTPUT=../../fixtures/ai/<new-name>.json pnpm exec tsx scripts/housing-director-eval.ts` to run the actual director/tool/commit loop with synthetic elevator-only apartment geometry. It additionally requires no primary route and explicit elevator exclusions in the committed receipt. Latest retained v2 uses director/7; raw purpose requests building-specific procedures and assistance review without inventing an exit. Native integration and human review remain pending.


## Current corrective evaluations

The director uses high thinking, a 6000-token generation ceiling, a six-turn/90-second operation budget and one bounded repair. Its provider effect schema reflects the selected hazard's recorded profiles; Core remains the state authority. Gemini can compose incidents and user suggestions, and generate grounded bespoke preparations. No fixed task catalog or canned choice IDs constrain its reasoning. See [current handoff](../../docs/ai/mac-corrective-handoff.md) for exact native contracts and the required production authorization/consent integration.

Run offline from this directory after building the Swift host:

```sh
pnpm exec tsx scripts/six-hazard-branches.ts
pnpm exec tsx scripts/six-hazard-replay.ts
pnpm exec tsx scripts/six-hazard-eval.ts
pnpm exec tsx scripts/practice-hazard-eval.ts
```

Run live evaluations sequentially in the server environment with synthetic data:

```sh
pnpm exec tsx scripts/six-hazard-eval.ts --live
pnpm exec tsx scripts/personalization-eval.ts
pnpm exec tsx scripts/resource-discovery-eval.ts
DRYRUN_COUNCIL_OUTPUT=../../artifacts/ai/council-current.json pnpm exec tsx scripts/council-eval.ts
```

`DRYRUN_MODEL=gemini-3.8-flash` selects the stronger allowed director model. The default is `gemini-3.1-flash-lite`. `DRYRUN_USE_BACKUP_KEY=1` lets development evaluation scripts use the separately authorized server backup; never include either secret in the app, traces or repository. Live pass/fail artifacts include failed attempts. Named-resource discovery remains an open gate until the real search-enabled provider calls succeed; quota fallback is not discovery evidence.


Free-tier eligibility and failures: see [official-source research](../../docs/ai/gemini-free-limits.md). Quotas are per project, not key. `provider_rate_limited` (429), `provider_overloaded` (503), `provider_model_unavailable` (404), `provider_access_denied` (403) and `provider_request_rejected` (400) stay distinct. No hidden SDK retries or automatic billing changes occur. A refused/unknown outcome retains its conservative budget reservation; `accountedUSD` is not proof of charges incurred.

`DRYRUN_RESEARCH_MODEL=gemini-2.5-flash` is an explicit research-only compatibility option for previously eligible accounts, with model-specific token accounting and default model reasoning. It never changes director/Home models. Both authorized keys returned **404: no longer available to new users** in the retained entitlement probes; it is not a working free workaround for these keys. Modern 3.1/3.8 Search grounding is unavailable on the Free API tier according to current pricing. Ordinary backup-key generation did work during the same evaluation period. A fresh safe diagnostic is `DRYRUN_USE_BACKUP_KEY=1 pnpm --dir services/ai-orchestrator exec tsx scripts/provider-entitlement-eval.ts`. It uses a synthetic public brief, no retries, and redacts secrets before storing diagnostics. Do not repeatedly probe a known ineligible model.


Review the latest [live corrective audit](../../docs/ai/live-corrective-audit.md) separately from schema acceptance. `corrective-live-replay.ts` replays six last committed states from one complete real-provider attempt, including failures; it does not promote failed live rows. `export-corrective-evidence.ts` exports a complete six-row report for review. `DRYRUN_PERSONALIZATION_CASE=medication-storage DRYRUN_PREPARATION_MODEL=gemini-3.8-flash` runs the recorded stronger-model preparation comparison; the latest attempt timed out. New preparation reports retain the actual instruction hash. The explicit-safety-assurance guard is a narrow observed-defect check, not a semantic grounding or medical validator.

### Gemini-primary Groq fallback (synthetic development)

Set `GROQ_API_KEY` only in the server environment to enable the additive adapter. `DRYRUN_GROQ_MODEL` defaults to `openai/gpt-oss-120b`; `DRYRUN_GROQ_EXTRACTOR_MODEL` defaults independently to `openai/gpt-oss-120b`. The 20B extractor remains an explicit evaluation override: its retained live outputs have factual/usefulness failures and do not qualify it as the default. Both models still require current semantic quality gates; a default is not an endorsement or quota guarantee. The development evaluation helper may read the existing secret file; the server does not bundle/read that file or expose keys to iOS. Production authorization remains a required separate dependency and startup fails closed.

Private operation/feature/intent requests must explicitly include Groq in `providerConsent` for private fallback. Omission remains Gemini-only. Public research uses a fresh allowlisted public brief, actual Groq `browser_search`, then separate tools-disabled strict extraction. It never forwards Google grounding or household history. Groq images are unsupported in this evaluated configuration; photo-bearing contexts do not route to text fallback. See `src/provider-capabilities.ts` and [actual coverage](../../docs/ai/groq-fallback-status.md), including open gates. Configured capability is not a quality/entitlement claim.

Both providers share the logical operation deadline/call allowance. A switch increments attempt generation; continuation replies are fenced at the unchanged revision too. One bounded transient quota retry may fit the remaining deadline; daily exhaustion opens a cooldown circuit. HTTP retries are explicit; native fetch has no SDK retries. Successful token-reset metadata paces subsequent calls, without hard-coded account entitlements. Internal browser work is not an exact billable-search count. Prior useful results and all committed host state survive failure.

Additional offline checks:

```sh
pnpm exec tsx scripts/commit-reconciliation-eval.ts
pnpm exec tsx scripts/provider-hazard-continuity-eval.ts
```

Additional live checks use synthetic fixtures only:

```sh
pnpm exec tsx scripts/groq-search-eval.ts
DRYRUN_PROVIDER=groq-fallback DRYRUN_HAZARD=water-outage pnpm exec tsx scripts/six-hazard-eval.ts --live
DRYRUN_REPRESENTATIVE=documented pnpm exec tsx scripts/six-hazard-eval.ts --live
```

Inspect timestamped artifacts and semantic findings before claiming a pass. Separate live extraction of permitted recorded Groq evidence uses `groq-extraction-eval.ts` with `DRYRUN_GROQ_SOURCE_RECEIPT`; it preserves original freshness and is not another live search. The captured response parser rejects unsupported/ambiguous browser response shapes instead of treating ordinary assistant URLs as retrieval evidence. Support for optional-field-free in-band snippets remains an explicit compatibility gate.


Quota composition: `configuredGroqClients` shares the same configured model client across private direction, browser search and structured extraction, retaining cooldown/token metadata without retaining role messages. Distinct model overrides retain independent eligibility. Late successes cannot clear a newer quota window; overlapping failures keep the longer window. Local circuit errors report remaining cooldown separately from actual upstream responses. Groq public research4 requests medium reasoning; current live factual/usefulness qualification remains open (see evaluation report).

Search and structured extraction share `ProviderOperation.tryOutputRepair`: one bounded recovery for invalid generated output across both phases, within the original operation/deadline/call/spend allowance. Configuration, capability and quota failures are not output repairs. Recovery tests use recorded provider failures/browser responses and synthetic normalization; actual fresh live quality remains separately pending.
