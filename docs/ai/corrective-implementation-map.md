# Corrective reconciliation — 2026-10-20

Specification: root `DryRun_AI_Implementation_Reference.md` (owner-modified before this session; preserved). No `.txt` counterpart or applicable AGENTS.md in this checkout. Baseline `main` at `26332ded170f2fea414d581fb50d5de6f4093ab9`. Node 26.11.1, pnpm 12.14.0, Swift 6.2 Docker; no host Swift/Xcode. Secret presence checked without printing its value. No native execution is claimed.

## Verified paths and missing integration

All six cards in `RehearseViews.swift` select scenario ID → `AppModel.startRehearsal(scenarioID:variants:)` → immutable `RehearsalInput` → `run` → `RehearsalEngine.run` → `SimulationSession.authoredResult` → shared `RunState`/`SessionTransitionReducer` → `RehearsalCursor`. Choosing an option reruns the entire authored schedule. The installed native path does not call the private Gemini gateway or the incremental session. This is a verified integration gap, not evidence that a different Mac branch behaves identically.

Portable AI path: `DryRunHost/main.swift` initialize → `SimulationSession.initialize` → explicit director policy; NDJSON commit/preview/tool/query → `Gateway` typed tool suspension → `executeDirectorTool` → Core preview → version/revision-bound proposal commit. Core owns route and resource effects; TypeScript does not simulate them. `HomeSceneContext` binds home revision; source input freezes household/home per session. The new `mechanicsVersion` is optional in persistence: historical logs keep their behavior, new initialized sessions use `dryrun.hazard-mechanics/5`; persisted `/1`, `/2`, `/3` and `/4` sessions retain their exact historical behavior.

Household editors → `AppModel.updateHousehold` → `HouseholdEditing` → `PrivateSnapshot` → `save` → publish/invalidate. Cloud `HouseholdContextSnapshot` previously projected only age/needs and essential/power booleans. It omitted recorded conditions/disabilities, essential medication, communication instructions, equipment purpose/storage instructions, specifications and actual supplies. The corrected projection includes relevant recorded fields, anonymous IDs and provenance. Names, contacts, exact location and unrestricted care-plan notes stay out. These fields remain sensitive and require the native consent/provider deployment path.

Preparations: `FeatureRunner` previously requested only candidate IDs when a catalog existed and overwrote many rationales/questions with fixed text. New-format proposals permit grounded bespoke tasks and preserve model reasoning; historical selected-ID output retains its compatibility adapter. The host must accept real-world proposals explicitly; simulated choices do not complete preparations or score predicates.

Home: `HomeTabView` → `ManualHomeEditorView` draft → synchronous `onSave` launching an asynchronous `Task` → `AppModel.updateHome` → authoritative private snapshot save → publish/invalidate. The current caller already dismisses only after success. Verified gaps: editor cannot await/report its callback, has no in-flight Save guard; updateHome does not reject a stale base revision and can increment multiple draft revisions; canvas disappears into contextual Form; raw dimensions and confirmation chores remain. These are code findings, not a reproduced iPhone diagnosis. Native Save failure still requires failed-write/relaunch checks.

Practice: portable `IntegratedAIState.beginPracticeCheck`/`submitPhasedPracticeAction` → persisted attempts/observations → host-reconstructed `PracticeEvaluator` → deterministic `ScoreCompiler`. Native AppModel does not currently own/load this sidecar, expose this queue, or compile its scores. Native NextSteps still documents the superseded no-score rule. Older portable practice is a four-competency phased check, not yet the required retiring six-hazard bank. Adding UI text alone cannot repair this lifecycle. Replay reconstruction now preserves the new mechanics version.

## Causes established versus pending

Established: disconnected native incremental/AI path; cloud-context omissions; closed task selection and canned rewriting; generic no-effect `fallback()`; absent escape/accounting and shelter-arrival commands; absent thermal range; no explicit stored-volume use by activity; missing flood access-loss profile. The new reducer/receipt and fallback address the portable mechanics gaps. Existing geometry, inventory, assistance, allocator and policy code is reused.

Pending: actual scene behavior and Save failure on the owner's current Mac branch; native integration, renderers, queue observation and durable sidecar preservation. Do not replace working PDFs or infer current hardware behavior from this Linux checkout.

## Reproduction

- Baseline: `scripts/swift.sh packages/DryRunCore test`: 474 tests passed; gateway 80 tests/typecheck passed.
- Red check: `scripts/swift.sh packages/DryRunCore test --filter SixHazardExperienceTests`: all six lacked a mechanics receipt; seven assertions failed before implementation.
- Corrective Core suite: 481 tests passed, including seven new behavioral checks and 24 preserved authored-run hashes.
- `pnpm --dir services/ai-orchestrator exec tsx scripts/six-hazard-eval.ts`: six offline host continuations/replays, synthetic same household/home. This smoke is not the entire two-branch/per-hazard acceptance gate.
- `... six-hazard-eval.ts --live`: actual gateway/tools/host validation and committed log replay, with per-row artifacts; report only the results actually captured.
