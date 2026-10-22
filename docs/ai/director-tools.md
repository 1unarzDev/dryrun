# Director read-only tool continuation, v1

Revisit reference section 10 when integrating this seam. `services/ai-orchestrator/src/contracts.ts` is the strict wire contract; generated continuation JSON schema lives in `content/ai/contracts`. The same revision/event sequence/context/household/home binding and one-use token protect every tool. No result writes facts or commits an exercise action.

| Function | Arguments | Minimized response beyond binding/snapshot/contextDigest |
| --- | --- | --- |
| validateSuggestedActions (gateway-owned mandatory phase) | `{commands:[director commands],suggestedActions:[complete user choices]}` | unchanged source snapshot/digest; `suggestionValidation:[{id,feasible,rejection?}]`, exact ordered IDs; no observation/preview |
| evaluateCandidateAction | `{ "command": { "kind": "advance", "minute": 120 } }` or `commands` batch | Hypothetical snapshot/digest and optional typed preview scene/routes/director state; omit observation |
| inspectScene | `{}` | `observation: { kind: "inspectScene", scene?: HomeSceneContext }` |
| queryRoutes | `{}` | `observation: { kind: "queryRoutes", routes: [...] }` |
| evaluateResources | `{}` | `observation: { kind: "evaluateResources" }`; current balances/unknowns are in snapshot |
| inspectDependencies | `{}` | `observation: { kind: "inspectDependencies", dependencies: [...] }` |
| runCounterfactual | `{ "profileIDs": ["supplied-reviewed-profile-id"], "retestPlan"?: StressRetestPlan }` | `observation: { kind: "runCounterfactual", scope: "initial_household_with_selected_profiles", failed, criterionID, dependencyIDs, baseline: MinimizedSnapshot, controlledRetest?: MinimizedSnapshot, comparison?: StressRetestComparison }` |

`queryRoutes` exposes **current computed occupant routes**, including committed hazard exclusions. It does not accept model-authored geometry or select arbitrary destinations. Each summary contains optional personID/primary/alternative, alternativeStatus, sharedChokepoints and optional noRouteReason. Paths expose only space/portal/connector ID sequences and verificationNeeded. Coordinates, names and raw native map data do not leave the host. Local general route requests remain available through `SessionToolRequest.routeRequest`; adding those arguments to the cloud contract requires another reviewed schema slice.

`runCounterfactual` executes selected profiles from the immutable initial household, using existing Swift `PlanStressTester`. It does not replay the current exercise prefix and does not claim a controlled intervention comparison unless the host actually computes one. Its separate baseline snapshot is hypothetical. The envelope snapshot/digest still identify the unchanged current session.

Execute each request with `SimulationSession.executeTool`, using its bound baseRevision. `services/ai-orchestrator/scripts/director-tools.ts` is an executable integration example and minimizer, not a substitute for native consent controls. For all non-preview tools, the envelope snapshot/digest must exactly match the request context, and `observation.kind` must match the pending tool. Mismatches leave the valid continuation token available for correction. Unknown fields and raw host responses are rejected.

The gateway permits at most six provider turns per operation including one bounded repair; the normal path uses four: up to two optional investigations, one candidate preview, one final proposal. On the third turn it offers only the preview tool if none has been run; after a preview it disables further model-selected tool calls. After a final proposal with choices it emits the mandatory gateway-owned validateSuggestedActions request; this is not a model call or optional investigation. Each full sequence is previewed independently after the director boundary on a Core-owned copy. Invalid wording and action sequences share one repair opportunity. Only a completed result may be presented or committed; source state stays unchanged throughout validation. Old native clients without this tool must pause safely rather than render pending choices. A final proposal requires an actual completed preview, rather than an inspection alone. Provider latency never advances simulation time. Exhaustion pauses safely with the same session.

Run:

```sh
pnpm --dir services/ai-orchestrator test
pnpm --dir services/ai-orchestrator exec tsx scripts/director-tools-eval.ts
DRYRUN_LIVE_TOOLS=1 pnpm --dir services/ai-orchestrator exec tsx scripts/director-tools-eval.ts
```

The offline evaluation executes all six tools against the running Swift NDJSON host, verifies read-only behavior, drives a deterministic provider through two continuations, commits and verifies replay. The live variant uses Gemini with the same synthetic household and records a separate artifact. These checks do not establish native integration or exhaustive live tool selection coverage.

The later [policy and actions slice](director-policy-and-actions.md) adds applied spatial batch previews, required command fields, one bounded tool repair, policy/runtime context and wait predicates. A spatial schedule alone is rejected as an unapplied preview.

Controlled preparation plans are specified in [stress-retest.md](stress-retest.md). They execute existing validated user actions only inside a separate initial-state copy before the same external schedule. The optional typed comparison retains remaining requirements and unknowns; it never resolves real tasks or modifies the current exercise.

The exact fire failure/repair regression is `scripts/compound-suggestion-eval.ts` and `fixtures/ai/compound-suggestion-evaluation.json` (actual retained live failure, explicitly synthetic repair, no live calls). `suggestionValidationArgs-v1.schema.json` and `suggestionValidation-v1.schema.json` define the added phase. The Core commit guard repeats validation before persistence; never silently reorder commands or pre-execute a suggested choice.
