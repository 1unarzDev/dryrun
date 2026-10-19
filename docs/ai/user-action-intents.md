# Optional submitted text/voice actions

Reference §10 allows one optional “another action” text/voice input inside Rehearse. Keep native scene selection and quick actions. This contract adds interpretation of explicitly submitted input; it is not a chat transcript or permission to update household facts.

`POST /v1/intents` is currently synthetic-only and loopback, using the same private fixture authorization, quota and production fail-closed policy as the gateway. Example request:

```json
{
  "contractVersion":"dryrun.ai/1","requestID":"interpret-1","synthetic":true,
  "submission":{
    "id":"input-1","text":"Use stored water only for drinking and cooking.","inputDigest":"<StableDigest of exact UTF-8 text>",
    "binding":{"sessionID":"exercise-1","revision":1,"eventSequence":3,"contextDigest":"<actual source digest>","householdRevision":4,"homeRevision":2}
  },
  "context":{
    "people":[{"id":"person-1","selected":true}],"rooms":[{"id":"kitchen","use":"kitchen"}],
    "portals":[],"equipment":[],"contacts":[],"supplies":[],"choices":[]
  }
}
```

Return is `{status:"completed", requestID, proposal}`. The `dryrun.user-intent/1` proposal echoes submittedInputID/inputDigest and source binding. It has exactly one of:

- proposed, with 1–3 explicitly submitted user commands;
- needsClarification, with one concise question and no commands;
- unsupported, with no commands.

A clear synthetic request above returns proposed `[{"kind":"useStoredWater","value":"essential"}]`. Room/subject identities must be supplied; the interpreter cannot guess which household member “mom” identifies. Native may resolve a selected person locally, but must not silently choose someone when that changes the action. Unknown or materially ambiguous objects/destinations need one clarification. Voice recognition itself remains native and needs separate iPhone verification. Raw transcripts may contain personal information; only send the deliberately submitted text after cloud consent, minimize context and retain no transcript in the event-sourced session. Production private-data/provider-audience gates still apply.

User commands include moveTo, takeSupply, transferSupply, assignHelper, allocatePower, closeDoor, choose, contact, useStoredWater and finish. Director commands and resource patches are absent from the schema. The gateway checks referenced IDs against the supplied local catalog. Interpretation makes no claim of success: actual feasibility and resource/access effects come from Core.

Native captures `ActionSubmission(id:text:binding:)` from the source receipt. Input digest uses Core StableDigest over the **exact** UTF-8 text; TypeScript `inputDigest` matches it. It is a non-security replay identity, not authorization. Never trim/change the input after capture. Commit via `UserActionIntent.commit(submission:to:library:persist:)` only after checking the response still belongs to the submitted input. Clarifications do not commit or trigger another director turn; resolve the ambiguity through a new explicitly submitted input. The previous operation cannot silently write its old proposal.

The host validates input identity, source binding, user-only fields, and dry-runs the full command batch. It atomically commits under the input ID. An infeasible batch records only an unsupported attempt with that input ID; no earlier command in that batch leaks through, no unrelated default is selected. A stale/duplicate response or persistence failure publishes no action. Persistence runs outside the infeasibility catch, so even an invalidCommand storage error cannot accidentally become a different user action. The returned `IntentCommitReceipt` distinguishes committed versus unsupportedAttempt and carries the authoritative receipt. Render feedback from that receipt and pass the committed action to the next director turn.

The interpreter has a 30-second operation limit, no tools, at most two provider calls (one repair), finite input/output sizes and a provider spend budget. It discards late results after cancellation. No raw input logging or durable provider history is added. Continuation is the existing director operation after host commit, rather than an interpreter modifying simulation state.

Reproduce:

```sh
pnpm --dir services/ai-orchestrator exec tsx scripts/intent-eval.ts
DRYRUN_LIVE_INTENT=1 pnpm --dir services/ai-orchestrator exec tsx scripts/intent-eval.ts
DRYRUN_REPLAY_INTENT=1 pnpm --dir services/ai-orchestrator exec tsx scripts/intent-eval.ts
```

`user-intent.json` is explicitly a deterministic provider fixture; `user-intent-live.json` records real synthetic Gemini results. Live used three interpretation calls plus three director calls: clear conservation action → Swift commit → dependency inspection → forecast preview → full proposal envelope → advance to minute 360 → actual pause. Ambiguous and impossible inputs returned clarification/unsupported. Both traces replay exactly without Gemini. These three inputs do not establish broad semantic accuracy, multilingual quality or real-family usability. Human review and wired-iPhone checks remain pending; test incorrect interpretations, rapid resubmission, ambiguous identities, compound actions, offline/manual fallback, VoiceOver/voice/text equivalents and no new chat/navigation surface.

`DRYRUN_LIVE_INTENT=1 pnpm --dir services/ai-orchestrator exec tsx scripts/intent-http-eval.ts` starts an actual loopback gateway with a fresh transient fixture credential. Its retained synthetic HTTP result passed live interpretation plus unauthorized, duplicate-request and non-synthetic rejection checks. The fixture stores no credential.
