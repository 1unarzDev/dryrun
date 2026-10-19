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

Live commands use only synthetic households and diagrams. Set `GOOGLE_AI_STUDIO_KEY` through server secret configuration, and a random `DRYRUN_DEV_TOKEN` of at least 24 characters for HTTP development. Never put either in iOS, fixture output or source. `.env.example` contains placeholders. `DRYRUN_MAX_USD` defaults to $0.25 per provider instance; `DRYRUN_CALL_SPACING_MS=5000` respects the observed 15 RPM development tier. Run live suites sequentially, since separate processes do not share a rate limiter/budget.

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

MapKit candidates remain local. The official-source tools read independently shipped public records, never arbitrary URLs or shared household caches. No Google Search/Maps grounding, Google Places, persistent provider file upload, external messages or purchasing tools are enabled.

Follow-up portable checks: `pnpm exec tsx scripts/director-tools-eval.ts`, `pnpm exec tsx scripts/inventory-session-eval.ts`, and `pnpm exec tsx scripts/score-stability.ts`. See `docs/ai/director-tools.md` and `docs/ai/exercise-inventory.md` from the repository root. `DRYRUN_LIVE_TOOLS=1 pnpm exec tsx scripts/director-tools-eval.ts` uses synthetic data and the server secret. Set `DRYRUN_PIPELINE_OUTPUT=../../fixtures/ai/integrated-pipeline-inventory.json` for both `scripts/pipeline.ts` and `scripts/pipeline-replay.ts` to retain/replay a separate connected run without replacing the original trace.

Director policy/spatial checks: `pnpm exec tsx scripts/spatial-policy-eval.ts`, `DRYRUN_LIVE_SPATIAL=1 pnpm exec tsx scripts/spatial-policy-eval.ts`, then `pnpm exec tsx scripts/spatial-policy-replay.ts`. See `docs/ai/director-policy-and-actions.md`. `requestDecision` pauses until a committed user action; `needs_user_action` makes no provider call. Full proposal envelopes carry requested boundary and receipt-only presentation metadata, and the harness commits through the same Swift `DirectorProposal` method expected on native.

Local pre-feedback practice capture: `pnpm exec tsx scripts/practice-capture-eval.ts`; integration and migration in `../../docs/ai/practice-capture.md`. This runs against Swift and does not call Gemini or send local AI state to the gateway.

Optional submitted action interpretation: `/v1/intents` (synthetic-only); `scripts/intent-eval.ts`, `DRYRUN_LIVE_INTENT=1` for real synthetic Gemini and `DRYRUN_REPLAY_INTENT=1` for retained replay. See `../../docs/ai/user-action-intents.md`. Keep exact source/input binding and commit through Swift before any director continuation.

Additional diagnostics: `scripts/council-invariance-eval.ts` (32 live calls; run sequentially), `scripts/inventory-image-eval.ts` (four live synthetic-label cases), and `scripts/vision-localization-eval.ts` (offline reanalysis of retained boxes). Read evaluation-report.md for actual failures/limits; raw council and vision results are not accepted household facts.

Home review transport and portable task/scenario links: `scripts/concern-eval.ts`; read `../../docs/ai/concern-integration.md`. The fixture reuses retained synthetic Gemini vision output and real Swift route computations. New home responses include reviewProposals bound to exact manifest digests/home revisions; confirmation and hypothetical opening selection stay in the local host.

Resource strategy refresh: `scripts/resource-refresh-eval.ts` drives actual Swift inventory arithmetic and normalized local keys without a model call. Native scheduling contracts are in `../../docs/ai/resource-refresh.md`; geographic results/origin never enter this key or cloud tools.
