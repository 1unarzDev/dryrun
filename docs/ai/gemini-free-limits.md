# Gemini free limits: practical options for DryRun

Researched 2026-10-19 against Google's current documentation. No account, project, billing, or secret changes were made. Account-specific quotas and whether the two authorized keys belong to different projects were not inspected.

## Can the free limit be increased without paying?

Google documents no general self-service increase for the Free API tier. Its increase form is explicitly for paid tiers; upgrades require billing, and higher tiers require spending. Active limits are model/project-specific and should be checked in [AI Studio's rate-limit view](https://aistudio.google.com/rate-limit), rather than assumed from old public tables. Daily request quotas reset at midnight Pacific: currently 2 a.m. Chicago time, changing with daylight saving time. [Google rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)

Quotas belong to the **project, not the API key**. Switching to the authorized backup can help if it has a separate eligible quota pool; another key in the same project does not replenish it. Model quotas differ, so an eligible model with capacity may still work. This is capacity recovery within existing entitlements, not a promise of unlimited free access. [Google rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)

## Why generation can work while nearby-resource research fails

The current pricing page lists ordinary Gemini 3.1 Flash-Lite generation as free, but **Search grounding is unavailable on its Free API tier**, as on 3.8 Flash. The footnote permits testing in AI Studio. Paid-tier free Search allowances do not make model inference free. Thus repeated Search 429s may reflect feature eligibility rather than a consumed daily allowance; actual error details/account limits must decide. [Google pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-3.1-flash-lite)

Google currently lists Gemini 2.5 Flash/Flash-Lite Search grounding at up to 500 free requests/day **shared across those models**. This is a possible research-only alternative if still supported for the account and required API; it is not a verified DryRun result or an automatic substitution for the required provider contract. [Google pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-2.5-flash)

URL Context consumes input tokens for fetched pages; it is not free extra context capacity or web discovery by itself. It accepts up to 20 URLs/request and 34 MB/page, with public-page/content restrictions. Its documentation does not supply a universal separate free daily quota. [URL Context](https://ai.google.dev/gemini-api/docs/url-context)

### Conditional 2.5 research role: compatibility and availability

The [Interactions overview](https://ai.google.dev/gemini-api/docs/interactions-overview#supported-models--agents) lists `gemini-2.5-flash` and `gemini-2.5-flash-lite`, with JavaScript SDK support from 2.3.0. Installed `@google/genai` 2.30.0's declarations include both model IDs. The [Search guide](https://ai.google.dev/gemini-api/docs/google-search#supported-models) and [URL Context guide](https://ai.google.dev/gemini-api/docs/url-context#supported-models) list 2.5 support and permit combining these two built-in tools. Their combined Interactions examples use 3.8, so this is documented compatibility, not a successful live 2.5 joint-tool test in DryRun.

**Availability is conditional:** Google's current [deprecation notice](https://ai.google.dev/gemini-api/docs/deprecations#gemini-2.5-flash-models) says 2.5 Flash/Flash-Lite have no announced shutdown date and are not deprecated, but access is restricted to users who actively used them previously. New projects are directed to 3.5 Flash-Lite/3.8 Flash. A bounded research-only compatibility probe may therefore be useful for a previously eligible account; this cannot be promised as a free solution for either authorized key. Retain the modern director model and explicit provider/usage provenance if such a probe succeeds.

## Read the failure before switching keys

| Failure | Meaning and useful response |
|---|---|
| 429 / resource exhausted | Identify the exhausted metric/model/project or unavailable feature. Respect any retry timing. A minute limit needs spacing; a daily limit needs reset; a zero entitlement needs a supported alternative. |
| 503 / service unavailable | Google's service is temporarily overloaded or down. It does **not** establish that either key is full. Back off, retry later, or use an eligible supported model. |
| Timeout | The request exceeded a deadline. Check latency/context and preserve unknown-outcome accounting; do not classify it as depleted quota. |

Google's [API errors](https://ai.google.dev/gemini-api/docs/api-errors) distinguish these cases. Its [troubleshooting guide](https://ai.google.dev/gemini-api/docs/troubleshooting) recommends bounded exponential backoff with jitter for transient errors. Application-level and SDK retries must not multiply blindly. For DryRun, retain full thinking for substantive decisions; reduce repeated context and unnecessary calls before reducing reasoning quality. That final sentence is an implementation recommendation, not a Google quota guarantee.

## Credits and programs: avoid accidental spending

- **The $300 Cloud welcome/free-trial credit is not a current Gemini API workaround.** Google excludes Gemini API/AI Studio usage from that program starting March 2026. Eligible older credits expire after 90 days. Prepay users must purchase credits before eligible Cloud credits can apply. Enabling billing is therefore not a no-spend solution. [Gemini billing FAQ](https://ai.google.dev/gemini-api/docs/billing)
- **Existing subscription benefits may be useful, but are conditional.** Google lists $10/month GenAI/Cloud developer credits with Google AI Pro; the free Standard Developer Program does not include these. If the owner already has an eligible paid or promotional plan, inspect its actual credit terms and billing requirements first. Buying a subscription to obtain them would spend money. [Developer Program comparison](https://developers.google.com/program/plans-and-pricing)
- **Startup grants require eligibility and approval.** Google's AI startup program advertises credits for qualifying funded startups, with discretionary acceptance and partial second-year coverage. It does not guarantee a free Developer API quota increase or a zero-cost account. Confirm the exact service/SKU coverage and billing terms before applying credits. [Google Cloud startup program](https://cloud.google.com/startup/ai)

## Recommended zero-spend workflow

Use the two already authorized keys sequentially when the failure could be project-specific, without exposing either. If both return the same quota/eligibility failure, stop repeated calls. Check each project's active model/tool entitlement in AI Studio; queue daily-quota work until reset, serialize minute-limited evaluations, and preserve accepted synthetic responses for replay. Keep live quality/discovery gates marked failed or pending until actual responses succeed. Do not create projects, enable billing, purchase credits, or assume free Search access from a free generation response.

## Actual authorized-key probes

On 2026-10-19 Chicago time (2026-10-20 03:09 UTC), both authorized keys returned **HTTP 404** for the bounded `gemini-2.5-flash` joint-tool Interactions probe: “This model models/gemini-2.5-flash is no longer available to new users.” The conditional legacy path is therefore unavailable for these keys. This result is distinct from quota exhaustion or an unsupported-tool assertion. The backup did accept ordinary preparation generation in the same period; neither key should be described simply as universally “full.” Modern Search-enabled Denver/Marfa calls returned429; the current pricing eligibility restriction remains relevant, but the generic429 alone does not identify its exact account metric.

Reproduce only after a relevant entitlement change: `DRYRUN_USE_BACKUP_KEY=1 pnpm --dir services/ai-orchestrator exec tsx scripts/provider-entitlement-eval.ts`. Safe diagnostic files are under ignored `artifacts/ai/provider-entitlement/`. No billing or account setting was changed.
