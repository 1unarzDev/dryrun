# Home concerns linked to Prepare and Rehearse

Reference §§6, 9–10 require observations to stay reviewable and concern links to work through domain authority. The Home response now optionally includes normalized `reviewProposals` alongside the original `proposal`. `normalizeHomeReview` binds every candidate to its actual manifest digest, current home revision and known room/task IDs. It rejects stale scenes, unknown associations and boxes overlapping redacted regions. It does not confirm anything or identify a metric obstruction/opening from pixels. Full physical projection remains unavailable without actual transformed intrinsics and aligned depth.

Native saves a decision through `IntegratedAIState.reviewConcern(...home:household:rubric:library:at:persist:)`. This validates the exact current home fingerprint, manifest, approved action and scenario IDs and commits the review atomically. Use this entry point for new reviews instead of calling the lower-level legacy ledger method. Failed persistence leaves the state unchanged. Repeated model IDs for materially overlapping evidence cannot create duplicate tasks. Dismissals stay suppressed for the same image/home evidence; new material evidence can be reviewed again. A home revision/fingerprint change makes old links stale until re-reviewed.

Confirmed reviews produce `concernTasks(currentHome:)`: stable concern/task/action IDs, home editor, room and related scenarios, evidence/source references, and `earnsScoreByItself=false`. Existing canonical preparations remain the action/score authority. A review is not automatic task completion, inventory confirmation or new score credit. A newly observed issue can reopen an action even if it was previously recorded as satisfied. Dismissed and uncertain reviews do not create preparation tasks. A manual home edit, measurement or explicit clearing action remains available through the existing home editor; the review transaction does not alter scan geometry or opening operability.

Optional scenario use is an additional explicit action from the same inline concern. Native presents the recorded room's existing openings for selection. `concernExerciseSeed(concernID:scenarioID:selectedPortalIDs:allowHypothetical:home:)` validates the chosen existing IDs and their actual adjacency to that room. It supports possibleObstruction only, never a model-derived obstacle polygon. An uncertain concern also requires `allowHypothetical=true`; dismissal cannot be used. Seed creation never runs an exercise automatically.

Start a fresh `SimulationSession.initialize(...concernSeed:)`. The seed stores the reviewed evidence/decision, explicit hypothetical permission, selected IDs and source home fingerprint. It is validated again at replay and included in the session digest. The canonical EgressPlanner is decorated with the selected hypothetical portal exclusions; user movement, inventory access, helper routes, hazard routes and read-only route requests honor them. A committed spatial scene contains the same excluded IDs and an explicit educational assumption. Source HomeModel and household remain untouched. Missing camera calibration cannot create openings, change metres, or assert that a selected opening is actually blocked. A hypothetical seed does not update preparedness predicates or grant score credit. Generic stress tools currently start from the original household; they do not automatically import this concern seed, so do not describe their result as a controlled retest of the concern.

The additive seed and optional review fingerprint preserve older session/Vault decoding. Legacy reviews without a source fingerprint need re-review before new linked tasks or scenario seeding; preserve their history. Exercise and practice prefix replay carry the seed, so capture identity includes these assumptions.

Local NDJSON operations:

- `reviewConcern`: session, aiState (optional for the first review), concernProposal, imageManifest, concernDecision, rubric → aiState and concernTasks.
- `concernExercise`: original session, aiState, concernID, selectedPortalIDs, allowHypothetical → a fresh session with the seed. This local example chooses a fixed fixture session ID; native supplies its own unique session ID through the Swift factory.

These requests contain private local state and are **not cloud payloads**. Use the minimized Home response/proposal schema for cloud work. `dryrun-host` now rejects unknown operation names instead of silently returning a query.

Reproduce after the Core build:

```sh
pnpm --dir services/ai-orchestrator exec tsx scripts/concern-eval.ts
```

`fixtures/ai/concern-integration.json` consumes an already retained real Gemini interpretation of a synthetic diagram, then executes uncertain review, permission rejection, fixture-selected opening, real route computation, task confirmation, dismissal and exact replay. No new model call or pixel-to-opening inference is used. Core tests cover unknown actions/rooms, wrong/malformed manifests, redacted evidence, duplicate proposals, atomic save failure and source geometry changed without a revision bump. Native capture/consent, annotation overlays, actual opening selection, draft content review, friction and wired-iPhone testing remain pending.
