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

Mac/iPhone checks remain pending: show one contextual “try this change” interaction, describe its simulation-only scope, compare resource/time/route outcomes without claiming full resolution, confirm real quantities/locations stay fixed, test cancel/background/replay and source changes mid-request, and verify no new navigation surface. No fresh live Gemini or human safety/usability review is claimed for this slice.
