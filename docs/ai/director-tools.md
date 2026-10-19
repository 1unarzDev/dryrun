# Director read-only tool continuation, v1

Revisit reference section 10 when integrating this seam. `services/ai-orchestrator/src/contracts.ts` is the strict wire contract; generated continuation JSON schema lives in `content/ai/contracts`. The same revision/event sequence/context/household/home binding and one-use token protect every tool. No result writes facts or commits an exercise action.

| Function | Arguments | Minimized response beyond binding/snapshot/contextDigest |
| --- | --- | --- |
| evaluateCandidateAction | `{ "command": { "kind": "advance", "minute": 120 } }` | Hypothetical preview snapshot/digest; omit observation |
| inspectScene | `{}` | `observation: { kind: "inspectScene", scene?: HomeSceneContext }` |
| queryRoutes | `{}` | `observation: { kind: "queryRoutes", routes: [...] }` |
| evaluateResources | `{}` | `observation: { kind: "evaluateResources" }`; current balances/unknowns are in snapshot |
| inspectDependencies | `{}` | `observation: { kind: "inspectDependencies", dependencies: [...] }` |
| runCounterfactual | `{ "profileIDs": ["supplied-reviewed-profile-id"] }` | `observation: { kind: "runCounterfactual", scope: "initial_household_with_selected_profiles", failed, criterionID, dependencyIDs, baseline: MinimizedSnapshot }` |

`queryRoutes` exposes **current computed occupant routes**, including committed hazard exclusions. It does not accept model-authored geometry or select arbitrary destinations. Each summary contains optional personID/primary/alternative, alternativeStatus, sharedChokepoints and optional noRouteReason. Paths expose only space/portal/connector ID sequences and verificationNeeded. Coordinates, names and raw native map data do not leave the host. Local general route requests remain available through `SessionToolRequest.routeRequest`; adding those arguments to the cloud contract requires another reviewed schema slice.

`runCounterfactual` executes selected profiles from the immutable initial household, using existing Swift `PlanStressTester`. It does not replay the current exercise prefix and does not claim a controlled intervention comparison unless the host actually computes one. Its separate baseline snapshot is hypothetical. The envelope snapshot/digest still identify the unchanged current session.

Execute each request with `SimulationSession.executeTool`, using its bound baseRevision. `services/ai-orchestrator/scripts/director-tools.ts` is an executable integration example and minimizer, not a substitute for native consent controls. For all non-preview tools, the envelope snapshot/digest must exactly match the request context, and `observation.kind` must match the pending tool. Mismatches leave the valid continuation token available for correction. Unknown fields and raw host responses are rejected.

The gateway permits at most four provider turns per operation: up to two optional investigations, one candidate preview, one final proposal. On the third turn it offers only the preview tool if none has been run; after a preview it disables further tool calls. A final proposal requires an actual completed preview, rather than an inspection alone. Provider latency never advances simulation time. Exhaustion pauses safely with the same session.

Run:

```sh
pnpm --dir services/ai-orchestrator test
pnpm --dir services/ai-orchestrator exec tsx scripts/director-tools-eval.ts
DRYRUN_LIVE_TOOLS=1 pnpm --dir services/ai-orchestrator exec tsx scripts/director-tools-eval.ts
```

The offline evaluation executes all six tools against the running Swift NDJSON host, verifies read-only behavior, drives a deterministic provider through two continuations, commits and verifies replay. The live variant uses Gemini with the same synthetic household and records a separate artifact. These checks do not establish native integration or exhaustive live tool selection coverage.
