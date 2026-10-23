# Beacon performance: measurements and the path to zero visible wait

Owner track: measure (scripts/perf/**, services/ai-orchestrator/scripts/beacon-latency.ts, this file).

## How to measure

```
scripts/perf/beacon-latency.sh 3                       # all roles, 3 runs each, Codex-first chain
scripts/perf/beacon-latency.sh 3 preparation,debrief   # subset
scripts/perf/beacon-latency.sh 3 director --gemini     # Gemini-first chain for comparison
```

The script starts its own gateway on 127.0.0.1:8792 (refuses 8788, the owner's gateway), sends synthetic
fictional-household requests from `fixtures/ai/native-bridge` (preparation fixtures for oak/lake/pine reused as
debrief/resources contexts; director home-fire/water-outage with recorded host tool results for continues), and
writes only timing, HTTP status, status/reason/servedBy machine codes and tool-call counts. Gateway logs and the
probe's stdout go to `scripts/review/firewall.py capture`; response bodies are parsed in memory for allowlisted
codes and dropped. Columns: `total` is request start to last body byte; `TTFB` is time to response headers. The
gateway writes JSON once the provider finishes, so TTFB is currently roughly equal to total: nothing streams.
`director_operation` is the whole start plus continues loop (one Beacon moment as the app experiences it).
`tool rounds` counts model-issued client tool calls before the director produced its proposal; each round is a
full round trip phone to Mac to Codex.

## Baseline

<!-- latency:begin -->
(pending)
<!-- latency:end -->

Reading the table: every Beacon role is one blocking request whose latency is model thinking plus tool round
trips. The table above is the floor the user sees today when nothing is prefetched. `resources` returning in
milliseconds with no `servedBy` means the host answered it deterministically for these fixtures (no
provider call), which is the shape every other role should reach on the visible path.

## Where the time goes (code facts, not measurements)

- Each Codex operation launches a fresh `codex app-server --stdio` process, sends `initialize` and `thread/start`
  with the full instruction and tool list, then the turn (`src/codex-provider.ts`, `launchCodex`). Process start
  plus handshake is paid on every request; nothing is kept warm between operations.
- `thread/start` sets no reasoning effort or service tier, so every role runs at the model default effort.
- The director is a multi-round loop: each model-issued tool call is a full phone to Mac to Codex round trip
  (`v1/operations` then `v1/continue` per call, up to the operation bound). `tool rounds` in the table counts them.
- The gateway writes the JSON body only when the provider finishes (`src/http.ts`), so TTFB equals total; the app
  cannot show partial progress.
- The app requests Beacon work when a screen needs it (Prepare card, director turn, debrief, practice step);
  there is no background prefetch keyed on the household revision.

## Ideas for zero visible wait, ranked

Ranked by expected visible-wait removed per unit of effort. "Gain" is relative to the baseline table above.

| # | Idea | Expected gain | Cost / risk | Owner track |
|---|---|---|---|---|
| 1 | **Deterministic first paint, then upgrade.** Every Beacon surface renders the Core/offline result immediately (Prepare tasks, debrief from the host receipt, practice from the fixed catalog) and swaps in the validated AI result when it lands, with a "Beacon is refining" indicator. Core already owns the fallback, so this is wiring, not new logic. | Visible wait goes to 0 on every surface regardless of model latency; AI latency becomes invisible quality upgrade time. | Low. Must avoid layout jumps (reserve height) and never replace text the user is reading mid-interaction. | beacon-ux + practice |
| 2 | **Background prefetch on household load and app foreground.** When the household revision or home changes, or the app comes to foreground, queue preparation, debrief-for-last-run, and the next practice session in the background; cache by `(role, householdRevision, homeRevision, contextDigest)`. After a practice session completes, immediately generate the next set. | Removes the full p50 of preparation/practice from the visible path for the common case (user opens a tab after the app has been open more than one p50). | Medium. Needs a small request queue with concurrency 2-3 and cancellation when the revision changes; quota counters already exist on the gateway. | practice (practice), beacon-ux (Prepare/debrief) |
| 3 | **Plan all branches in one call.** Practice and director decisions have a fixed option set; ask once for the whole decision tree (every option's consequence, follow-up and coaching line) as one structured output, validated by the host, then serve each step locally. | Per-step latency drops from a network+model round trip to 0; total model time is one call instead of N. | Medium. Larger structured schema; host validation per branch; a single failure falls back to deterministic for the whole session. | practice |
| 4 | **Speculative next director moment.** While the user reads the current moment, start the director operation for the most likely next action (or all offered actions, they are bounded) and keep results keyed by the committed action and binding digest; discard on mismatch. | Director turn wait goes from p50 `director_operation` to near 0 when the user picks a pre-computed action. | Medium-high: extra calls (bounded by offered actions, typically 2-4); Core binding check already rejects stale proposals, so correctness is preserved. | speed + beacon-ux |
| 5 | **Per-role effort and tier.** Pass low reasoning effort (and the fast service tier where the profile allows) on `thread/start`/`turn/start` for practice, director and debrief; keep higher effort only for preparation's background run. | Typically 30-60 percent off model time on short structured outputs (to be confirmed by rerunning this table). | Low code cost; quality risk is caught by the existing host validation and evals. | speed |
| 6 | **Warm Codex runtime pool.** Keep 1-2 `codex app-server` processes initialized (and optionally a thread pre-started per role instruction) and hand one to the next operation; respawn in the background. | Removes process spawn + `initialize` + `thread/start` from every request (expected hundreds of ms to a few seconds; measure with a no-op role). | Medium: lifecycle and isolation (one operation per runtime, dispose after use to keep ephemeral semantics). | speed |
| 7 | **Context pre-packing to cut tool rounds.** Put the facts the director almost always reads (scene summary, routes, dependencies for the current phase) in the first request instead of making the model call `inspectScene`/`queryRoutes`; keep tools for rare reads. | Each removed tool round saves one full round trip; the table's `tool rounds` column bounds the saving. | Low-medium: larger prompt (watch the 96 kB operation payload cap); context projection must stay minimized. | speed |
| 8 | **Cache keyed by input digest.** Hash the minimized request context per role; if the same digest was served in the last N minutes, return the cached validated proposal (gateway side) or the stored one (app side). Not for practice generation, which should be fresh each session. | Repeat opens of Prepare/debrief become instant; also protects quota. | Low. Cache must be per owner and invalidated by household/home revision. | speed (server), beacon-ux (app) |
| 9 | **Stream progress to the app.** Codex already streams; forward phase events (`thinking`, `reading_context`, `tool:<name>`, `writing`) as NDJSON or chunked status lines before the final JSON, and drive the thinking animation from them. | Does not reduce latency, but perceived wait drops sharply because the user sees work happening; TTFB goes from total to under a second. | Medium: protocol change on `v1/features`/`v1/operations` behind a header so old clients keep the single JSON body. | speed + beacon-ux |
| 10 | **Shorter client timeouts with early fallback.** The app waits up to 95 s on feature requests; with first paint in place, cap the visible wait at a few seconds and let the request finish in the background. | Bounds the worst case (`max total` column) the user can ever see. | Low. Depends on idea 1. | speed (DirectorGatewayClient) |

Suggested order for the hour: 1 and 2 (no visible wait for most paths), 5 (cheap, measurable here), then 3/4.
Rerun `scripts/perf/beacon-latency.sh 3` after each server change and compare the table.
