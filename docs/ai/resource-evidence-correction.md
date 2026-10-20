# Resource service evidence and useful repair — 2026-10-20

This extends the existing provider boundary and handoff. It does not replace the six-scenario goal or establish fresh live research quality. No new live-model calls were made.

## Observed failure and cause

The retained `groq-albuquerque-extraction-v5-live.json` contains actual20B extraction from actual120B browser evidence. Its accepted clinic option described general pharmacy services and public-transit accessibility although its selected passages established only the clinic's name/contact/hours. The `documentedService` was simply `Pharmacy`, copied from the organization name. Genuine source IDs did not establish the asserted activity or suitability.

A deterministic replay through `GroqResourceDiscovery.formatEvidence` reproduced publication of that unsupported option. A second minimized test showed that a category word occurring only in the facility name passed source binding. The original red outputs are `/tmp/dryrun-research-claims-red.log` and `/tmp/dryrun-research-minimal-red.log`.

The host also sent only generic “validation failed” instructions on its permitted repair: no rejected structured candidate or specific error. That encouraged repetition rather than a focused correction.

## Code correction

- `src/discovery-evidence.ts` rejects identity-only category/service text, returning `unsupported_research_service_description`. Actual independent service or contact/hour excerpts remain usable. Existing per-source/per-record binding still prevents borrowing another directory listing's service; no directory scopes were merged.
- `src/groq-discovery.ts` extraction policy7 explains that names do not establish activities. A real named program heading may identify the option; the model must not invent a composite facility name by joining an organization and service label. For AHCH, `Increasing Access to Prescriptions` and its substantive prescription excerpt are actually in one source scope.
- The existing single repair now receives the rejected schema-valid candidate plus the exact option-specific validation errors, alongside unchanged public brief/passages. Previous claims remain untrusted. No hidden reasoning, private planner context, task ID, or new evidence is forwarded. The operation's generation, deadline, quota, output cap and one-repair budget are unchanged.
- The model can still reason freely about public needs and propose specific checks. It is not confined to a task catalog. A contact-only lead must remain a lead rather than becoming a clinical service claim.

## Runnable evidence

From the repository root:

```bash
pnpm --dir services/ai-orchestrator exec vitest run test/discovery-evidence.test.ts test/groq.test.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/research-service-evidence-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/groq-discovery-replay.ts
```

The new evaluation is included in `scripts/verify-ai-portable.sh`. It rejects both actual retained bad extraction attempts without erasing the browser evidence. It then tests one **authored synthetic** repair on those same passages: an actual named prescription program tied to the brief's budget issue, and an explicitly contact-only clinic lead. Both retain transport, current opening/stock and personal eligibility unknowns. Original retrieval/expiry are unchanged; replay freezes the original clock rather than making expired information current.

`fixtures/ai/research-service-identity-repair.json` marks the correction synthetic and not live-model-verified. `artifacts/ai/resource-service-evidence/report.json` records the original errors, qualified repaired options, actual provider/model provenance, one repair/two synthetic transport turns per operation, and zero new provider calls. The older actual120B three-option Albuquerque extraction still revalidates without another search.

Current verification: gateway **203 tests /24 files passed**, TypeScript passed, both replay evaluations passed. Core/native code did not change in this slice; their preceding verification remains as recorded in [scenario experience handoff](scenario-experience-handoff.md).

## Limits and Mac continuation

**Linux-tested:** identity/service separation, source-record isolation, exact repair feedback, bounded operations, attribution/timestamps, actual bad-response replay and useful synthetic repair. **Live-model-tested:** original search/extraction failures only; no fresh live repair or search was run here. **Synthetic-only:** repaired response, private development data and replay transport. **Native-pending:** actual task/resource companion, MapKit matching, refresh/expiry and iPhone behavior. **Human-review-pending:** usefulness and semantic correctness of all reasoning clauses, content/accessibility/manufacturer boundaries and family usability.

This check is not a semantic entailment verifier for arbitrary `whyUseful`, `nextAction`, comparison or raw research-answer prose. A different unsupported paragraph paired with a substantive service quote could still require rejection on review. Do not promote the retained original assistant answer into verified facts or reuse stale evidence as current activation/stock/travel information. Fresh end-to-end usefulness under injected Gemini429 remains open, as do Gemini's own normalized-claim quality checks; this correction specifically exercises the Groq extraction path.

Claude should retain the same gateway/public-research separation, show the actual named program/service or qualified contact lead, preserve consequential unknowns, and avoid claiming a feasible transit approach from a city/address/name alone. No user location-record curation or provider chooser is needed. If a later live budget is available, evaluate whether policy7 actually produces the grounded alternative without a synthetic response; do not count this fixture as that pass.
