# Groq Browser Search contract findings

Checked 2026-10-20 UTC. Read the complete implementation reference section 5A. Documentation/source inspection only; no live model call, key access, account change, or implementation edit.

## Supported request and output controls

Groq's current [Browser Search guide](https://console.groq.com/docs/tool-use/built-in-tools/browser-search) supports GPT-OSS 120B/20B through Chat Completions with `tools: [{type: "browser_search"}]`, `tool_choice: "required"`, and `stream: false`. Browsing executes on the provider. Its recommendation is `reasoning_effort: "low"`; greater effort can extend exploration. Search cannot be combined with Structured Outputs.

The [Chat API reference](https://console.groq.com/docs/api-reference#chat-create) documents `citation_options: "enabled"` (default), `include_reasoning: false`, and `max_completion_tokens`. Do not also send `reasoning_format` with `include_reasoning`. `parallel_tool_calls: false` concerns parallel function calls, not an exact internal-browser limit. Neither that Chat request nor the first-party Chat SDK exposes `max_tool_calls`, `max_searches`, `max_opens`, or `include_search_results`. `max_tool_calls` appears in the **Responses response object**; this does not establish a supported Chat request parameter. The generic reference's functions-only tool text conflicts with the dedicated Browser Search examples; use the dedicated documented browser type.

**Budget conclusion:** no exact Chat browser-search/open cap was found in the inspected public contract. A prompt saying “two searches/four opens” is a soft instruction. Keep logical request, deadline, output, and spend reservations as host limits; report internal steps separately when available. Cancellation cannot guarantee that upstream work or charges stopped. Do not claim a request/token limit enforces six internal browsing actions.

## Evidence returned when optional metadata is absent

The Browser Search guide explicitly describes snippets and the final attributed answer in `choices[0].message.content`. Its example shows an ellipsis placeholder for site snippets, then line citations such as `〖2†L6-L10〗`. **It does not publish a complete content-only source block with a resolvable source URL/ID mapping, a guaranteed delimiter, or an authenticity boundary separating tool text from generated text.** A numeric line citation alone cannot identify a URL. [Browser Search final-output example](https://console.groq.com/docs/tool-use/built-in-tools/browser-search#final-output)

Current [first-party TypeScript Chat source](https://github.com/groq/groq-typescript/blob/master/src/resources/chat/completions.ts) declares `message.executed_tools` and `message.annotations` optional. Executed tools can carry `browser_results` with title/URL/optional content, `search_results`, or `output`. Annotations are `document_citation` or `function_citation`; the latter supplies character offsets and `tool_call_id`, **not a source URL**. A function citation must resolve to actual tool evidence. Search settings expose country/domain/image preferences, not browsing-count limits. These optional types do not guarantee those fields on every browser response.

## Recommended safe adapter behavior

These are recommendations derived from section 5A and the contract limits above, not newly documented vendor guarantees:

1. Preserve the original attributed answer even when the source envelope is absent. Separate “request completed,” “retrieval evidenced,” and “claim verified”; missing optional metadata is not automatically proof that search never ran.
2. Prefer validated provider tool-result records. Support the documented `browser_results` alternative as well as observed `search_results`/tool-output snippets. Keep exact URLs and content; assign host source IDs. Record search snippets versus page inspection separately.
3. Accept another content-only source format only after a sanitized actual response establishes its shape and reliable source/citation join. Public docs alone do not justify a regex that promotes arbitrary `URL:` blocks in assistant prose to trusted retrieval. Never derive URLs from citation numbers or guessed paths.
4. If only model-authored links/markers remain, retain an unresolved attributed answer/candidates and use the existing permitted independent retrieval path to verify candidate sources. A successful independent fetch proves that fetch and its supported claims; it does not retroactively prove which Groq searches occurred. Reject unsupported task claims, not every useful partial result.
5. Keep tools-disabled strict extraction separate. Supply only validated source IDs/content and unknown-capable fields. Extraction may interpret evidence; it cannot establish retrieval or create sources.

## Observed checkout evidence, separate from documentation

At inspection, `parseGroqResearch` required a recognized `executed_tools` search step and handled `search_results.results` plus a specific line-prefixed `tool.output` URL pattern; it did not handle `browser_results` or content-only source mapping. This is a local implementation finding, not a vendor requirement.

Existing synthetic-public-brief artifact `artifacts/ai/groq-search/2026-10-20T04-53-54-993Z/marfa.json` contains a recorded response with `message.content` and 15 `executed_tools`. This research did not replay or validate its facility claims and did not create a new live result. It does show why observed internal browsing counts must not be described as the prompt's two-search/four-open hard cap.
