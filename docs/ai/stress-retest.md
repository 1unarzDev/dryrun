# Controlled preparation retests

Reference §11 requires executable improvements and the outcome after a controlled retest. `StressRetestPlan` now allows a bounded preparation on a copied initial exercise before the exact same external incident schedule. It uses existing host user-action validation; it cannot mutate the real household, real inventory, current rehearsal or score.

`PlanStressTester.execute(..., retestPlan:)`, `SessionToolRequest.retestPlan` for `runCounterfactual`, and the headless host `stress` operation accept:

```json
{
  "version": "dryrun.stress-retest/1",
  "commands": [
    {"kind":"takeSupply","target":"water","value":"p-oak-1"},
    {"kind":"moveTo","target":"p-oak-1","value":"sp-living"},
    {"kind":"transferSupply","target":"water","value":"sp-living"}
  ]
}
```

The 1–8 commands may be `takeSupply`, `transferSupply`, `moveTo`, `assignHelper`, `closeDoor`, `allocatePower` or `useStoredWater`. Each needs the same recorded identifiers and eligibility as a real host action. No time, duration or hazard fields are allowed. Unknown versions, absent stock, invalid routes/transfers, unowned backups, incident/director commands and empty/oversized plans fail. No hypothetical resource grant or hidden relocation succeeds by narration. Door closing still carries no unvalidated spread-delay credit. A plan can accompany an existing `Intervention`; both remain hypothetical and are retained separately for replay.

The host commits preparation as actor `user` only inside the isolated retest session, before committing the unchanged director schedule at its resulting revision. It does not import the current rehearsal prefix. Preserve `finding.retestPlan`, `retestIntervention`, `schedule` and frozen source to reproduce the comparison; the ordinary baseline receipt is unchanged. Existing sessions with absent/null dependency policy retain their historical output metadata when no new preparation plan is requested.

New controlled findings include `comparison.version = dryrun.stress-comparison/1`, both final minutes, whether both reached the scenario horizon, resolved/remaining/newly unmet requirement IDs, and all remaining retest unknown IDs. This is a final-state comparison, not proof of uninterrupted success: inspect receipt events for earlier depletion/failure times. For example, extending water from 1.25 to 3 days can still leave `req.water` at the final horizon. An unknown is not a pass. Requirements that clear do not complete real tasks or expand a scored robustness envelope.

The strict counterfactual gateway arguments allow optional `retestPlan`; its read-only observation adds optional minimized `controlledRetest` and typed `comparison`. The outer response binding/snapshot/digest still refer to the unchanged current exercise. Supply records, labels, addresses and private provenance are not forwarded. Native callers must implement the whitelist in `scripts/director-tools.ts` and locally resolve IDs for display. Present the proposed improvement and remaining limitations together within existing Plan/debrief, with normal confirmation before any real preparation edit.

Run `pnpm --dir services/ai-orchestrator exec tsx scripts/stress-retest-eval.ts` after building Core. `fixtures/ai/stress-retest.json` is a synthetic protocol fixture: actual Swift simulation and actual gateway validation/continuation, deterministic provider fixture, **zero live model calls**. It contrasts inaccessible kitchen water with stock moved to the living room before the same incident, preserves all five gallons, replays exactly, and completes a separate director proposal without committing the hypothetical move to the current session. It retains unresolved assistance/egress requirements and unknowns. Core tests also verify invalid plans, source preservation, legacy metadata and delayed-but-unresolved water depletion.

Mac/iPhone checks remain pending: show one contextual “try this change” interaction, describe its simulation-only scope, compare resource/time/route outcomes without claiming full resolution, confirm real quantities/locations stay fixed, test cancel/background/replay and source changes mid-request, and verify no new navigation surface. The initial slice used a synthetic provider fixture; the later live follow-up below does not replace human safety/usability review.

## Live model follow-up and bounded rejection

`director/5` adds exact preparation field semantics. The request's optional `initialInventoryItemIDs` is a minimized opaque allowlist from the frozen source inventory ledger, not a list of home objects/annotations or resource balances. Supply retest targets require this allowlist; missing IDs make those supply retests unavailable rather than authorizing guesses. Keep source IDs opaque and exclude labels, notes, physical identity, photos and addresses. Verified supplied item IDs are also eligible evidence citations. Manual/local stress execution does not require a cloud allowlist.

The provider schema adapter now preserves trusted schema descriptions, including the different target/value roles. `transferSupply` puts stock down in the current carrier's recorded room; it does **not** implement person-to-person handoff. Host validation and resource conservation remain authoritative.

When the host rejects a well-shaped counterfactual with `invalidCommand`, the native tool handler may return only the unchanged current envelope and:

```json
{"kind":"runCounterfactual","status":"unavailable","reason":"host_rejected_counterfactual"}
```

This strict alternative has no baseline, failed/pass flag or invented comparison. The model can correct a plan within the existing four-call budget or acknowledge unsupported scope. It still must preview before a final director proposal. Stale source, cancellation and transport failures remain fatal; never translate those into an accepted/repaired comparison. Implement the exact catch/whitelist in `scripts/director-tools.ts`.

`stress-retest-live.json` retains the successful real Gemini 3.1 Flash Lite/SDK 2.30.0 run: three calls, estimated $0.0057935 at base token rates without a cache discount. It generated the stock pickup/move/put-down plan, consumed the actual host comparison (zero versus five accessible gallons, five remaining requirements and seven unknowns), previewed a kitchen incident, and committed a validated director proposal pausing at minute 5. The stock location in the current exercise stays in the kitchen. Its final purpose describes the current incident rather than explaining the entire retest; render the host comparison directly and keep model narration unverified. This single synthetic live case does not prove broad model reliability or family-facing explanation quality.

Development evidence is retained honestly: the first call reversed command roles (estimated $0.001843). The next three calls used the home annotation `an-supplies` as a stock ID, received the new typed rejection and returned a validated current-incident proposal acknowledging unavailable comparison (estimated $0.005909); the harness then failed by accessing an absent baseline rather than asserting a successful comparison. Adding the source allowlist and selecting only actual successful comparisons fixed these paths. The initial full diagnostic was overwritten before unique failure filenames were added; `stress-retest-live-initial-failure.json` is explicitly a summary of observed arguments and usage, not a recovered full raw trace. The second attempt's full trace is `stress-retest-live-rejected-scope.json`. Total across these three development attempts: seven provider calls, estimated $0.0135455. No real household evidence was sent.

Run `pnpm --dir services/ai-orchestrator exec tsx scripts/stress-retest-live.ts` only with server-side synthetic-development credentials; failures now get unique filenames. Run `stress-retest-repair-eval.ts` for the four-turn actual-host synthetic rejection → corrected comparison → preview → validated commit loop, and `stress-retest-replay.ts` for exact offline replay of synthetic and retained live tool results/proposals and unchanged real sources/score. Both offline commands are included in portable verification.
