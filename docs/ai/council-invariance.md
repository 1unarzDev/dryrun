# Development consistency probe

Reference §13D asks for ordering, language/wording, identity cues and cost-description checks. `scripts/council-invariance-eval.ts` holds one existing development case's accepted predicate facts and frozen rubric constant across eight variants: base, reversed evidence/criterion order, longer wording, Spanish wording, Vietnamese wording, Gemini proposer cue, other-model proposer cue, and a low-cost description. No holdout case was used. Variants are not independent households and there is one run per variant; earlier three-household × three-repeat results remain separate.

Actual live synthetic result: 32 Gemini calls, estimated token cost $0.06329825 under the configured rates. Raw council criterion agreement ranges from 42.86% to 78.57%. Eight raw critical false passes occur across the eight variants (counts are correlated observations, not household risk estimates). Reversed order and identity cues coincide with changes, but this tiny uncontrolled probe cannot attribute causal bias, statistical significance or self-preference. It does establish that raw model assessments must not grant points or resolve facts by vote.

All eight host-reconciled accepted assessments match the policy-authored development reference, and the deterministic score is exactly unchanged. This reflects host enforcement of already accepted predicates, not independent correctness of the council or human validation. The full output, each variant's result, usage and latency are retained in `fixtures/ai/council-invariance.json`; progress is retained separately.

Spanish/Vietnamese variation changes evidence wording notes; it is **not** a full translation of the rubric, prompts or household interview, and does not establish localized product quality. Real names are excluded from the minimized context schema. Raw photo-versus-typed assessment is not run here because the council takes accepted host predicates, not photos; image interpretation must remain a separate review step. Qualified human references, more independent households, full language equivalence and further photo/intake comparisons remain pending.

Run sequentially with other live suites to respect development provider limits:

```sh
pnpm --dir services/ai-orchestrator exec tsx scripts/council-invariance-eval.ts
```

Do not tune against the locked holdout. Any review-driven policy/prompt change requires a version and new held-out evidence before making a held-out quality claim.
