# Gemini provider verification

Fetched official pages and npm metadata over HTTPS on **2026-10-19**, approximately **05:49–05:55 UTC**. This note verifies published interfaces and terms; it does not establish account access, model quality, legal release approval, or device behavior. No credentials or real household data were used. Research follows the repository reference, sections 5, 8, 13, and 16.

## SDK and protocol

- Official npm registry reports **`@google/genai` 2.30.0**, Node **>=20.0.0**. Its published declaration file was inspected directly from the registry tarball. Pin the exact installed version in the lockfile and evaluation records. Sources: [registry metadata](https://registry.npmjs.org/@google/genai/latest), [2.30.0 tarball](https://registry.npmjs.org/@google/genai/-/genai-2.30.0.tgz), [official SDK repository](https://github.com/googleapis/js-genai).
- Official documentation now calls **Interactions generally available since June 2026 and recommended for new work**; `generateContent` remains supported. Interactions defaults to **`store:true`**. Use explicit **`store:false` on every private call**, full local bounded history, no `previous_interaction_id`, and no background execution. Published default stored retention is 55 days paid / 1 day free; `store:false` is a storage control, **not a promise of zero provider abuse retention**. [Interactions overview](https://ai.google.dev/gemini-api/docs/interactions-overview)
- Interactions uses `interaction.steps`, `function_call` with `id`, `name`, `arguments`, and `function_result` with **`call_id`** matching that ID. Preserve **all returned steps**, including opaque `thought.signature` fields, in order. The official stateless example appends `...interaction.steps` to its input history before appending results. Re-send tools, system instruction, and generation configuration each continuation. [Function calling, stateless example](https://ai.google.dev/gemini-api/docs/function-calling), SDK `FunctionCallStep`, `FunctionResultStep`, `ThoughtStep`, `CreateModelInteraction` declarations.

Verified Interactions shape (protocol illustration; host must validate calls and results):

```ts
const history: interactions.Step[] = [{
  type: 'user_input',
  content: [{ type: 'text', text: syntheticContext }],
}];
const first = await ai.interactions.create({
  model, store: false, input: history, tools,
  system_instruction: instruction,
});
history.push(...first.steps);
// For each authorized function_call, execute the validated host tool.
history.push({
  type: 'function_result', name: call.name, call_id: call.id,
  result: [{ type: 'text', text: JSON.stringify(validatedHostResult) }],
});
const next = await ai.interactions.create({
  model, store: false, input: history, tools,
  system_instruction: instruction,
});
```

`generateContent` is a different wire protocol: `Content[]`, full `candidates[0].content` with ordered `Part[]`, `functionCall`, `functionResponse: {id, name, response}`, and `Part.thoughtSignature`. Preserve whole model content rather than reconstructing it from the convenience `functionCalls` getter; never translate Interactions steps into these parts by guessing. Structured output still requires application-level semantic validation. [Function calling](https://ai.google.dev/gemini-api/docs/function-calling), [structured output](https://ai.google.dev/gemini-api/docs/structured-output).

## Model candidates and published price

Standard paid rates, USD per million tokens; output includes thinking. These are published candidates, **not an account-specific availability check or a quality recommendation**. [Model catalog](https://ai.google.dev/gemini-api/docs/models), [pricing](https://ai.google.dev/gemini-api/docs/pricing).

| Model ID | Input text/image/video | Output | Use to evaluate |
|---|---:|---:|---|
| `gemini-3.1-flash-lite` | $0.25 | $1.50 | Economical routine roles; audio input $0.50 |
| `gemini-3.5-flash-lite` | $0.30 | $2.50 | Newer economical routine candidate; same input rate for audio |
| `gemini-3.8-flash` | $0.75 | $3.75 | Stronger inspection/director/adjudication candidate |

The 3.8 Flash rates above expire December 31, 2026; published January 1, 2027 rates are $1.50 input / $7.50 output. The catalog also lists `gemini-2.5-flash-lite`; avoid assuming an older default is best without fixture evaluation. Log actual `usage` from calls and compute costs from the selected dated price schedule; do not infer cost from HTTP count alone. No live model was invoked for this research.

## Privacy, audience, and map deployment

- Developers must be **18+**; API clients must not be directed toward, or likely accessed by, under-18s. The owner's reported age meets the developer requirement but does not resolve DryRun's family audience. Record a release-fit decision before private production use; parental consent alone is not an exception stated in these terms. [Gemini API terms, Age Requirements](https://ai.google.dev/gemini-api/terms)
- Unpaid terms say **not to submit sensitive, confidential, or personal information** and permit product improvement/human review. Paid prompts/responses are not used for product improvement under the stated paid terms, but abuse/security/legal logging remains. Verify actual billing/project configuration before accepting private household data. Cloud/Vertex terms require a separate assessment; switching endpoints does not establish compliance. [Gemini API terms, Unpaid and Paid Services](https://ai.google.dev/gemini-api/terms)
- Apple requires clear disclosure of third-party AI sharing and explicit permission before personal-data sharing. Native integration needs cloud opt-in and separate understandable room-photo review, while keeping manual use useful. [App Review Guidelines 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/)
- Google Places content shown on a map must be shown on a **Google Map**, with required attribution; caching/storage has limited exceptions. Do not put Places-derived markers on DryRun's MapKit map. Native MapKit results and independently obtained official records can use their own supported provenance. [Places policies](https://developers.google.com/maps/documentation/places/web-service/policies)
- Google Search/Maps grounding has additional display, attribution, retention, and reuse restrictions. Grounding output must not be treated as unrestricted public records or cached as ordinary domain evidence. Avoid those built-ins by default in the MapKit flow; use reviewed independent official-source evidence and the native search contract. [Gemini terms, Grounding sections](https://ai.google.dev/gemini-api/terms), [Maps grounding](https://ai.google.dev/gemini-api/docs/maps-grounding)

## Remaining verification

Implementation must test the **actually installed** SDK against its declarations and protocol fixtures, then run synthetic live stateless continuations, refusal/timeout/repair, multiple calls, cancellation, bounded history disposal, role quality, and usage accounting. Published model listings do not prove a particular key can use a model. Private deployment configuration, audience/terms review, native consent, App Attest/Keychain, image capture/deletion, MapKit attribution, and real-device lifecycle remain separate gates.
