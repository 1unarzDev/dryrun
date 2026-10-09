# Adversarial security review: regional agent and `/v1/regions/:id/brief`

Reviewer: Agent A. I did not edit any `src` files. Scope: `services/public-api/src/agent/**` and the brief route in `src/app.ts:121-130`.
Probes: `services/public-api/test/agent-adversarial.test.ts` (23 tests). Confirmed defects use `it.fails`: each asserts the secure
behaviour and currently fails. When a fix lands, vitest reports an unexpected pass; switch that probe to `it` at that point. I checked
that all 10 fail on their security assertion, not on a setup error, by temporarily running them as normal tests.
Run: `cd services/public-api && pnpm test` → `Tests 56 passed | 10 expected fail (66)`.

**Exposure context:** `runRegionalAgent`, `fetchOfficialSource` and `validateModelProposals` are **not wired to any route** yet. They
are library code. No model provider is configured (`UnavailableProvider`). The brief route makes no upstream fetch. The severities
below assume the agent will be deployed; today the reachable surface is the brief route only.

## Confirmed defects

| # | Severity (once wired) | Where | Scenario | Fix |
|---|---|---|---|---|
| 1 | **High** | `src/agent/model.ts:196-198` | For `summary` proposals only the `quote` must be verbatim; the summary **value** is free prose. The model can attach invented text ("Cooling center staffed 24 hours with free rides") to a trivial quote ("Erath"). The instruction/activation filters run only on the value and are bypassed by homoglyphs (Cyrillic "о" in "оpen") or by words not in the list ("accepts pets"). The result is accepted as a `modelSummarizedVerbatimChecked` claim, a label that overstates its evidence. | Require the value itself to be verbatim (or a normalised substring of the quote), with a minimum quote length (e.g. ≥ 40 characters). Normalise with NFKC and reject non-ASCII lookalike letters before filtering. Better: drop free-text `summary` until review tooling exists. |
| 2 | **Medium–High** | `src/agent/model.ts:195-199` | `phone`/`date` proposals are checked only for being verbatim somewhere in the source, never for **format**. An injected page containing "The shelter at 1 Fake St is OPEN" lets the model submit that sentence as `claimType: "phone"`, which skips the activation filter (that filter applies only to summaries). | Validate model `phone`/`date` values with the same regexes as `extract.ts`, so a model proposal can only re-confirm a pattern-shaped value. |
| 3 | **Medium** | `src/agent/fetchSource.ts:22` | The allowlist rejects http, userinfo and ports, but accepts **IP-literal and internal hosts** (`https://169.254.169.254/…`, `https://[::1]/`, `metadata.google.internal`). The manifest is curated, but this is the last line of defence if a bad entry is committed. | Reject IPv4/IPv6 literals, `localhost`, `*.local`, `*.internal`, and single-label hosts. Optionally pin to an explicit list of official domains (`*.tx.us`, `*.gov`, `211texas.org`, …). |
| 4 | **Medium** | `src/agent/fetchSource.ts:76` (redirect loop) | Redirect checks compare only the scheme and `hostname`. A same-host redirect to **another port** (`https://www.co.erath.tx.us:8443/admin`) or one carrying **userinfo** is followed. | On every hop, enforce `url.port === ""`, no `username`/`password`, and `url.origin === originalOrigin`. |
| 5 | **Medium** | `src/agent/extract.ts:113` | Deterministic URL extraction accepts any `https://` URL in page text, including `https://169.254.169.254/latest` and `https://localhost/x`. The model path has `isPublicHTTPS`; this path does not. If claims are later shown as links, an injected page can plant internal or phishing URLs. | Apply the shared public-URL check (fixed as in #6) to extracted URLs; consider also requiring an allowlisted official domain. |
| 6 | **Low–Medium** | `src/agent/model.ts:182` (`isPublicHTTPS`) | Accepts `https://localhost./admin` (trailing-dot FQDN), and any other non-IP internal name not ending in `.local`/`.internal`. | Strip a trailing dot before testing; reject single-label hosts and reserved TLDs (`.localhost`, `.home.arpa`, `.lan`). |
| 7 | **Low** | `src/agent/fetchSource.ts:39` (`htmlToText`) | A `<script>` with no closing tag is not removed. Only the tag is stripped, so script text (`var hotline='254-555-0100'; location='https://evil.example/'`) becomes "page text" and feeds extraction. Hidden text (`display:none`, `aria-hidden`) is kept the same way. | Drop everything from an unclosed `<script`/`<style` to the end of the document. Long term, use a real HTML parser and skip hidden nodes. |
| 8 | **Low** | `src/agent/fetchSource.ts:94` | The content-type check is a prefix match: `text/htmlx` and `text/plain-javascript` are accepted. | Parse the media type and require an exact `text/html` or `text/plain` (parameters allowed). |
| 9 | **Low** (reachable today) | `src/agent/brief.ts:25-26` | `alertEnrollment` becomes `officialPageMentionsSignUp` whenever the office summary contains "alert" or "sign up", even "This office does not operate an alert system". The brief then implies a sign-up exists. | Infer this only from an explicit `alertEnrollment` resource; otherwise return `unknown`. |

## Probed and holding

- **Source IDs only:** the agent's fetch tool accepts source IDs, never URLs. http, userinfo and ports in manifest entries are rejected. A same-host http downgrade is refused. Redirect hops are capped at 3 fetches.
- **Slow and huge bodies:** a body that never finishes is cut off by the single headers+body deadline. An oversized chunked body with no content-length is refused by the byte cap.
- **Model proposals:** proposals citing a source that was **not fetched** are rejected. Instruction-like summaries ("should evacuate"), verbatim "OPEN" summaries, and IP-literal URLs are rejected. Every claim, deterministic or model, stays `needsReview`.
- **Brief route:**
  - `..`, `%2e%2e%2f`, `__proto__`, `constructor`, NUL, and extra path segments all give ≥ 400.
  - Any query (`?alias=CANARY&address=…`) gives 400. POST gives 405. A non-zero content-length gives 400.
  - A household-like request header is not echoed back.
  - With no cached alerts the brief says `unavailable`. Expired or demo alerts inside the freshness window are never `current`.
  - `siteActivation` stays `unknown` without a sourced, unexpired active site.
- **Household data:** there is no route, parameter or body through which household-like fields can enter, and nothing logs request details (`app.ts:151`).

## Assumptions and residual risk (not testable here)

- **DNS rebinding / internal resolution:** host allowlisting works on names. Safety depends on the Workers runtime not reaching private address space. Keep the allowlist to public official domains (fix #3) and do not run this fetcher on a host that can reach internal networks.
- **Prompt construction (`model.ts:163-172`):** source text is delimited and `<source>` tags are stripped, but delimiter spoofing with Unicode lookalikes is still possible. Validation (fixes #1 and #2) is the real control, not the prompt.
- **Brief caching (`app.ts:128`):** the brief is served `public, max-age=300` while alert status comes from an in-isolate cache. An alert that expires inside that window can be shown as `current` for up to 5 minutes. Consider `max-age` ≤ 60 or `no-store` whenever `officialAlerts.status == "current"`.
- **Pack-level `expiresAt`:** `buildRegionBrief` ignores it. A curated pack that has expired as a whole can still yield `siteActivation: confirmed` if an individual resource's `expiresAt` is in the future.
