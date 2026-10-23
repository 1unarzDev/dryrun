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
