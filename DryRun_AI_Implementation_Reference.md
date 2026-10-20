DRYRUN AI IMPLEMENTATION REFERENCE

Purpose
This is the detailed product and engineering specification for improving DryRun's Gemini integration and the native flows it enhances. Its companion launch prompt is DryRun_AI_Fresh_Context_Goal.txt. Keep this document available to the coding agent and consult it throughout implementation.

ADDITIONAL WORKING POINT — GROQ FALLBACK, CHECKED 2026-10-20 UTC

The owner reports substantial progress toward this goal and requests Groq as a fallback because Gemini is rate limited, with particular concern for search. This is an additional implementation requirement, not a replacement goal or a new architecture. Preserve every existing product outcome, corrective priority, six-scenario acceptance gate, deterministic authority boundary, and Linux/Mac responsibility. Inspect current progress and extend working code; do not restart completed work.

Keep Gemini primary and add capability-aware Groq fallback inside the existing private gateway using the server-side GROQ_API_KEY. Section 5A specifies real search continuity and provider switching; sections 8 and 13H connect it to existing resource and evaluation requirements. Elsewhere, requirements for what Gemini contributes also apply to an eligible fallback agent; provider-specific protocols, capabilities, and data rules remain specific to their adapters. A successful text fallback alone does not establish that search works.

CORRECTIVE PRIORITIES — UPDATED 2026-10-20 UTC

The owner reports that the current app's AI feels generic and immature, all six disaster scenarios feel the same, room editing is confusing and Save fails, and several panels/checks create unnecessary friction. These are reports about the newer app, not defects established by inspection of an older archive. Reproduce them against the actual current checkout and Mac build.

Highest-priority completion gates:
1) ALL SIX DISASTERS must have distinct causal mechanics, decisions, consequences, scenes, and debriefs: home fire, tornado, flash flood, freeze/power loss, heat/grid strain, and water outage. Sections 10 and 13 define the required evidence. One strong scenario or six renamed versions of one sequence is insufficient.
2) Fix room editing and its real Save/persistence path. Remove measurement chores and Still to confirm; make selection and Door/Window correction direct. Section 9 defines the native contract and checks.
3) Make household personalization substantive. Relevant recorded disabilities, assistance needs, medications, equipment, dwelling, and supply gaps must reach Gemini and affect applicable outputs. Sections 5-7 define the context and quality requirements.
4) Replace generic movement/helping decisions and the single persistent practice check with meaningful actions and varied checks whose completion updates persisted evidence and scores. Sections 10 and 12 define the lifecycle.
5) Fetch useful location information automatically. Remove user-facing location-record maintenance; support actual research, comparison, sources, and task links beyond the initial county. Section 8 replaces the older curated-only design.
6) Complete the reported task-row, family-editor, For your family, reconnection, and score-explanation corrections in sections 2 and 12.

These requirements supersede earlier constraints that would preserve unusable native flows, require routine manual measurement/scan confirmation, limit useful recommendations to a closed task catalog, make live resource research optional, or hide relevant household needs from the agents. Keep the existing seven connected feature outcomes and the deterministic authority boundaries. Mature the implementation already present; do not start another parallel architecture from scratch.

Operating context
The coding session starts without previous conversation context and works in an existing native iOS repository on Linux. A separate Claude session on an Xcode-enabled Mac with a connected iPhone owns native integration and device verification. The objective is a working, evaluated architecture with concrete native integration contracts.

How to use this reference
- Read these corrective priorities and the product, repository, architecture, and authority requirements before designing.
- Follow the implementation sequence in section 14, then revisit each feature section before changing that flow.
- Use section 13 to select meaningful verification for each slice.
- Treat historical implementation notes as orientation; current source establishes the actual implementation.
- Suggested type/module names and provisional rubric values permit justified refinement. Required feature outcomes, authority boundaries, and acceptance behavior remain in scope.
- Keep the reference available in the repository, preferably at its root or under docs/ai. Locate it by the exact filename DryRun_AI_Implementation_Reference.txt after a context reset.

Section index
1. Product intent and reported app baseline.
2. End-user experience and connected improvement loop.
3. Linux/Mac ownership, repository discovery, and engineering standards.
4. Architecture, execution locations, and agent roles.
5. Provider configuration, privacy, authorization, and operating limits.
5A. Additional working point: Groq fallback, real search, and provider continuity.
6. Shared contracts, evidence, revisions, and proposal acceptance.
7. Personalized preparations and supply inventory.
8. Automatic nearby resources and map integration.
9. Direct room editing and Save, home geometry, optional images, and concern review.
10. Six distinct disaster experiences, meaningful actions, adaptive state, replay, and fallback.
11. Dependency analysis and executable plan stress tests.
12. Numerical scorecard, practice credit, rubric, and agent council.
13. Contract, domain, model, image, rubric, and human/device evaluations.
14. Implementation sequence, deliverables, Mac handoff, and definition of done.
15. Community impact and demonstration.
16. Research sources and re-verification guidance.

The original research baseline is 2026-10-19. Resource discovery and the six-hazard lesson sources were checked again on 2026-10-20 UTC; section 16 identifies provider information to recheck at implementation time.

1. PRODUCT INTENT AND CURRENT BASELINE

DryRun helps families make useful emergency preparations, discover weaknesses in their plans, and practice responding to realistic situations in their own home. It should turn incomplete household knowledge into a few concrete improvements with minimal effort.

Product vocabulary:
- Household: family/household members, roles, assistance needs, trusted contacts, and relevant medical/power/storage dependencies.
- Home: a manually entered or RoomPlan-derived representation of rooms, floors, doors/windows, connectors, and relevant locations. Valid RoomPlan dimensions are accepted as the normal geometry input. Semantic suggestions and facts about actual use can be corrected without a scan-wide confirmation chore.
- Prepare / Next steps: a short prioritized action list for preparedness and mitigation, not just rehearsals.
- Plan: the living family emergency plan, meetups, local-resource map, home/escape preview, and emergency card.
- Family emergency card: a quickly readable, intentionally shareable/printable summary with prominent critical information, contacts, and meeting places.
- Rehearse: educational exercises in the family's own home/plan, with visual scenes, meaningful decisions, consequences, and follow-up preparations.

Use the established screen names and navigation in the actual checkout. AI should enhance these existing flows. Keep setup progressive, make correction easy, and preserve useful manual/offline paths. Do not add a chatbot, an agent dashboard, another primary tab, or a large questionnaire.

The owner is 18. Do not apply assumptions that the developer is a minor. Provider requirements for the eventual app audience are a separate deployment consideration described below.

Treat the latest repository and the following reported Mac-session changes as the baseline to preserve:

- The redesigned native PDFs emphasize critical information, contact tables, paired meetups, numbered map markers, home diagrams with opening gaps and route legends, continuation pages, and smaller files.
- Navigation now has direct family/home/card editors, a living Plan screen, contextual meetup selection, and fewer nested sheets. Card selections agree across preview and export.
- Rehearsal is scene first, advances between key moments, provides immediate decision feedback, and has clearer hazard/person/route symbols and useful debrief exits. Routing remains deterministic.
- Home/RoomPlan has clearer labeled 3D views, corrected floor-mesh winding, collapsible family details, and scanner room-type suggestions. Preserve the useful representation; the newer request removes the unusable blanket confirmation flow and measurement controls.
- Existing optional on-device AI turns a household description into a reviewable proposal, with an EN/ES/VI keyword fallback. A separate EN/ES briefing explains existing priorities.
- Local resources include explicit county selection and seven sourced Tarrant County records, still marked for review.

These native changes are owner-reported and may live on a newer Mac branch than your checkout. Verify which are present. If some are absent locally, do not recreate native screens, capture behavior, or PDFs from this prose. Continue portable work against verified current contracts, record the exact branch/commit and compatibility assumptions, and identify required native integration in the Mac handoff.

Preserve working native changes and user data. Coordinate through versioned contracts and the handoff; avoid overlapping speculative rewrites of files Claude is changing. Historical implementation notes below provide orientation and must be checked against current source. No earlier conversation or archive is required.

Required AI authority: Gemini must perform substantive planning, inspection, counterexample search, and adaptive exercise direction. It must contribute to a numerical preparedness scorecard through an evidence-based council and fixed rubric. Any older product note limiting AI to briefing prose or prohibiting numerical scores is superseded by this goal. Local facts, validated state transitions, resource arithmetic, and geometry-based routing remain authoritative.

2. THE EXPERIENCE TO DELIVER

A family should be able to:

A. Save an address and have relevant nearby preparation resources appear in the existing Plan map, with a specific reason each matters and a direct connection to an unfinished task.

B. Describe their household and supplies once, review a compact set of proposed facts, and receive a short, meaningfully personalized next-action list.

C. Scan or edit their home, optionally review selected room photos, and see a small number of possible visible concerns that can be confirmed, dismissed, or left uncertain.

D. Begin an exercise in their actual home layout. Their choices change the computed situation; the director observes those changes and chooses subsequent events and questions dynamically.

E. Check their plan for brittle dependencies, see supply gaps, and get a transparent scorecard with household preparation, practice, evidence coverage, and the next few useful improvements.

Build a shared improvement loop:
confirmed facts -> inventory and dependency assessment -> relevant tasks and nearby resources -> adaptive practice and stress tests -> reviewable findings -> updated facts and scorecard.

One confirmed change should propagate through that loop without repeated data entry. Simulated actions never silently become real household facts or completed preparations.

Required corrections to the existing surfaces:

Task rows:
- Keep the title and description in a stable text column. Place a smaller warning indicator in a dedicated trailing position or similarly unobtrusive location; adding a warning must not shift the text's leading edge or reduce it through a second large leading icon.
- Derive the row's relevant icon/badge styling from one semantic urgency state. Urgent rows use coherent red treatment, including the currently blue No cost icon; ordinary rows retain their appropriate styles. Keep readable contrast and an accessible text/icon indication of urgency.
- Verify long titles, multiline descriptions, large Dynamic Type, existing languages, and usable hit targets when an indicator is interactive.

Family editing:
- Present one clear Name field and a separate Relationship/role control. Avoid a redundant default-looking family-member heading immediately above the editable name. Keep You as an identity marker. A relationship change must not overwrite a real name.
- A new household starts with the user; other members are added intentionally. Preserve existing people, stable IDs, names, relationships, needs, and medications on migration and reopening.
- Capitalize localized disability/accessibility option labels through the display layer. Preserve stable stored values, user-written text, and acronyms such as ADHD. Audit dropdown options as well as field headings in existing supported languages.

For your family:
- Use a family icon, aligned with the heading, and consistent leading edges, spacing, and hierarchy. Avoid crowded badges and uneven padding.
- Show a small set of the most consequential supported observations, each connecting a household fact to its practical implication and an existing next action. Select them dynamically; do not hardcode a few sentences that merely repeat the profile.
- Where applicable, use actual recorded assistance/disability needs, medication storage or power dependencies, apartment/shared-building constraints, multiple floors, inaccessible supplies, and missing protection such as an extinguisher. Locally resolve member/room IDs to readable names. Distinguish not recorded from confirmed absent.

Remove the vague standalone Reconnect with family feature and its orphaned entry points, notifications, and obsolete completion checks. Preserve trusted/out-of-area contacts, useful meetups, emergency-card content, and concrete reunification tasks/practice. Replace a vague card only when a specific missing preparation warrants a direct action, such as adding an out-of-area contact. Removing a screen must not delete useful plan data or award communication points.

These changes should simplify existing screens. Do not substitute new approval dashboards, nested sheets, or a setup wizard for the flows being removed.

3. LINUX OWNERSHIP, MAC OWNERSHIP, AND INITIAL RECONCILIATION

On Linux, own:

- The private AI service, provider adapter, bounded agent runner, schemas, context builders, validators, public-evidence tools, request budgets, and tests.
- Platform-neutral Swift/domain changes where the toolchain supports them, especially the incremental simulation host, state/evidence models, inventory arithmetic, score compiler, and replay.
- Protocols and fixture adapters for native maps, image capture, local deterministic tools, secure authorization, and persistence.
- Recorded synthetic end-to-end examples, model evaluation, failure-mode tests, architecture decisions, and a concrete native integration guide.

The Mac session owns Xcode builds, SwiftUI integration, MapKit behavior, RoomPlan/ARKit capture, image redaction/camera permissions, Keychain/App Attest integration, device lifecycle, native PDF/share rendering, accessibility, and connected-iPhone verification.

Do not say Linux cannot test anything. Run the backend, schema, engine, and model tests available there. Do not report native or hardware testing as completed on Linux.

Start with focused repository discovery:
1) Read applicable AGENTS instructions, root README, package manifests, existing architecture notes, and relevant working changes. Identify branch/commit, actual runtime/toolchain versions, package boundaries, and test commands. Inspect credential presence without printing values or dumping environment files.
2) Locate existing domain, persistence, routing, simulation, AI intake/briefing, public-evidence, and native-adapter code. Reuse their actual symbols and ownership boundaries.
3) Trace all six rehearsal entry points through selected hazard ID, session initialization, household/home context, director policy, event handlers, fallback, persistence, and native scene selection. Trace one household edit through its outbound Gemini snapshot and preparation/plan invalidation, room Save through durable storage, and practice completion through evidence/scoring/UI refresh.
4) Run the relevant existing portable test/build baseline and record pre-existing failures separately. Native builds remain a Mac responsibility.
5) Write a compact implementation map with verified files/symbols, state owners, reuse decisions, required migrations, and genuine unknowns. Then begin the first executable slice; do not wait for every architectural question to be resolved.

Known earlier repository layout, to verify and adapt if renamed:
- apps/ios/DryRun: native SwiftUI application, AppModel, device services, and rendering.
- packages/DryRunCore: domain models, deterministic dependency/routing/simulation logic, and portable tests.
- packages/DryRunVault: private persistence.
- services/public-api: public content/evidence backend. Its agent directory historically had source allowlisting and claim provenance with a limited ModelProvider abstraction.
- content: versioned guidance, scenarios, regional data, and locales.

Useful historical seams include packages/DryRunCore/Sources/DryRunCore/Simulation/RehearsalEngine.swift, Simulation/HazardRules.swift, Session/RehearsalCursor.swift, and native AppModel orchestration. RehearsalEngine.run historically computed a whole schedule, missing choices could take defaults, and the cursor revealed precomputed results. If this is still true, implement an incremental session; a larger AI-generated fixed script is insufficient. Verify current resource/temperature support instead of assuming a label means a numerical model exists.

Preserve the established hazard families: home fire, tornado, flash flood, freeze/power loss, heat/grid strain, and water outage. Extend their shared mechanisms instead of leaving some families on an incompatible second engine.

Investigate actual causes of sameness rather than assuming a prompt change is sufficient. Candidates to examine include a selection/enum mapping bug, shared scenario fixture, generic fallback, omitted hazard or member revisions in a cache key, missing fields in transport, an overrestrictive decoder/action catalog, precomputed choices, or a renderer that ignores distinct committed events. Record evidence for the causes you find. Similarly trace failed Save and stale scores to their actual state owners; do not label a guessed cause as diagnosed.

Native corrections are required outcomes. If the current native branch is available and file ownership permits, prepare scoped changes against verified code and mark them native-pending until Mac validation. If newer native code is unavailable or Claude owns it, deliver exact shared contracts, reducers, persistence expectations, and reproduction/acceptance steps. Linux handoff readiness does not mean the app's native defects have been verified fixed.

Engineering standards:
- Implement the first runnable host/provider/tool/commit loop before creating a full set of empty role classes and schema shells.
- Contract names below identify responsibilities, not a parallel replacement domain. Reuse existing models; add thin transport DTOs or justified fields with migrations. Extend a working incremental engine/provider interface if one already exists.
- Give each fact and calculation one authoritative owner. Avoid duplicated scoring, resource math, or route rules in Swift and TypeScript.
- Preserve stable IDs, saved plans, card selections, and persistence compatibility. Add meaningful migration tests when data shapes change.
- Use explicit typed states/errors, bounded inputs, cancellation, and revision checks. Keep model SDK types inside adapters; do not hide mismatches with broad casts, silent defaults, or swallowed errors.
- Keep modules cohesive and interfaces small. Introduce abstractions for demonstrated boundaries, not hypothetical future providers or dozens of agents.
- Make code changes and their relevant tests in small coherent increments. Review the diff for unrelated changes and regressions after each slice.
- Test domain behavior, cross-language contracts, and actual failure risks. Do not inflate the test count with assertions that merely mirror implementation.
- Keep dependency/toolchain upgrades scoped to demonstrated requirements. Prefer the established stack and official Google SDK.
- Use parallel work only for separable tasks with clear file ownership and shared contracts; one integration owner reconciles the result.
- Distinguish required acceptance behavior from suggested implementation names. If source evidence supports a simpler architecture with the same authority, privacy, and reliability properties, implement it and record the reason.

Do not add a vector database, hosted workflow platform, or separate service per agent without a demonstrated need. Complete available work when one seam is blocked; report the exact remaining integration dependency.

4. RECOMMENDED SYSTEM ARCHITECTURE

Use three clear execution locations.

iPhone / portable DryRun domain host:
- Owns confirmed household facts, contacts, home geometry, supply inventory, accepted plan, local evidence, and authoritative simulation state.
- Builds minimal context snapshots for each role.
- Executes native geographic tools and the deterministic simulation/routing tools.
- Validates and commits proposals, renders the native experience, stores accepted results, and supports offline use.
- Calculates supply gaps and rubric scores from explicit rules.

Private AI gateway:
- A separate boundary from the public regional-content service; suggested location services/ai-orchestrator.
- Authenticates app requests, enforces per-installation and global budgets, invokes Gemini or an eligible configured Groq fallback, validates tool calls/output, and handles cancellation and errors.
- Runs a handful of roles using versioned prompts and role-scoped tools.
- Retains private job state only when required for a bounded operation, with an explicit short TTL.
- Returns proposals, evidence references, tool requests, and accepted-result explanations. It is not a second independent simulation database.

Public evidence service:
- Retains the existing public-only scope.
- Supplies reviewed guidance and automatically obtained public resource evidence through permitted APIs/directories/retrieval paths, with source identifiers, dates, applicability, and freshness. Curated region packs are bootstrap/fallback content, not the boundary of live discovery.
- Never accepts household profiles, room photos, contact lists, or private exercise histories into a shared public cache.

Build on the existing provider-neutral AgentProvider interface with Gemini and Groq implementations. Keep provider-specific request/response parsing and tool-continuation state inside their adapters. Represent research as a capability/workflow within this same gateway; it need not have the same call shape on both providers. Do not introduce another service or duplicate domain engine for fallback. Suggested roles:

1) PreparationPlanner: household-specific tasks and inventory interpretation.
2) ResourceStrategist: autonomous bounded discovery, reading, useful candidate comparisons, and task-specific resource explanations, alongside the native geographic adapter.
3) HomeObserver: visible concern proposals from home context and selected images.
4) RehearsalDirector: adaptive events, pacing, action interpretation, and consequence-based coaching.
5) PlanStressTester: executable counterexamples and dependency analysis.
6) AssessmentCouncil: bounded independent review passes and evidence adjudication.

These are role configurations and tool permissions within one service, not six permanent autonomous services. Reuse context/provenance helpers and combine compatible work in a call. Run the council for meaningful assessments and evaluation, not every tap.

The official SDK plus a small explicit orchestration loop is the default. Google's ADK is an option if its current TypeScript support measurably simplifies tool suspension, validation, and evaluation. Document the choice; do not adopt a framework just to label the app "multi-agent." [R1-R5]

5. PROVIDER CONFIGURATION, DATA HANDLING, AND OPERATIONAL LIMITS

Provider implementation:
- Read GOOGLE_AI_STUDIO_KEY from the selected runtime's secret mechanism and pass it explicitly to the SDK: env.GOOGLE_AI_STUDIO_KEY for a Cloudflare Worker binding, or process.env.GOOGLE_AI_STUDIO_KEY for Node. Do not copy it into client configuration or assume the SDK discovers this custom variable name.
- Read GROQ_API_KEY through the same server-only mechanism and pass it explicitly to the Groq adapter. Never log either key, include it in fixtures, or ship it in the iOS app. Section 5A adds fallback without replacing the primary provider or the existing feature goal.
- Verify the current model/API capabilities and installed SDK. Configure model IDs per role rather than scattering literals. Pin model, SDK, prompt, schema, content, and rubric versions in evaluation records.
- Current official documentation presents Interactions as the recommended API for new work; generateContent remains supported. Interactions stores by default. Use store:false for private requests and keep the required continuation content yourself; do not mix the two APIs' response formats. [R1]
- Preserve required tool-call IDs, signatures, and opaque protocol parts through stateless continuation using the official SDK's supported representation. Retain them only for the active bounded operation. Application code executes function calls. Validate values and semantics even when structured output passes its JSON Schema subset. [R2-R3]
- Start by evaluating a current economical Flash-class model for routine roles and a stronger configured model for difficult inspection/adjudication. Choose using actual fixture quality, latency, and cost.
- Do not require Live voice, Deep Research, desktop browser automation, provider file-search storage, or an always-running agent for this feature set. Provider-hosted research tools such as Groq browser_search are covered separately in section 5A.

Data defaults and deployment fit:
- Use synthetic fixtures for developer testing until the intended private-data configuration is verified. Gemini's unpaid-service terms disallow submitting sensitive/personal information; paid-service handling differs, and provider abuse retention still exists. [R6]
- Google's current terms require developers to be 18+ and restrict API clients directed to, or likely accessed by, under-18s. The owner's age meets the developer minimum; it does not settle the family-app audience question. Record this release-fit issue without blocking synthetic implementation or claiming parental consent alone resolves it. [R6]
- Keep Groq and any future alternate provider/Vertex deployment behind the adapter and evaluate actual terms separately. Groq fallback is owner-requested; household data sharing still follows the configured disclosure and consent scope. Do not promise that an alternate product automatically resolves all restrictions.
- Keep the product within preparedness education and recorded care requirements; do not implement clinical advice or diagnose medical conditions. [R6, R14]
- Provide a concise native cloud opt-in that identifies Google Gemini and Groq fallback and the information shared, with a separate understandable review for optional room-photo upload. Reuse existing consent when it already covers both; update a Gemini-only disclosure before sending private household data to Groq. Do not interrupt every automatic switch with another prompt. Apple requires disclosure and permission for personal-data sharing with third-party AI. [R9]

Context minimization:
- Task planning uses stable anonymous member IDs with relevant recorded disabilities, functional/communication/assistance needs, medications, storage requirements, essential equipment, caregiving arrangements, and instructions that affect preparedness. Keep specificity that changes the plan; a hasMedicalNeeds boolean is insufficient.
- Include a medication name or relevant recorded instruction when needed to interpret that dependency, under the configured consent/data path. Do not discard medications or disability fields merely to simplify the DTO. Omit member/contact names, phone numbers, and unrelated clinical narrative; resolve readable member names locally for presentation.
- Distinguish a recorded diagnosis/disability from a recorded functional limitation. Do not assume a diagnosis establishes inability to walk, hear, decide, or live independently. A medication name alone cannot establish a storage temperature, safe interruption period, altered dose, or clinical recommendation.
- Spatial review needs the home graph and selected images, not the street address.
- Public resource research receives a minimized service brief, travel constraints, and a coarse locality; it does not receive names, medication lists, room plans, or the exact home address in search queries. The private planner can translate a recorded medical/accessibility need into a necessary service capability. Apply that translation without losing the practical requirement.
- Run web-enabled research as a separate operation built from a typed ResearchBrief. Do not attach the private planner's conversation, provider continuation state, household snapshot, member IDs, or room images. Preserve useful requirements such as step-free access, delivery, and needed equipment-service capabilities. Personalized briefs/reasoning stay private; shared caches contain only permitted public evidence.
- The exercise director needs relevant committed state and evidence, not the entire photo collection at every turn.
- Build schema-level context policies and test both required relevant fields and forbidden unnecessary fields. Privacy handling must preserve useful permitted context instead of reducing every household to the same generic summary.
- Household snapshots remain sensitive even after names are removed.

Gateway requirements:
- Do not expose an unauthenticated paid-model proxy. Implement an authorization interface, short-lived scoped sessions, quotas, payload/image limits, and replay protection. Provide an App Attest-compatible native handshake contract and a real server validation path or a clearly identified integration dependency.
- Developer fixture credentials must be restricted to local/dev operation; production must fail closed if its authorization provider is not configured.
- Bind continuations to the authenticated installation/session, operation, context revision, permitted tool name, and pending tool-call ID. Enforce expiry and one-time or idempotent consumption. Reject unsolicited, cross-operation, or out-of-order results. Client responses cannot change role permissions, tool arguments, spend limits, or provider identity. Schema validity alone does not establish a client result's trustworthiness.
- Limit allowed roles, tools, models, and output sizes on the server. Never accept an arbitrary client system prompt or arbitrary tool/URL execution.
- Redact personal payloads from logs and error traces. Record versions, latency, token/tool counts, validation outcomes, and non-sensitive diagnostics.
- Give each operation a deadline, finite tool/call budget, one bounded repair opportunity, cancellation, and typed errors. Use a configurable small development spend cap; start with a synthetic smoke suite and report remaining evaluation work if the cap is reached.
- Prefer inline bounded image requests over persistent provider uploads. If uploads are necessary, implement explicit lifecycle/deletion and document actual retention.
- Treat website text, OCR, household notes, and model output as untrusted data. They cannot change role instructions, tool permissions, validated network-access policies, or application state.
- Accept newly discovered public sources through section 8's guarded retrieval controls; a source need not already exist in a region pack/catalog. Reject unvalidated URL execution, private-network destinations, unsafe redirects, and attempts to alter retrieval policy. Separate retrieved instructions from application instructions and prevent cross-household cache contamination.
- Do not request, display, analyze, or persist hidden chain-of-thought in application records. Preserve only provider-required continuation parts/signatures, unchanged, inside bounded transient operation state; delete them on completion or expiry. Durable records contain concise evidence-linked decisions, tool receipts, accepted commands, and committed events. store:false is an interaction-storage setting, not a guarantee of zero provider retention.

Keep the existing local intake, translations/fallbacks, deterministic checklist, saved plan, card, and authored exercises available without cloud access. A network error must not erase useful results.

5A. ADDITIONAL WORKING POINT: GROQ FALLBACK AND SEARCH CONTINUITY

Scope and architecture

Implement Groq fallback within the existing gateway, context builders, role policies, validators, tool protocol, and result contracts. The original goal remains in force. Preserve the richness of household personalization, all six distinct scenarios, evidence-based resources, and the practice/score loop. Fallback must not substitute generic prose, a canned regional list, or a new user workflow for those outcomes. Do not make users choose providers, obtain keys, paste URLs, or maintain location records.

Route by the capability needed for the operation: private text/structured proposals, application function tools, public web research, or image understanding. Record the configured model/API capabilities and evaluation status. A shared chat-completion interface does not prove tool, search, schema, continuation, privacy, or image compatibility. Keep Gemini as the default when eligible; use Groq when the relevant primary operation is unavailable or its quota circuit is open. If neither can satisfy a capability, preserve the useful existing local/native/cached path and return an honest typed status.

Current search implementation to verify and use

- As checked on 2026-10-20 UTC, Groq lists groq/compound and groq/compound-mini as decommissioned on September 21, 2026. Do not build against surviving examples or search snippets for those model IDs. The deprecation notice does not itself name a direct successor. [R25]
- Current Groq documentation supports provider-executed browser_search on openai/gpt-oss-120b and openai/gpt-oss-20b through POST https://api.groq.com/openai/v1/chat/completions. Evaluate the 120B model first for research quality; test the 20B model if it meets the same useful-output gates. These are Groq-hosted model IDs authenticated with GROQ_API_KEY; they do not add an OpenAI API dependency. Keep model IDs configurable and recheck current availability when implementing. [R26]
- Supply tools: [{ type: "browser_search" }], tool_choice: "required", and stream: false on the dedicated research request. Configure citation options, output limits, reasoning effort, and returned-reasoning suppression only through parameters supported by the actual API and installed SDK. Current Groq guidance recommends low reasoning effort to constrain browsing. Do not persist hidden reasoning. [R26, R29]
- The documented browser_search path uses Exa internally and does not require a separate Exa/search-provider key. Actual model access, billing, usage limits, and deployment configuration still need a small synthetic live smoke test; the existence of GROQ_API_KEY alone proves none of these. [R26]
- Do not pass obsolete Compound web_search/visit_website configurations. GPT-OSS does not support the separate legacy Visit Website tool. Current built-in tools can coexist with compatible custom tools, so do not impose obsolete Compound restrictions; DryRun's public research role should nevertheless expose only the tools it needs. [R26]

Required search-to-result flow

1) Build the existing typed ResearchBrief from permitted service needs, coarse locality, travel constraints, and the current preparation gap. Run it in a fresh public-research context. Do not forward private planner history, exact home address, names, household/member IDs, medication lists, diagnoses, room images, or home geometry to web-enabled research.
2) Attempt the existing Gemini research workflow when its capability and circuit are available. On an eligible failure, run actual Groq browser_search. Request named useful options, material comparisons, explicit sources, and specific unknowns. A natural-language answer from a plain model call is not live search.
3) Preserve the returned attributed answer and actual source metadata. Capture a sanitized synthetic response from the chosen Groq API/model and implement parsing against it. Browser Search documentation shows snippets and inline citations; optional SDK annotations or executed_tools fields are not guaranteed on every response and must not be the sole success requirement. Never invent URLs from unresolved citation markers, reuse Gemini groundingMetadata parsing, or accept source-looking model text as proof of retrieval. [R26, R29]
4) When the existing UI needs a typed proposal, perform a separate, tools-disabled Groq extraction call using a supported strict JSON schema. Groq currently does not support combining Browser Search with Structured Outputs; its Structured Outputs also excludes tool use and streaming. GPT-OSS 20B/120B support strict schema output. Preserve a working Gemini single-call path where supported; identical app contracts do not require identical provider workflows. [R27]
5) Give the extractor application-assigned source IDs and supported evidence. It can map and qualify those claims, but cannot manufacture new sources, coordinates, dates, capabilities, or URLs. The schema must represent unknown/partial/unavailable results instead of forcing invented required fields. Keep the original attributed answer available. Validate claim support, source identity, relevance, material uncertainty, schema, and permitted display/storage. If extraction fails after the bounded repair, retain any independently validated useful research that the existing UI can safely show; do not silently label an empty JSON result as a successful resource search.
6) Return through the existing Plan/task result contract and native MapKit adapter. Keep the practical chain: household gap -> supported local capability -> useful next step. Native map candidate identity joins, data permissions, automatic refresh, and task links remain governed by section 8. Do not claim Groq searched Apple Maps or established a safe evacuation route.

The fallback extraction cannot depend on Gemini recovering. Conversely, do not remove search from a failing request just to obtain schema-valid output. Tools-disabled extraction is formatting/interpretation of retrieved evidence, not a second search. If the current UI already accepts a validated attributed answer, omit an unnecessary extraction call. Preserve partial supported findings and dates; distinguish live sourced, partial sourced, successful search with no matches, unavailable search, and cached results. A successful request does not prove stock, opening, shelter activation, or present road conditions. [R26-R27]

Keep provider-grounded content and independently retrieved durable evidence under their respective permissions. Do not transfer raw Google-grounded content into Groq merely because the primary failed. A fresh research brief is the default across providers. Only reuse evidence where its provenance, freshness, and processing permissions allow it; unsupported claims may be verified through the existing permitted independent retrieval path or left qualified. Fallback is not a way to bypass content-use restrictions.

Rate limits, budgets, and error handling

- Normalize provider failures into useful internal categories: transient rate limit, exhausted quota, service/transport timeout, authorization/configuration failure, unsupported capability/request, policy refusal, invalid output, and cancellation. Preserve retry/reset data and a non-sensitive diagnostic. Do not reduce every failure to an empty list or retryable 500.
- Gemini limits are per project, not per API key. Groq exposes 429/retry-after and quota headers; its request and token counters use different windows, so parse documented units/reset values rather than assuming both are per minute. Avoid hard-coded account quotas and key rotation. [R28, R31]
- On confirmed exhaustion, open the relevant circuit promptly. A short transient retry is acceptable only when its delay fits the remaining operation deadline. Otherwise use an eligible fallback. Respect retry-after, use jitter, permit a controlled half-open probe after cooldown, and prevent simultaneous callers from repeatedly probing an exhausted provider. Scope failures to the real quota/capability scope instead of globally disabling a working provider after one unsupported tool combination.
- Bound the entire logical operation across both providers: request attempts, tool continuations, extraction, output repair, token/output limits, elapsed time, and spend. A new attempt or extraction step does not reset its deadline or budget. Allow at most one provider switch and one output-repair opportunity per operation; never ping-pong between providers. Suggested retry/call limits are implementation policy, not vendor quota claims. Account for provider-internal browsing separately: an application request cap is not an exact cap on internal searches.
- Groq's current TypeScript SDK automatically retries selected failures twice and defaults to a one-minute timeout. Set maxRetries: 0 when the gateway owns retries, and use an explicit timeout bounded by the remaining deadline; otherwise explicitly account for SDK attempts. Inspect the installed Gemini SDK's behavior too. Cancellation must reach queued work, network requests, tool continuations, and result acceptance. [R29]
- Do not cross providers to bypass a policy refusal, revoked consent, or an access restriction. Stop retries for invalid configuration and expose an actionable operator diagnostic; a separately authorized, correctly configured fallback may continue. Model/tool incompatibility requires an adapter/configuration fix, not pretending a text call searched.
- Keep permitted useful results while refreshing. If both providers are unavailable, return the existing native/offline/cached behavior with an accurate freshness/status message. Do not make an outage erase the plan or generate dozens of generic replacement tasks.

State continuity and privacy

- Retain the logical operation ID but issue a new provider-attempt ID/generation. Fence the old attempt's responses, continuations, and pending tool calls, including late arrivals at an otherwise unchanged host revision. Check the fence before dispatching native tools and when accepting their results. Cancellation is best effort: an upstream call may still finish and incur usage, so unknown usage is not zero or an automatic refund. Record provider/model/attempt provenance internally without a new user-facing provider dashboard.
- Reconstruct the fallback request from the current authoritative committed snapshot, selected hazard/mechanics version, user intent or durable commit receipt, recent accepted events, pending incidents, valid evidence, and remaining budget. Do not translate or forward Gemini thought signatures, raw continuation objects, or hidden reasoning to Groq.
- Reuse a read-only tool receipt only if its arguments, revision, freshness, and permissions still hold. Never replay a committed user action or consume supplies again on provider switch. If a commit acknowledgement is lost, reconcile the host's durable receipt before continuing; an unknown outcome is not permission to retry a state mutation. Pause that operation if durable status cannot be established; neither model may guess whether the commit happened.
- Rehearsal network waiting does not advance simulated time. Preserve resources, occupants, incident queue, history, and hazard identity. The deterministic host still validates and commits changes. Replay uses the committed log without model calls. The same fixed rubric and accepted evidence determine scores; changing provider alone never changes a score.
- Preserve the relevant member-linked disability, assistance, medication/storage, equipment, dwelling, and supply context for authorized private Groq roles. Provider fallback must not strip meaningful context into generic booleans. Explicitly disable public web/remote tools on private inference using supported adapter controls; test what is actually sent.
- Groq's data documentation distinguishes inference content, limited reliability/abuse retention, usage metadata, and configurable retention controls; do not promise blanket zero retention. Browser Search is outside Groq's HIPAA BAA coverage. Verify the actual deployed data configuration before sending real private fixtures; these facts do not block synthetic implementation or establish the legal classification of every consumer record. Groq Chat Completions currently does not support store, so do not blindly copy Gemini's store:false parameter. [R29-R30]
- Do not assume text/search fallback also supplies evaluated vision. Current model listings include a preview vision option; use an image-capable fallback only after capability, privacy, and quality evaluation. Otherwise leave image inspection pending or use the existing manual/local path while continuing eligible text, home-graph, and search work. Never claim a text-only call inspected room photos. [R30]

Definition of this additional working point: the existing app outcomes remain intact when Gemini is rate limited, with actual attributable Groq search, source-preserving useful results, bounded provider handling, and no state/privacy regression. Implement and verify section 13H; a provider selector, mock search, or successful generic chat response alone does not complete it.

6. SHARED CONTRACTS AND EVIDENCE MODEL

Define the minimal versioned contracts and fixtures needed for the first runnable slice, then expand them with each role. Reuse existing domain models instead of building a duplicate schema universe. Generate types where useful, but test real TypeScript/Swift round trips rather than assuming identical optional/null/enum behavior.

At minimum define:

- HouseholdContextSnapshot
- HomeSceneContext and RoomImageManifest
- EvidenceRecord and EvidenceReference
- AgentOperationRequest / AgentOperationResult
- ClientToolRequest / ClientToolResult
- ResourceSearchPlan and ResourceRecommendationProposal
- DiscoveredResourceEvidence and an attributed transient research-result envelope with explicit display/retention permissions
- InventoryObservationProposal and ConfirmedInventoryItem
- PreparationTaskProposal
- HomeConcernProposal
- SimulationSessionState, UserActionIntent, DirectorProposal, and CommitReceipt
- StressTestFinding
- RubricDefinition, CriterionAssessment, CouncilReview, and PreparednessScorecard
- PracticeCheckDefinition, PracticeAttempt, CompetencyEvidence, and persisted completion/score invalidation receipts

Use stable IDs and include the relevant household/home/inventory revisions, session ID, monotonic event sequence, context digest, request/proposal ID, creation/expiry timestamps, and contract version. Reject stale responses rather than applying them to newer facts.

Extend existing operation/evidence envelopes only as needed for section 5A: provider-attempt generation, actual model/API provenance, capability/error classification, research execution status, and source/expiry metadata. Do not create a parallel Groq-specific domain model. Provider switching must fence stale attempts as well as stale household revisions.

Evidence must distinguish:
- User-recorded or explicitly confirmed facts.
- Scanner measurements and unconfirmed scanner suggestions.
- Independently obtained official guidance and public-service information.
- Independently obtained publisher-reported business/provider claims, with publisher identity, claim-specific sources, dates, and limitations.
- Attributed provider-grounded research, retaining metadata and applicable display, retention, and reuse permissions.
- Geographic provider results subject to their own use rules.
- Model observations/suggestions.
- Explicit hypothetical exercise assumptions.
- Engine-derived findings and real committed exercise outcomes.

Do not merge those into a single "AI confidence" field. Include source/evidence IDs, applicable jurisdiction, retrieval/publication date where available, confirmation state, and uncertainty. Model confidence is not verified truth.

Validate support at the claim level. A business page can support its stated delivery service without proving stock; an official service page can establish a program without proving today's activation. Preserve supported information and identify the particular unknown rather than rejecting the entire recommendation.

A useful operation result is a discriminated union:
- completed: a validated proposal with evidence.
- needs_client_tools: bounded native/core tool calls and an expiring continuation token.
- needs_clarification: one targeted question whose answer changes the next action.
- unavailable/rejected: a typed reason and supported fallback.

The gateway should use opaque, expiring, revision-bound continuation state, preferably retained server-side only for the active operation. Do not expose raw provider history or hidden reasoning to app UI. Provide a local harness that drives the same protocol without an iPhone.

Only app/domain commit handlers write household facts, inventory, task completion, or simulation state. A user's confirmation can approve a batch of related observations in one concise review; do not require repetitive confirmations for the same fact.

Audit the full household path: stored person -> context builder -> transport -> server validation -> role input -> structured result -> local presentation. A field existing in Swift is not evidence Gemini receives it. Add schema fixtures for disabilities, assistance capabilities/preferences, medication and recorded storage instructions, equipment loads/backup arrangements, dwelling/floors, contacts' roles, and inventory availability. Preserve unknown versus absent. Include relevant revisions in request fingerprints and invalidate stale results after edits.

Verify relevant medical/assistance context separately for the preparation planner, exercise director, stress tester, and scorecard reviewers. Preserve member-to-medication/device/instruction links and uncertainty; each private role receives the dependencies it needs. Public research receives only the minimized service brief. Include a two-member fixture proving that needs are never assigned to the wrong person or lost during local name resolution.

7. PERSONALIZED PREPARATIONS AND SUPPLY INVENTORY

Implement a preparation pipeline that combines agent interpretation with source-backed actions and deterministic quantities.

Inputs:
- Confirmed member disabilities and recorded functional needs, medications and applicable storage/continuity instructions, equipment, caregiver/assistance arrangements, dwelling type/floors, relevant hazards, actual supplies, transport, existing plan, and unresolved evidence.
- Optional cost, effort, transport, and storage constraints. Make these optional and easy to change.
- Existing reviewed action catalog and source records as reusable foundations, including communication/meetup and home-escape preparations. Permit grounded task composition and new useful preparations beyond catalog wording. [R12-R13]

Planner behavior:
- Identify which actions apply and why, adapt their wording, identify dependencies, choose a small useful slate, and ask only the highest-value missing question.
- Show three primary next actions by default, with a compact path to the rest. Do not replace a short list with dozens of generated tasks.
- Keep reviewed life-safety priority constraints. Let the agent meaningfully select and sequence within those constraints using household needs, prerequisites, cost, effort, and expected preparation benefit.
- Every task needs stable objective and subject IDs, a specific next action, an applicability explanation, source/evidence references, completion predicates, the relevant editor/action, and links to inventory/resource/stress-test dependencies. Include criterion IDs only where a valid mapping exists; useful tasks need not all be scored.
- Use subject-specific identity so two people needing different support are not collapsed into one task.
- Do not automatically complete a task because the model recommended something or the family succeeded in a simulation.
- Let Gemini generate bespoke, evidence-linked preparations and combine related needs into practical tasks. Validate relevance, support for consequential claims, feasibility, duplication, and completion behavior. Uncatalogued must not automatically mean rejected or hidden behind a separate ideas-review queue.
- A bespoke task can satisfy an existing criterion only when its confirmed result meets that criterion's actual predicates. Otherwise it is a useful unscored task; it cannot invent a weight, denominator, critical cap, or medical instruction. Rubric changes remain a development process.
- Display rough cost/effort bands as estimates when useful. Do not invent current prices or product availability.

Examples of meaningful personalization:
- Infant: caregiver/reunification arrangements and appropriate feeding, sanitation, and essential supplies based on recorded needs.
- Dog: food/water planning, carrier/leash, transport and destination compatibility.
- Powered medical equipment: documented approved backup arrangements, equipment-provider contact, allocation of available backup capacity, and an earlier preparation priority when a critical requirement is unresolved.
- Two independent adults: applicable household protections, water/food, communication, meetups, and relevant local hazards without irrelevant infant/pet/device tasks.
- A household without a car: reachable resources and assistance/transport plans that do not assume driving.
- A family with limited funds: feasible free or low-cost actions and supported community resources, without hiding genuine shortages.
- A member with a recorded mobility constraint sleeping upstairs: identify the specific route/assistance-plan dependency; do not offer a generic staircase action as feasible.
- A recorded refrigerated medication with no documented outage arrangement: identify the missing storage preparation without inventing product-specific limits.
- An apartment household: account for recorded shared exits, dwelling/floor information, and building arrangements; do not pretend a unit-only scan includes the whole building.

Personalization acceptance:
- Require a traceable recorded fact -> practical implication -> useful next action -> reason for its current priority. Keep this concise in the UI; detailed evidence belongs behind existing details.
- Pair synthetic households differing in one relevant disability, medication-storage requirement, housing/floor arrangement, or supply gap. Verify the actual outbound snapshot and that applicable tasks, resource needs, or scenario options change substantively. Irrelevant facts should not gratuitously change unrelated advice.
- Test sparse profiles, conflicting records, and already-owned equipment. Correctly ask one useful question or explain a specific uncertainty instead of fabricating a fact, repeating buy supplies, or requesting a large questionnaire.
- Audit all role prompts, schema enums, token budgets, source tools, caches, and fallbacks for constraints that collapse supported reasoning to generic templates. Make the system bounded around factual authority and execution, with enough latitude for useful planning.

Inventory:
- Add concise "What do you already have?" intake in the existing Prepare/household flow. Reuse current description intake where possible.
- Support typed entries first; optional voice/photo extraction produces reviewable item proposals. A product photo does not prove ownership, quantity elsewhere, functionality, compatibility, or unreadable expiry.
- Model item ID, category, quantity/unit, usable quantity, condition/expiry when known, storage room/location, accessibility, relevant people/devices, provenance, and last confirmation.
- Distinguish unknown quantity from zero. Require compatible units and explicit conversion rules.
- Count the same physical item once across images, plans, and allocations. A shared battery cannot independently promise its full capacity to every device.
- Compute deficits locally from reviewed rules and an explicit planning horizon. CDC's baseline is at least one gallon per person per day for three days, with additional considerations and a longer supply where possible; do not let a model invent a universal per-person or per-pet quantity. [R11]
- Keep medication/device/infant-specific requirements tied to recorded instructions and appropriate source content. Equipment backup suitability must come from manufacturer/distributor instructions, not a visual guess. [R14]
- Convert a confirmed deficit into one actionable task, a relevant nearby-resource search, and a possible exercise dependency.
- Owning an item, having it accessible, and knowing how to use it are distinct predicates. Credit each only where the rubric explicitly calls for it.

Acceptance example:
For an infant + dog + powered-device household, incomplete backup documentation must not be buried beneath a generic shopping task. If the family already owns suitable supplies, ask for a missing location or condition only when it matters instead of telling them to buy duplicates.

8. AUTOMATIC NEARBY PREPARATION RESOURCES

Remove the user-facing Location records workflow, including record creation, URL entry, source-pack choice, and manual record reconciliation. The family should receive researched options in the existing Plan map and related task. Internal evidence records are still useful; maintaining them is the app's job.

Save an address once. Resolve geographic context locally where possible and request correction only for actual ambiguity. County is internal source metadata, not the organizing concept. Start discovery automatically within the existing cloud opt-in after a home is established or a material preparation gap changes. Users may choose/favorite a destination or refresh results without becoming researchers.

Deliver completed recommendations, not merely a ResourceSearchPlan that leaves discovery to the user.

A. Derive a focused research brief.
The private planner identifies the relevant gap, hazard/dependency, necessary capability, travel mode/range, optional cost constraints, and alternatives. Send only the minimized service need and locality to web-enabled research. Exact address, medical narrative, contact identities, and floor plans stay out of public search queries.

B. Research and native geography work in parallel.
- Implement actual agent-assisted discovery and page inspection. The primary Gemini path uses supported Google Search together with URL Context so the model can find relevant pages and read them; users need not supply URLs. Verify the chosen model/SDK/tool combination and preserve required citation/suggestion metadata. Add section 5A's Groq browser_search workflow when the primary is unavailable. Both return the same useful app outcome with provider-appropriate evidence handling; schema-valid text alone is insufficient. [R3, R7, R21, R26-R27]
- Investigate organization/provider pages, official directories and service announcements, and relevant business websites. Compare what matters: documented service, eligibility, accessibility information, delivery/pickup, stated hours, appropriate cost information, and consequential unknowns.
- If the first result is weak, allow bounded expansion to neighboring localities, regional assistance, delivery, or another useful category. Seven bundled records cannot define the research universe.
- Run MapKit searches independently on the iPhone with the saved home as origin. The native adapter supplies geographic candidates, ordinary travel estimates, and Apple-map presentation.
- Each native tool has an explicit cloud-return policy. Do not forward Apple listings, coordinates, routes, photos, or derived descriptions into a generic continuation unless the specific processing path is permitted. Gemini may compare independently obtained permitted evidence; do not claim it inspected listings it never received.
- Match independently sourced evidence to a native candidate automatically only through a permitted path and sufficient identity checks: stable IDs where available, full name/address, and relevant location checks. A nearby similarly named place is insufficient. If a join cannot be established, retain a useful attributed research result alongside native candidates rather than inventing a match or asking the user to reconcile records.

C. Support two concrete evidence paths.
1) Provider-grounded answers: the Gemini Search/URL Context path or section 5A's Groq Browser Search path performs live discovery/reading and returns an attributed answer. Retain and display it under that product's actual terms, with adapter-specific provenance. Do not mine grounding results into a separate crawler or unrestricted permanent database.
2) Independent retrieval: query permitted official APIs/directories or appropriately licensed search services and read relevant public pages through a guarded retrieval service. This can populate durable DiscoveredResourceEvidence when its source rights permit that use. Source controls include public HTTPS, redirect/destination checks, network isolation, size/time bounds, relevance, publisher identity, and claim support. Do not require an operator to pre-enter every locality or a user to approve every URL.

Implement the first path as required live research; support the second where durable resource/plan evidence needs it. A fixed source-ID allowlist or bundled pack alone does not meet automatic discovery. Keep website content untrusted and separate from role instructions. Prefer official evidence for public services and activation claims; a business's page can substantiate what it states about its services without proving stock or suitability for every household.

Use an internal evidence envelope with identity, source URL/provider, retrieval date, publication/updated date when available, claim-to-source references, jurisdiction, supported capabilities, unresolved questions, refresh policy, and permitted display/storage/export uses. Apply those permissions at the adapter boundary. Do not require human review of every informational location before it can be useful.

Record the research execution time separately from source publication/update dates and the period a claim describes. Online discovery may use indexed content. A successful research call does not establish current opening, stock, or activation; request fresher evidence when that distinction materially changes the recommendation. Preserve useful dated findings with specific qualifications. [R21]

D. Show a compact, useful result.
- Favor two or three good options related to the current preparation, with limited map markers and a direct location overview.
- Explain the actual match: household gap -> supported service/candidate capability -> useful next action. Distance alone is not a rationale.
- Show name, category, location, ordinary distance/travel estimate when available, why it matters, material unknowns, and sources associated with the claims. Keep attribution with provider-grounded content.
- Connect to an existing task or plan choice; for example, a missing extinguisher preparation can open relevant hardware-store options, and a documented cooling dependency can open researched cooling alternatives.
- Offer Open in Apple Maps and ordinary user-initiated contact/navigation controls. Agents do not call locations, send messages, buy supplies, or start navigation themselves.
- Preserve partial usefulness: a grocery candidate is useful even when stock is unknown; a published service is informative when today's activation is unconfirmed. State the particular limitation instead of a blanket unverified label and a research chore.
- If evidence is genuinely unavailable, explain the limited result and offer a useful native search or supported alternative. Do not fabricate a named facility.

Relevant categories:
- Grocery/food assistance and drinking-water preparation.
- Pharmacies/equipment suppliers for recorded requirements.
- Hardware/general retailers for extinguishers, alarms, flashlights, and suitable supplies.
- Hospitals/emergency departments with facility type established where available.
- Police/fire stations and emergency-management offices, explaining their actual role.
- Officially identified warming/cooling centers, shelters, accessible destinations, and trusted meetups.
- Warm clothing/blankets and appropriate heating preparations. Include firewood only for a household with confirmed suitable installed equipment; do not make generic indoor-combustion suggestions. [R17]

Unsupported claims remain specific boundaries:
- A police/fire station, school, or church is not automatically an activated public shelter.
- Listing a retailer does not establish stock or operation during an outage.
- Nearest does not establish the appropriate destination for a particular medical emergency.
- An ordinary route estimate does not establish a flood-safe evacuation route.
Use supported official information for flood preparation and explicit hypothetical closures for stress tests. Tornado preparation focuses on an appropriate reachable shelter, rather than default driving to a distant generic destination during a warning. [R15-R16]

Data and refresh behavior:
- Preserve the seven Tarrant records and their provenance until updated by actual evidence. They are initial content, not a nationwide coverage claim or a mandatory review task.
- Keep provider-grounded Search/Maps answers out of the unrestricted permanent resource database and PDF pipeline unless an explicitly implemented permitted path allows that use. Live discovery is required now; rights-aware handling should make it useful, not defer it indefinitely. [R6-R7]
- Direct Google Places has separate configuration and map-display policies. The Gemini key does not automatically enable it. Keep the existing Apple map and do not copy Google Places/Maps content indiscriminately into Apple pins or exports. [R8]
- Apple also limits map-data reuse/storage/display; preserve a provenance-aware native adapter and verify snapshot/export handling without undoing the working renderer. [R10]
- Refresh on changes to relevant needs, transport/budget constraints, locality, source freshness, or an explicit refresh. Native geography has a separate fingerprint. Debounce edits, deduplicate, cancel stale work, and retain useful results while refreshing. Unrelated medical notes/photos must not trigger web research.
- Bound operation time, requests, tool rounds, returned results, and cost. A cap on app requests is not a guaranteed cap on the provider's internal searches. Record actual usage.
- Revoking cloud opt-in stops new jobs and cancels active work where possible; native search and permitted saved plans remain useful.

Acceptance:
Starting with an address and a relevant household gap outside Tarrant County, demonstrate actual automatic discovery of useful named options, evidence-backed differences, native map candidates, and a task link. Include a rural/no-car case, stale/unavailable information, and a no-results fallback. The family must not create records, paste URLs, choose source packs, or repeat the research. Clearly label live-retrieved, recorded-fixture, and native-pending evidence.

9. DIRECT HOME EDITING, OPTIONAL IMAGES, AND REVIEWABLE CONCERNS

Repair the existing room editor as a required native outcome.

Direct editing:
- Make the home canvas the main editor. Tapping a room selects it and opens/updates one compact inspector with clear Name, room use/type, floor context, and relevant settings. Avoid nested room -> configuration -> another sheet chains.
- Selected room and opening must be unmistakable using a strong outline/fill and visible name/type, with accessible selected-state announcements. Selection and inspector values must reference the same stable ID, including adjacent/small rooms and multiple floors.
- Tap a door/window opening to select that precise object and show an immediate Door / Window control. Reclassify it in place; preserve identity and captured geometry. Do not require deletion/recreation or another screen.
- Update 2D/3D appearance and draft route semantics coherently. A corrected window does not automatically become a verified usable exit, and a previous door classification cannot leave stale door-route eligibility.
- Hide raw measurements, dimensions, transforms, and measurement-edit controls from the user interface. Do not move them to another user-facing advanced menu. Use valid RoomPlan measurements without asking families to remeasure or approve dimensions.
- Keep automated geometry/connector consistency checks internally. Show a targeted explanation only if a specific issue blocks the requested operation. Trusting captured dimensions does not establish window operability, exterior grade, or structural safety.
- Valid captured dimensions/widths satisfy geometry validation without a separate user-confirmation flag. Audit legacy isConfirmed/verification/measurement prerequisites in import, Save, routing, previews, and rehearsal initialization. Removing the confirmation UI must not leave an invisible gate that makes an otherwise supported home unusable.
- Remove Still to confirm, its badge/count, and dead-end links. Do not rebuild it under another name. Offer scanner room-type suggestions directly in the inspector, with easy correction and reasonable defaults. Semantic uncertainty should not block ordinary editing or saving.

Save and persistence:
- Find the actual failure in the current native branch. Draft bindings, selected IDs, validation, async persistence, dismissal, and downstream observation are investigation areas, not assumed causes.
- Save must commit the current draft atomically through the authoritative home store, increment the home revision once, and return success only after durable persistence. Disable duplicate in-flight commits or make them idempotent.
- Dismiss only after success. On failure, preserve the draft and offer a clear retry; a disappearing sheet is not evidence of a saved home.
- Keep Cancel from partially committing edits. Handle a stale base revision/concurrent scan without silently overwriting newer geometry.
- After success, refresh the home scene, plan/escape previews, route caches, relevant tasks, and new rehearsal context from the same saved revision. Reject stale pending AI proposals. Active exercises retain their identified snapshot or follow the supported refresh/fork path.
- Optional metadata and unconfirmed room-use suggestions must not disable Save. Preserve a draft with a real topology problem and explain its specific route limitation without pretending the route is valid.

Required Mac/iPhone checks:
Import the example scan and save without a measurement/confirmation menu. Select adjacent rooms and different floors; rename/reclassify rooms; switch a door to a window and back; save, leave, force-quit/relaunch, and verify identity, geometry, labels, and dependent previews/routes. Test repeated Save, cancellation, pending updates, and an injected failed write. Confirm no silent success, lost draft, duplicate objects, or dead Still to confirm entry points. Validate touch selection, VoiceOver, large text, and a shallow editing path on the connected iPhone. Linux can test portable reducers and persistence contracts; it cannot certify these native interactions.

Define HomeSceneContext so the agent can reason about the actual home instead of interpreting an unlabeled screenshot alone.

Include:
- Schema/home revision, units, coordinate conventions, per-floor origins/transforms and elevations.
- Stable floor, room, wall, opening, door/window, connector, obstacle, and relevant object IDs.
- Room polygons, adjacency, opening dimensions and operability where recorded, stairs/ramps, exterior access and grade, and known accessible routes.
- Internal provenance and known/unknown status for safety-relevant attributes, without exposing a blanket confirmation queue.
- Recorded room uses and reasonable scanner defaults with provenance/uncertainty; shelter/exit/meetup candidates; storage/equipment locations; and anonymous assistance needs. Room-use defaults can support labeled exercise assumptions without establishing a usable exit or structural shelter suitability.
- Derived graph relationships and current route feasibility from the deterministic core.
- Explicit unknowns: scanner geometry does not establish usable exterior grade, window operability, fire resistance, structural shelter performance, or hidden hazards.

Add an annotated 2D floor-plan image per relevant floor keyed to the same IDs. An optional simple 3D/isometric view can help orientation but cannot substitute for the graph.

Image integration:
- Create a RoomImageManifest with image ID, home/room revision, capture time, orientation, image dimensions, room associations, and actual camera pose/intrinsics/depth provenance when available.
- Record the exact submitted image digest and crop/resize/rotation transforms. Bounding boxes refer to that image. Overlay/projection must use transformed intrinsics and aligned depth, or invert the recorded transforms first. Redacted/unobserved regions provide no negative evidence; missing calibration/transform consistency keeps findings in image space.
- Start with a few selected useful keyframes per room, not the whole scan video. Use quality/coverage selection and an explicit image/token budget.
- Do not assume RoomPlan already persists a photo tour. Specify the Mac implementation needed to capture/select synchronized AR camera frames without disrupting RoomPlan, or offer a short guided photo pass after scanning.
- Redact/minimize sensitive contents before upload where practical, remove unnecessary metadata, show selected images, and allow deletion or manual review instead.
- Gemini supports image understanding and image-space localization; normalize its output in the adapter to a documented bounding-box convention. Image boxes are not metric 3D coordinates. Only the app may project them using actual calibration/depth, and unsupported association stays uncertain. [R4]

HomeObserver output should include:
candidateID, category, room/image/object references where supported, image-space box, visible evidence, suspected concern, alternative explanations/unknowns, review urgency, one confirmation prompt, related source/action IDs, and potential scenario use.

Good candidates include possible clutter obstructing a doorway, a visible cord crossing a walking route, or supply placement that may be hard to reach. The reviewer should explain what was visible and what still needs checking.

Do not claim the model detected carbon monoxide, proved electrical-code compliance, established safe heater clearances without measurements/instructions, verified an alarm works, diagnosed medication requirements, or certified a room structurally safe.

User flow:
- Show a small inline "Review possible concerns" affordance in the existing home view.
- Highlight the image evidence and associated room; allow Confirm, Not an issue, or Not sure with minimal editing.
- Deduplicate repeat observations and remember dismissals unless material evidence changes.
- A confirmed issue can create a linked preparation task and update scenario-relevant facts.
- An uncertain concern can appear as a clearly labeled hypothetical exercise assumption, with permission to use it.
- Detection failure or an unphotographed room must never produce an "all safe" conclusion.

This optional review of a specific photo concern is separate from the removed Still to confirm scan workflow. Ask about the finding that matters; do not require every room, dimension, or opening to be reapproved. Locate a concern in its room/image and connect an accepted finding to its actual preparation or exercise consequence.

Generate reviewable in-app findings, not autonomous emergency alerts or unsolicited push notifications. Keep capture/manual input alternatives equally useful.

10. GENUINELY ADAPTIVE REHEARSAL

10A. ALL SIX DISASTERS MUST BE SUBSTANTIVELY DIFFERENT

This is the highest-priority product correction. Every hazard needs its own drivers, salient state, transition rules, objectives, feasible actions, pacing, visuals, ending conditions, and debrief. A new title, icon, color, paragraph, or event ID over the same blackout -> move someone -> helping sequence fails acceptance.

Implement a hazard specification/adapter in the existing engine for each family, with an explicit supported-mechanics manifest. The director receives the selected hazard and its actual affordances. Shared power, water, geometry, and assistance modules can be composed differently; Gemini directs events within those mechanics. Each local fallback must also remain hazard-aware.

The following are proposed educational abstractions. Sources support lesson content, not predictive fire, flood, temperature, or structural models.

HOME FIRE
- Driver/state: specific ignition room/origin, staged smoke/fire effects through supported room/opening relationships, occupant positions, blocked/reachable exits, and outside household-accounting status.
- Decisions: choose an available escape route from the actual starting room, adapt if a connection becomes unavailable, and account for people at the outside meetup. An extended battery or supply-allocation sequence is not the primary fire experience.
- Consequences: a valid chosen route changes positions and exit status; a blocked path stays blocked. Later events respond to actual progress. A missing route/support arrangement becomes an explicit plan gap, not a magic exit or encouragement to re-enter.
- Scene/debrief: smoke/fire stages, affected connections, current route, outside meetup, and people accounted for. Explain the actual chokepoint, missing second way out, or meetup gap. Vary ignition locations, including an occupied room and the usual exit path. [R13]

TORNADO
- Driver/state: exercise watch/warning/impact stage, building type, interior/window exposure, supported shelter candidates, floor/access constraints, occupants reaching shelter, and alert continuity.
- Decisions: reach an appropriate recorded shelter through a feasible approach; choose concrete accompaniment when a recorded need warrants it; address a usual shelter dependent on unusable stairs. Outdoor reunification is not the default objective.
- Consequences: shelter choice changes modeled exposure and sheltered status. The director responds to who has arrived and the remaining access/alert gap; it cannot certify structural safety from the scan.
- Scene/debrief: shelter/approaches, window exposure, sheltered occupants, and restrained impact/window-damage cues tied to committed events. Do not imply exact predicted glass failure. Explain suitability limits, access, or warning continuity. [R15]

FLASH FLOOD
- Driver/state: explicit exercise flood/evacuation stage, illustrative rising water in applicable low spaces, floor/elevation relationships, affected electrical/access links, reachable supplies, transport, and road/destination assumptions.
- Decisions: use a supported early evacuation arrangement under the exercise's stated official instructions before relevant access is lost. An explicitly trapped case can require identifying a supported refuge or recognizing that none is modeled.
- Consequences: water/access changes alter route and supply feasibility. Lower-room supplies can become inaccessible. A modeled road closure affects the relevant dependency; ordinary directions cannot make it passable.
- Scene/debrief: water in relevant rooms/floors, lost links and supplies, supported paths/refuge, and the decision stage that mattered. Never reuse tornado's lowest-interior-room objective for a flooded basement. Outdoor flooding/access assumptions are explicit, not inferred from RoomPlan. [R16]

FREEZE / POWER LOSS
- Driver/state: extended cold-weather outage, recorded heating/power dependencies, illustrative indoor cooling model/range, backup allocations/energy, phone reserves, and well/medical/storage dependencies where applicable.
- Decisions: compare feasible continuity arrangements, allocate documented backup under competing loads, use available warmth preparations, and consider a supported heated alternative as conditions change.
- Consequences: allocations change computed consumption and later options over simulated hours. A useful preparation averts its corresponding complication. Do not invent medically safe device interruptions or medication storage limits.
- Scene/debrief: indoor temperature trend/range, available heat, energy allocation, and the actual unresolved dependency. A generic escape diagram is not the main display. Heating/generator lesson content uses reviewed guidance. [R14, R17, R22]

HEAT / GRID STRAIN
- Driver/state: extreme heat with potentially functioning electricity, actual cooling options, illustrative indoor warming model/range, water access, and feasible transport/destinations. Grid strain is not automatically a total blackout.
- Decisions: select workable cooling for the recorded household; a later loss of cooling requires adaptation. It is not the mandatory first event shared with freeze.
- Consequences: cooling/backup choices alter available resources and modeled conditions. Account for recorded assistance and storage dependencies without inferring medical tolerance or prescribing fluid intake.
- Scene/debrief: heat trend/range, available cooling, relevant rooms, and supported cooling alternatives. Explain what changed cooling access/continuity. Recolored freeze or a universal turn-on-a-fan answer is insufficient. [R23]

WATER OUTAGE
- Driver/state: separate service availability, quality/advisory category, usable stored volume, access location, and household uses. Include absent-water and flowing-water-under-advisory variants. Power need not fail.
- Decisions: select an appropriate recorded supply for a particular activity, choose feasible use under the exercise advisory, and address inaccessible storage or a supply gap.
- Consequences: consumption deducts from the correct accessible usable inventory. Restoring service does not automatically clear an advisory. Boil-water, do-not-drink, and do-not-use are distinct; boiling is not a generic fix for chemical contamination. [R24]
- Scene/debrief: faucet/service state, advisory, stored-water availability, and affected activities. Do not reuse rising floodwater visuals. Explain the actual quantity, quality, or access issue and next preparation.

For every hazard, demonstrate at least two meaningful decision points with alternative choices producing different valid consequences, plus a household/home variant that changes a feasible option or result. Run all six against the same representative home/household to expose shared-script leakage. Then vary relevant layouts, ignition locations, needs, and supplies. Native scenes and local fallbacks belong in the six-row acceptance matrix; one working row cannot establish completion.

10B. MEANINGFUL ACTIONS AND LEARNING

Remove generic Move someone and Helping as the main visible decisions. Low-level movement/helper primitives may remain internal. A primary action explains what changed, its objective, actor/recipient where relevant, destination or resource, and meaningful constraint/tradeoff.

Examples, only when supported: Take the available back exit to the family meetup; Accompany the child to the selected shelter; Allocate the recorded battery to the specified essential load; Use stored water for this household task. Show concise context before the choices. Assistance performs a defined task; a helper cannot teleport, satisfy incompatible simultaneous duties, or enter an excluded area because a flag says helping.

Let Gemini formulate, compose, and rank contextual options from actual affordances rather than select a few old choice IDs. Support a short alternative-action input without adding chat. A recommended action must be feasible or explicitly identify the missing fact. An incorrect/infeasible attempt receives a specific explanation, never a silent default. Concept checks can teach without resource movement, but must be presented as checks rather than fake physical actions.

Committed physical actions have identifiable state effects. Next-turn context includes those effects and infeasibility results. Debrief claims reference actual events and open the relevant preparation directly. Recognize a sound plan and end appropriately; continually inventing failures is not better agency. Section 12 defines varied practice checks and scoring.

10C. INCREMENTAL HOST AND DIRECTOR ARCHITECTURE

Implement an incremental, serializable SimulationSession and a pure domain reducer with operations equivalent to:

initialize
applyUserAction
scheduleIncident
advanceUntilBoundary
queryState
previewTransition
commit
finish
replay

Keep the existing authored run API as an adapter over that reducer so offline and agent-directed exercises share the same state mechanics.

The app is the authoritative host. At each meaningful boundary:

1) Receive a native action or interpret submitted text into a UserActionIntent linked to that input's ID. Clarify material ambiguity. The host validates and commits the action, or records an unsupported/infeasible attempt, before the next director turn. An engine boundary can also trigger the turn.
2) Build the director's context from that committed result: submitted action and actual effects, current revision/conditions, relevant home/household facts, recent actions, pending incidents, uncertainties, and learning objectives.
3) Let the director select read-only tools, inspect consequences/counterfactuals, choose its next action, or request one useful clarification.
4) If the model needs local tools, the gateway returns typed requests; the app executes them through the core and returns revision-bound results to continue the same operation.
5) The director proposes a bounded incident/decision/pacing plan.
6) The host validates and dry-runs it, commits accepted effects atomically, and returns a receipt.
7) Render scenes, resource balances, route overlays, feedback, and narration from that receipt.
8) The director observes what actually happened and adapts again.

Provide a headless executable over the portable Swift host using a documented transport such as newline-delimited JSON over stdin/stdout. The Linux harness must drive initialize -> user action -> gateway request -> client-tool request/result -> validated proposal -> commit -> next director turn against that running host. Do not rewrite state mechanics independently in TypeScript. Isolate genuinely Apple-only dependencies behind protocols and use honest fixtures for those seams; fixtures must not replace available state/resource/route computations. Report a genuinely unavailable Swift toolchain explicitly.

A DirectorProposal needs session/proposal/request IDs, selected hazard and mechanics version, base revision and event sequence, home/household revisions, context digest, permitted commands, next boundary, purpose, evidence/assumption references, and presentation intent. Validate hazard identity through initialization, gateway, cache, reducer, fallback, scene, and debrief.

Expose a small, composable action language:
- External conditions: power loss/restoration, water-service advisory, communications loss, unavailable destination, modeled road closure.
- Spatial incidents: startIncident(roomID, hazardType, reviewedProfileID), advance permitted hazard stage, affected portal/room relationships calculated by the core.
- Internal user-action primitives: moveTo(destinationID), take/transfer supplies, assign a helper to a concrete duty, allocate a power source, contact a simulated contact, close an operable door, choose a plan alternative. Compose these into the meaningful visible actions in 10B; do not expose raw primitive labels as the experience.
- Pacing: requestDecision, waitUntil(predicate, maximumSimulatedDuration), finishExercise.
- Read-only tools: queryRoutes, inspectRoom, forecastResources, evaluateCandidateAction, inspectDependencyGraph, and runCounterfactual.

Separate user-action commands from director incident/pacing commands by schema and permission. The director can suggest an action but cannot commit occupant movement, supply use, helper assignment, or power allocation without a corresponding submitted user intent. Read-only previews never commit either class of command.

Do not expose unrestricted state patches, arbitrary code, model-authored route coordinates, invented exits, or direct setting of remaining battery/water to a dramatic number.

This still gives the director substantial agency. It chooses incidents, locations, timing, composition, follow-up questions, and which dependency to investigate in response to the family's actions. Reviewed incident profiles bound physical assumptions; they do not prescribe a fixed sequence of questions.

Store a host-enforced DirectorPolicy with permitted hazard families, maximum active incidents, finite scheduling horizon/event budget, and allowed stage transitions. Reject events in the past and define deterministic same-time ordering. These limits constrain valid compositions without choosing the director's sequence.

Interaction:
- Keep the scene-first, key-moment native presentation.
- Let families select a destination/person/object, make a short action choice, or enter an optional single "another action" text/voice instruction that is translated into a validated intent.
- Suggested actions accelerate input without limiting every exercise to predetermined multiple-choice IDs.
- Do not introduce a conversational transcript.
- Feedback follows the committed result. If narration is unavailable, render an accurate local template.
- Distinguish consequences caused by the family's action from a new external complication chosen by the director.
- Let the director acknowledge a sound plan and finish. Do not continually manufacture new failures to punish good decisions.
- Keep unsupported actions explicit; do not silently map them to an unrelated default.

State mechanics:
- Track simulated time independently of wall-clock/network time. A slow response must not burn resources or advance hazards while the user waits.
- Use monotonically increasing event sequence as well as time; multiple actions can occur at the same simulated minute.
- Track electricity, water availability and stored liters, temperature/range when supported, backup energy, documented device loads/runtime, phone/bank capacity, food and relevant supplies, locations, accessibility, occupant/helper state, and pending events.
- Enforce resource conservation, units, simultaneous allocations, nonnegative balances, compatible devices, explicit replenishment, and access constraints.
- Advance to depletion or other mandatory boundaries even if the director requested a later time.
- Represent unknown and approximate values explicitly. Do not invent equipment specifications.
- Implement temperature as a documented educational model or scenario range with versioned assumptions. Home geometry alone does not establish thermal properties or medically safe exposure.
- Keep fire/smoke/flood/tornado visuals synchronized with the same committed hazard fields that affect routing. Educational hazard progression is not a validated prediction of real spread or time to injury.
- Confirmed accessible exits/connectors remain authoritative. Handle blocked starts, unreachable destinations, missing stairs, multi-floor homes, and no supported route explicitly.
- Use explicit destination types for exterior egress, confirmed interior shelter, and scenario-specific refuge. Extend an exterior-only planner before exposing general queryRoutes/moveTo tools. Never relabel an exterior route as a shelter path or remove an affected starting room from hazard exclusions just to obtain a route.
- Preserve hazard-specific distinctions. A room useful for one hazard may be unsuitable for another; do not quietly pick a universal "safest room."

Example dynamic behavior:
A family allocates its only backup battery to a refrigerator. The core computes the actual available energy and remaining allocations. Depending on household facts and the response, the director might explore phone charging, the powered well, or a documented medical dependency. If the family changes the allocation, later consequences must reflect that change. It cannot declare an arbitrary depletion merely because the next scripted question requires it.

Replay and failure behavior:
- Persist initial snapshot, versions, seed, accepted commands, derived events, state hashes, evidence/context digests, and final presentation.
- A random seed does not reproduce model choices. Replays use the committed log and do not call Gemini.
- Enforce idempotency, revision checks, cancellation, atomic persistence, and recovery after app backgrounding/relaunch.
- Do not commit partial streamed output. Reject stale or duplicate proposals without double-consuming resources.
- On timeout/provider failure, retain the same session, resource balances, pending event queue, and history. An eligible Groq director can continue under section 5A, followed by the existing local fallback or pause when necessary. Never restart an authored scenario, replay default choices, reset supplies, or reapply incidents for fallback. Test switching from Gemini to Groq and local continuation without lost/duplicated effects; all six hazards retain their mechanics and acceptance criteria.
- Use any prefetch only for an exact revision and discard it after changes.
- For before/after comparisons, replay the same external incident schedule while varying the intervention. A freshly directed scenario is an alternate exercise, not a controlled comparison.

11. PLAN STRESS TEST

Build a dependency graph across goals, people/helpers, routes/openings, meetups/destinations, contacts, devices, communication channels, transport, power, water, and accessible supplies.

Use deterministic graph checks for obvious single points of failure and let the agent propose additional supported counterexamples. Relevant examples:
- Two apparent exit routes share the same blocked corridor or stair.
- All contact methods depend on one uncharged phone.
- A backup device and several household loads compete for one power source.
- Both meeting locations depend on the same transport route.
- One helper is responsible for two simultaneous assistance needs.
- All supplies are in a room that becomes inaccessible.
- A planned destination's needed capability or activation is unverified.

Distinguish confirmed dependency, plausible hypothesis, and unsupported scope. Having only one recorded contact is a meaningful review prompt, not proof that the family has no other support.

StressTestFinding should identify:
the failed objective, affected household members, minimal/shared dependency where supported, preconditions, executable scenario/trace, confirmed evidence versus assumptions, proposed improvement, related criterion/task IDs, and the outcome after a controlled retest.

Run proposed challenges through the same core. Avoid purely rhetorical plan reviews. Let a resolved finding update the plan and priorities through normal confirmation.

Each scored robustness criterion defines its approved stress envelope, preconditions, and met/unmet/unknown outcomes. Agent search can discover counterexamples within that envelope but cannot enlarge it or invent deductions. More extreme challenges remain advisory unless a reviewed criterion covers them. Hypothetical failures never become claims about current household conditions. Multiple traces exposing one criterion gap produce one assessment, not repeated penalties.

Surface the most important few findings within Plan and the existing debrief. No separate stress-testing dashboard is necessary.

12. A REAL PREPAREDNESS SCORECARD AND AGENT COUNCIL

Implement a transparent numerical score rather than a model's intuitive grade. The score measures preparation documented under a published rubric. It is not a survival probability, prediction of injury, certification, or comparison with other families.

All three requested inputs matter:
- Inventory supports actual resource and accessibility criteria.
- Plan stress tests support robustness findings tied to explicit criteria.
- Eligible simulation performance contributes a bounded practice component and identifies useful learning needs.

Implement a provisional version-0 rubric with fixed budgets, explicit applicability, accepted evidence types, atomic completion predicates, partial-credit anchors, freshness rules, criticality rules, and sources.

Starting household-preparation domains, totaling 100 within the preparation subscore C:
- Protection, escape, and shelter: 25.
- Essential supplies: 25.
- Communication and reunification: 20.
- Household-specific continuity: 20.
- Maintenance and currency: 10.

The sources support individual preparations, not these weights. These are proposed product-policy values to evaluate and revise through a versioned process. Preserve useful existing criteria and remove double-counting.

For each applicable criterion i, use fixed weight w_i and anchored earned credit r_i in [0,1].
Within domain d:
D_d = sum(w_i * r_i) / sum(applicable w_i)
C = 100 * weightedMean(D_d, domainWeights)

Use bounded parent criteria for conditional needs. Multiple people/devices divide a predetermined criterion budget or use explicit predefined subcriteria; generating more tasks cannot create more points.

Statuses:
- Met.
- Partly met, with explicit subpredicates.
- Unmet: evidence establishes a gap.
- Unknown: insufficient evidence; no earned credit, but not mislabeled as a confirmed failure.
- Not applicable: removed only by a published applicability rule.
- Outside supported scope: disclosed, never counted as satisfied.

Keep unresolved applicability in its fixed parent budget as unknown; exclude only criteria confirmed not applicable by a published rule. Redistribute a domain's weight proportionally only if all its criteria are confirmed not applicable. Unsupported or unassessed criteria do not qualify. If no domain is evaluable, display "Not assessed," not 100. Calculate household evidence coverage with the same domain-weighted formula, substituting assessed-predicate fractions for earned credit; confirmed failures count as assessed. Report practice coverage separately. Preserve snapshots and identify scope/rubric changes instead of presenting denominator changes as earned improvement.

Practice component P:
- Use four equally weighted competencies: appropriate initial response; adapting when a route/shelter option fails; using the communication/reunification/assistance plan; handling a relevant continuity dependency.
- Grade anchored actions from committed traces: independently correct, defined partial credit, incorrect, or unassessed.
- Unsafe choices earn zero on the assessed anchor; any broader restriction must be an explicit rubric rule. Feedback never retroactively changes the original answer.
- Collect comparable evidence from an optional short "Practice check" within the existing Rehearse flow using approved equivalent variants. Guided/adaptive training still provides feedback and insights but arbitrary scenario difficulty cannot directly determine the score.
- Use the latest eligible evidence for each atomic rubric anchor, keyed by household, rubric, competency, anchor ID, relevant hazard/scope, and stable subject where applicable. Preserve evidence revisions separately. Variant IDs identify attempts, not new scoring scopes. A short check updates only the anchors it assesses; it cannot overwrite other hazards, subjects, or competencies. Do not use a best-attempt maximum or drill count.
- Persist attempt and variant identity, assessed competencies/hazard scope, committed pre-feedback answers, grading anchors, and evidence revisions. Interruptions resume the same attempt. Restarting cannot erase contrary observed evidence or silently reroll an easier variant.
- Track hazard coverage separately; one fire check cannot claim knowledge of all six disasters. Where a criterion requires multiple hazard anchors, define fixed subpredicates/weights in the rubric before generation and aggregate only their eligible evidence. More generated questions never enlarge a competency's fixed budget.
- For an incomplete attempt, retain its observed results and explicit unanswered state without clearing unrelated assessments. Retest with a genuinely equivalent variant. Keep older results in history and never hide a newer eligible incorrect result behind an older success.
- Only a newly observed eligible answer supersedes prior evidence for the same anchor. Starting, canceling, or leaving a question unanswered does not erase a prior valid answer. Report partial anchor coverage without claiming the whole competency has been assessed.
- Track each anchor's relevant dependency fingerprint and freshness rule. Material preparation/home changes invalidate only dependent evidence and can schedule a targeted retest. Renames, display-label changes, and unrelated edits do not revoke credit. Preserve invalidated evidence in history and explain any score change.
- VoiceOver, translation, alternative input, and additional reading time are accessibility support, not coaching. Provide an equivalent text/manual option with the same grading anchors.
- Do not score reaction speed, expensive equipment, photo quality, LiDAR ownership, physical ability, animation completion, or the number of rehearsals.
- Until variant comparability is evaluated, mark practice results provisional and avoid invented difficulty multipliers.

Practice-check variety and meaning:
- Replace the single generic persistent check with a bank spanning all six hazards. As an initial content gate, provide at least two distinct check objectives per hazard, each with alternate equivalent variants. Reuse competent existing content where it meets these requirements.
- Examples: fire route choice and household accounting; tornado shelter/access and alert continuity; flood early evacuation decisions and loss of access; freeze warmth/continuity and competing backup loads; heat cooling access and adapting to lost cooling; water usable-supply selection and advisory distinctions. These are content objectives, not twelve new score budgets.
- Each check presents a concrete situation, a useful goal, and an assessable choice. State which competency/predicate it measures and why the decision matters. Recognizing an unrecorded arrangement or unsupported route can be the appropriate result.
- Gemini personalizes the context/options to current facts and valid mechanics. Keep grading anchors, difficulty/comparability rules, and eligibility fixed; changing the prose must not change which answer earns credit secretly.
- Prefer a short relevant check based on an unresolved learning need, a material changed preparation, or an unassessed hazard. Keep one clear next check or a compact choice in existing Rehearse; do not create another navigation area or endless queue.

Completion, persistence, and score refresh:
1) Commit the attempt/answer evidence with stable instance IDs and first-answer grading. Deduplicate double taps and late model responses. Make persisted completion recoverable/idempotent across relaunch.
2) Retire that completed check instance from the active queue, including an incorrect completion. Keep it in history; a later retest is an intentional equivalent variant, not the same stuck card. If there is no useful next check, show an honest completed/current state.
3) Update only the assessed competency evidence and compile the score from the latest accepted evidence and fixed rubric. Trigger observation/invalidation for every native score surface and the practice queue. Display the updated practice component and explanation immediately after the local commit; a council/network response must not block it.
4) Persist/derive the score snapshot with its evidence revision. Recompute recoverably after a crash; reject stale asynchronous assessments that would overwrite newer evidence. Cosmetic household edits must not resurrect all completed checks.
5) Completion does not guarantee earned points. An incorrect answer, an already-current result, rounding, or a critical cap may leave the headline number unchanged; the component/result and reason must still update. Never animate a fabricated increase to imply progress.

Regression cases: completed checks stay retired after relaunch; one check preserves other competency results; repeated drills cannot stack credit; cancellation/interruptions retain answered evidence; incorrect results do not retain an older best score; double taps cannot grade twice; preparation changes trigger appropriate targeted retests; score views agree after refresh; council timeout/stale results cannot undo newer practice. Test all six check families, supported languages, and accessible alternatives.

Include a medication-storage change that invalidates its dependent continuity anchor while preserving unrelated route/communication evidence, and a member rename that changes neither practice credit nor completed-check status.

Overall proposed score:
Base = 0.90 * C + 0.10 * P
Overall = min(Base, applicableCriticalGapCap)

C is the uncapped preparation subscore. Each atomic practice anchor earns 1 for independently correct, 0.5 only for explicitly anchored partial credit, or 0 for incorrect/unsafe; unassessed earns 0 with unknown status. For competency k, compute c_k as the fixed-weight mean of its applicable rubric anchors. Unknown/unresolved anchors keep their weight; exclude only anchors confirmed not applicable under a frozen rule. Subject-specific anchors divide a predetermined parent budget. An unevaluable competency remains unassessed with c_k = 0. P = 100 * (c_1 + c_2 + c_3 + c_4) / 4. Define the anchor/weight/applicability map before generating checks; added questions do not add weight. Use the lowest triggered critical cap, or 100 if none applies. Apply the cap after combining C and P; round only the displayed result.

When practice/evidence is unassessed, retain the fixed possible contribution, show the unresolved portion/coverage, and label the overall result provisional. Do not normalize only over successful or answered criteria.

Candidate critical-gap policy for evaluation:
- A known unresolved critical requirement caps the score at 59.
- An unverified critical requirement caps the score at 79.
- Otherwise, use the base score.
These numbers are provisional policy, not official safety thresholds. Encode them as versioned rubric configuration and show the specific reason for a cap. A model cannot invent a critical classification.

Example: C = 76; all practice competencies are unassessed, so earned P = 0 and Base = 68.4. The household explicitly reports no usable alternative for an essential powered device, triggering a known-critical-gap cap of 59. Display:
"Preparedness 59/100 · provisional"
"Household preparations 76 · Practice not assessed"
"Limited by a confirmed gap in essential-device continuity"
"Household evidence assessed: [computed coverage] · Practice: 0/4 assessed"
Then the three most useful improvements and the existing How this is scored explanation. Remove the rubric-version label from the bottom of that user-facing view. Keep its version in internal score records, migrations, logs, and evaluation artifacts; explain points, evidence, practice contribution, and any cap in ordinary language. Missing backup documentation alone must not be reclassified as confirmed absence.

Avoid green "safe" labels, leaderboards, competitive family rankings, and shame-based messaging. An equally suitable low-cost solution earns equal credit. Budget changes feasible next steps; it does not fabricate supplies or conceal gaps.

Council:
1) Coverage/safety reviewer checks applicable requirements, source fit, and serious omissions.
2) Evidence/consistency reviewer checks unsupported credit, duplicates, contradictory facts, and denominator mistakes.
3) Feasibility/fairness reviewer checks accessibility, household fit, cost assumptions, and presentation/demographic bias.
4) A bounded adjudication pass resolves evidence-linked disagreements against the frozen rubric; unresolved facts remain unknown or lead to one useful question.

Give first-pass reviewers the same frozen evidence without each other's conclusions or the proposer's identity. Independent prompts are not statistically independent experts. Do not average confidence scores, vote a disputed fact true, or let the council silently change weights for one family.

The deterministic scorer computes the number from the accepted assessments. Agents can recommend evidence interpretations and explain them; validated facts/rules decide credit. Model-generated interpretations that would materially change household facts still follow the proposal/review path.

Make rubric improvement a development process: draft -> independent critique -> development tests -> locked holdout -> relevant human review -> versioned release. Models must not continuously rewrite the rubric in production. LLM judge research documents ordering and self-preference biases, so explicitly test those patterns rather than assuming a council removes them. [R18-R19]

13. TESTING AND EVALUATION THAT SUPPORT THE CLAIMS

Implement and run tests for the actual risks. Keep deterministic tests separate from live-model quality evaluation and native-device verification.

A. Contracts and service:
- Cross-language fixture round trips, missing/null/unknown values, enums, units, bounds, invalid IDs, and schema migrations.
- Authorization, quotas, TTLs, cancellation, replay, forbidden data fields, no secret leakage, prompt injection, unauthorized URL/tool attempts, and private-cache isolation.
- Provider protocol fixtures from the actual installed SDK, including multi-step stateless tools, structured completion, refusal, timeout, malformed responses, and one bounded repair.
- Startup behavior with missing credentials and production authorization misconfiguration.

B. Spatial and simulation:
- Maintain a six-row scenario coverage report with initial driver, supported state, two meaningful branching decisions, household/layout variant, distinct visual/debrief expectations, local fallback, and actual verification status for each hazard. All six rows are required; mark native checks pending until performed on Mac/iPhone.
- Run all six with the same representative household/home and compare causal state transitions and action semantics. Assert hazard identity across selection, context, cache, director, reducer, scene, fallback, and debrief. Different text/IDs alone cannot pass the differentiation gate.
- Same committed log gives identical state/route hashes offline.
- Duplicate/stale/out-of-order proposals and failed atomic persistence cannot double-consume resources or corrupt the session.
- Conservation, simultaneous power allocation, access constraints, unit conversion, depletion boundaries, and temperature assumptions.
- Current example floor plan plus varied houses: studio/apartment, one floor, multiple floors, split levels, disconnected/missing connector, inaccessible stairs, narrow/blocked portal, ambiguous exterior windows, and a home without an appropriate confirmed shelter.
- Vary fire starting rooms/portals, flooded low areas, tornado assumptions, occupants/helpers, and supplies. Include a person starting in an affected room and no supported route.
- Unsupported geometry and photo observations cannot manufacture routes or confirmed safety.
- External incident schedules stay controlled in before/after intervention tests.
- Test past-time incidents, scheduling-budget exhaustion, fallback/resume, interior routing, and source household/home edits during a session. Source edits invalidate pending proposals and require a supported snapshot refresh/fork or continuation against the identified original snapshot; never mix old geometry with new facts.
- Demonstrate that distinct household actions yield materially different valid continuations and that the director creates sequences beyond the old fixed choice IDs.
- Add cross-hazard negatives: flood cannot inherit the tornado basement objective; water-service loss cannot create floodwater; heat can start with functioning power; fire cannot default to a multi-hour battery drill; a no-cloud fallback cannot silently turn every scenario into an outage.
- Exercise direct room/opening edit reducers and atomic persistence where portable. Verify identity/geometry retention after Door/Window changes, route invalidation, stale revisions, failed saves, and cancellation. Leave native hit testing, actual durable Save, 2D/3D synchronization, and relaunch checks explicitly for Mac.
- Import a fixture whose captured geometry and recorded exterior/access facts support a route. Save, generate its route/preview, and start rehearsal without a measurement/confirmation screen. A missing manual confirmation flag alone must not block the path. Separately verify that genuinely unknown exterior/operability facts remain unknown.

C. Inventory, tasks, resources:
- Two adults versus infant + dog + powered-device household.
- Mutate recorded disability/functional need, medication storage instruction, apartment/multistory context, and missing extinguisher independently. Inspect actual serialized role inputs and relevant output changes; reject unsupported functional/clinical inferences. Include already-owned and unrecorded versus confirmed-absent cases.
- Duplicate images/items, unreadable labels, unknown quantities, expiry, inaccessible supplies, shared battery capacity, missing device specifications.
- Priority constraints, subject-specific tasks, no duplicate shopping, and limited actionable recommendations.
- Ambiguous addresses, no results, rural distances, no-car travel, outside-source-pack regions, closed/unknown services, stale official records, and prompt injection in resource text.
- No invented inventory, shelter activation, hospital capability, retailer stock, or route safety.
- Verify that actual supported facts drive the resource explanation and checklist link.
- Prove automatic named-resource research beyond the bundled county, without manual records, URLs, or source-pack selection. Distinguish a useful qualified result from fabricated stock/activation; verify attribution and permitted data handling through the actual provider adapter.
- Evaluate For your family observations and task proposals for evidence, implication, concrete action, fit, and redundancy. A changed name or added generic sentence is not substantive personalization.

D. Rubric/council:
- Create at least 60 distinct synthetic household cases, separating a development set from a locked holdout before prompt tuning. Include incomplete/conflicting facts and diverse supported home/assistance/budget situations.
- Specify source-backed expected criteria and representative reference assessments with explicit author/review status. Reserve "human-adjudicated" for cases actually reviewed and resolved by independent qualified people. Do not use another unconstrained LLM as the sole ground truth.
- Run deterministic score/rubric tests across all cases and targeted mutations.
- On a budgeted representative subset, repeat live agent/council assessments at least three times; record actual households, model calls, versions, costs, and unrun cases. Expand only to resolve observed failures or satisfy the evaluation gate.
- On the same representative subset, compare deterministic baseline assessment, one reviewer, and the council against independent reference expectations. Report whether the council improves supported assessments or critical-gap detection, alongside added calls, cost, and latency. If holdout findings inform changes, those cases become development evidence; use fresh untouched cases for another held-out claim.
- Hold relevant facts constant while changing wording length, names, language, evidence order, reviewer/proposer identity cues, photos versus equivalent typed facts, and budget description.
- Score arithmetic must be identical for identical accepted facts/rubric. Removing a valid resource cannot improve its criterion; adding duplicates cannot inflate credit; equivalent low-cost preparations receive equal credit.
- Unknown cannot become N/A to improve the score. A pantry improvement cannot clear an unrelated critical cap. A repeated drill cannot repeatedly earn points.
- Test comparable practice variants, coaching boundaries, accessibility equivalents, incomplete checks, and harder arbitrary scenarios.
- Run section 12's practice lifecycle regressions against persisted attempts and the score compiler: retirement/replacement, per-competency updates, fixed budgets, no duplicate credit, caps/rounding, no network dependency for local refresh, and recovery after relaunch.
- Report critical false passes, unsupported-claim acceptance, criterion/applicability agreement, useful-priority relevance, inventory error, abstention quality, and score stability.
- Report sample sizes and uncertainty at the household level; reruns and variations of one case are not independent households.
- Known critical invariant violations must be fixed before calling the affected path complete. A finite passing test suite is evidence of behavior, not proof of real-world safety.

E. Image evaluation:
- Use rights-cleared, consented, or explicitly synthetic room/image fixtures with annotated intended observations and hard negatives.
- Include lookalikes, partial views, poor light, missing camera calibration, conflicting images, hidden/absent evidence, and adversarial image text.
- Separate image-level localization from supported home-graph association. Test rotated/cropped/resized frames against original camera calibration and ensure redaction never becomes negative evidence.
- Report actual vision limitations. Passing labeled diagrams or synthetic images is not evidence of validation on real household scans.
- Leave a concrete Mac photo-capture/inspection validation script when real scan images are unavailable.

F. Human/device evaluation:
- Prepare reviewer materials for emergency-preparedness content, relevant accessibility needs, and manufacturer/clinical information boundaries.
- Prepare a small consent-based family usability protocol: time/steps to reach three useful tasks, comprehension of "unknown," correction effort, recall, and whether a concrete preparation was completed.
- Do not claim a responder, clinician, family, or competition judge reviewed anything unless it actually happened.
- Supply the Mac session with exact end-to-end cases, fixtures, expected state transitions, and native visual checks.
- Include the reported warning/text shift, urgent No cost coloring, duplicate-looking name labels, disability dropdown capitalization/localization, family-card alignment and specificity, removed reconnection/version labels, direct room editing/Save, removed Location records, and completed-check/score refresh in the native acceptance script. Validate ordinary and large text, VoiceOver, and existing supported locales.

G. Meaningful live-agent quality:
- Evaluate the actual model path after schema validation/rendering, not just raw impressive prose in a provider console. Check whether current validators, context omission, fixtures, fallbacks, or UI truncation erase useful content.
- Use paired household/context and user-action mutations. Record evidence-linked changes in useful tasks, location comparisons, offered actions, actual continuation, and debrief. Check for repetitive generic fallback even when calls technically succeed.
- Keep instructions/schema limits around supported facts, executable effects, and budgets. Permit grounded task generation, bounded investigative tool use, and varied incident composition. Extend a justified missing domain affordance instead of faking it in narration or suppressing all meaningful alternatives.
- Preserve a substantive adaptive trace per hazard. Budget live runs honestly; if any are unrun, identify those rows instead of claiming all-six maturity. Use privacy-safe synthetic context and label recorded/mock traces accurately.

H. Additional provider fallback and real-search acceptance:
- Force a Gemini 429 at the adapter boundary, then complete a live Groq browser_search operation for a public locality outside Tarrant County. Return supported named options and meaningful differences through the existing result contract. Where typed extraction is required, it runs on Groq with no recovery-time dependency on Gemini. Label the injected primary failure and the genuinely live fallback separately.
- Capture and sanitize an actual response fixture for the configured Groq model/API/SDK, then test source parsing and output normalization. Plain chat, unresolved citations, invented URLs, disabled/unsupported tools, and schema-valid unsupported claims cannot pass as live research. tool_choice: required is a request setting, not evidence of a successful search.
- Preserve partial supported results and original source dates. Distinguish no matches, unavailable search, unresolved evidence, cached information, and an extraction failure. The fallback schema cannot force fabricated values or discard a useful attributable answer just because not every field is known.
- Exercise relevant quota/reset headers, circuit cooldown/half-open behavior, missing/invalid credentials, both providers rate limited, cancellation, and incompatible tool/schema requests. Prove retries, internal extraction, continuation, and repair share one bounded budget and cannot multiply through SDK defaults or provider ping-pong.
- Inject a late Gemini proposal and a late native-tool response after Groq takes over, including unchanged host revisions. Both are fenced. Test duplicate callbacks and lost commit acknowledgement; reconcile durable receipts before continuing and never double-consume resources or credit practice twice.
- Reuse the existing six-scenario suite to verify hazard identity, mechanics, state/resource/time continuity, meaningful actions, replay, and score invariants across the new provider route. Run budgeted live Groq quality checks for eligible roles; mark any untested provider/hazard combinations honestly. Search success alone does not complete rehearsal or assessment fallback.
- Verify both private adapters receive the relevant member-linked disability, medication/storage, equipment, dwelling, and supply context. Verify none of that private context leaks into public research. Revoked consent cancels jobs; Gemini-only consent does not silently authorize private Groq traffic.
- Test image-dependent capability routing. A text-only fallback must not claim to inspect a photo or silently omit a required image; eligible text/search/home-graph work can continue while the image result remains pending or uses an evaluated supported path.
- Keep existing Plan/task/MapKit integration and data-use requirements. No new user record curation, URL entry, provider chooser, or third-party search key is required by the documented Groq browser_search path. Account/model access or quota blockers must be reported accurately instead of replaced with mocks labeled live.

Produce an evaluation report with clear "passed on Linux," "live model tested," "synthetic only," "native pending," and "human review pending" categories. Include provider/model and fallback-path coverage; never report an unrun test as passed.

14. IMPLEMENTATION SEQUENCE AND DELIVERABLES

Work in integrated slices and keep them runnable. Mature verified existing implementation instead of rebuilding services or native screens from prose.

Additive integration work: inspect progress against the same milestones, then implement section 5A within the existing provider boundary and section 13H within the existing acceptance suite. Start with a real search fallback slice because that is the owner's stated concern, then cover the other eligible roles and state continuity. This adds resilience work; it does not replace, narrow, defer, or satisfy any original feature milestone. Preserve completed work and use targeted regression evidence rather than restarting the project.

Milestone 1 — Reconcile and trace the current failures.
Verify branch/commit and state owners; trace all six scenario selections and host/director/rendering paths, required household-context fields, room Save, and practice-to-score updates. Run available baselines and record actual causes. Start the Mac reproduction/editing handoff immediately so native fixes are not left as vague last-minute suggestions. If the host/provider/tool loop already exists, extend it. Otherwise implement the smallest real incremental loop before adding role scaffolding.

Milestone 2 — Make all six disaster experiences distinct.
Implement each hazard's drivers/state/actions/consequences, meaningful choices, fallback, replay, and scene/debrief contract. Demonstrate every row of section 10's matrix with branches and relevant household/home variations. Develop the shared room-edit/persistence changes required for valid home context in parallel under clear file ownership. This is the highest-priority feature gate; additional AI prose or score polish cannot substitute for missing hazards.

Milestone 3 — Make planning and resources household-specific.
Trace recorded disability/assistance/medication/equipment/dwelling/inventory facts through Gemini and into applicable tasks and For your family observations. Permit grounded bespoke preparations, deterministic supply gaps, and automatic research of useful named local options. Demonstrate a material household change producing a substantive change in recommendations, including outside the initial region. Remove the Location records requirement.

Milestone 4 — Complete the practice and assessment loop.
Create varied meaningful checks across the six hazards. Implement completion/retirement/retest persistence, per-competency evidence, immediate score invalidation/refresh, executable stress tests, the fixed rubric, and bounded council. Test that scores reflect accepted evidence without duplicate points or stale asynchronous overwrites. A local practice result must not wait for Gemini to update the UI.

Milestone 5 — Finish home/image integration and native simplification.
Complete scene/image context, targeted concern review, and links into tasks/scenarios. Deliver direct room/opening editing, trusted captured dimensions, no Still to confirm, and durable Save semantics. Coordinate the exact native task-row, family editor/card, reconnection, scoring-label, resource, and practice changes in sections 2, 8, 9, and 12. Preserve working PDFs/card privacy selections and shallow navigation. RoomPlan capture and the image path must be concretely ready for the Mac/iPhone Pro verification; contracts alone do not establish device completion.

Milestone 6 — Validate integrated behavior and report completion honestly.
Run the relevant contract, domain, live-model, rubric, and regression evaluations. Prepare the six-scenario coverage report, current status of every reported issue, runnable fixtures/replays, and precise Mac handoff. Fix portable failures. Record each native/human test still outstanding without marking the app complete while these required outcomes remain unverified.

Suggested repository deliverables, adapted to current conventions:
- Working private AI service/role configuration, official SDK adapter, tools, schemas, validation, and non-secret configuration.
- Shared contracts and cross-language fixtures, including member context, home edits, attributed resource output, scenario identity/actions, practice evidence, and score invalidation.
- Portable state/reducer, inventory/evidence, edit/persistence, stress-test, and scoring changes.
- Versioned guidance/action/rubric content and automatically maintained permitted source evidence.
- Headless host/agent evaluation runner, development/holdout fixtures, adversarial/mutation tests, and exact commands.
- docs/ai/architecture.md, data-flow.md, rubric.md, evaluation-report.md, six-scenario-coverage.md, corrective-issue-status.md, and mac-integration-handoff.md, or equivalent established files.
- A meaningful adaptive trace per hazard, useful context/resource examples, and privacy-safe demonstration households; distinguish live calls, recorded real outputs, and mocks.

The Mac handoff must identify:
- Exact branch/commit, verified files/symbols, shared-file ownership, migrations, and compatibility assumptions.
- Native protocols/DTOs with real call/response fixtures and state owner/acceptance points.
- Scene selection and incremental synchronization for every hazard, meaningful action options, and hazard-specific fallback/replay.
- Room canvas hit testing/selection, compact inspector, in-place Door/Window switch, removed dimensions/confirmation UI, Save transaction, failure/cancel behavior, and all downstream invalidation.
- The stored-member -> outbound-context -> native personalized-result path, including disability/medication information and local display names.
- MapKit candidate/overview/attribution handling, automatic research integration, removal of Location records, and use beyond Tarrant County.
- Groq fallback contract/status/source presentation, existing cloud-disclosure update where needed, cancellation/resume behavior, and the exact Gemini-unavailable native verification case. Backend search can be verified on Linux; Apple-map rendering and iPhone behavior still require Mac/device checks.
- RoomPlan/AR image selection, calibration, redaction, deletion, and fallback capture on a supported iPhone Pro.
- Consent, Keychain/authorization handshake, background/resume/cancellation, and data-sharing controls.
- Practice bank, queue retirement/replacement, persisted attempts, component/headline score updates, caps, and relaunch behavior.
- The exact task-warning placement/urgent styling, family labels, For your family layout/icon/content, and removed reconnection/rubric labels.
- Locale, VoiceOver, Dynamic Type, reduced-motion scene support, and critical-language checks.
- PDF/card integration using accepted household content and permitted map data; do not export raw agent deliberations.
- Reproduction steps, expected observable results, actual passed tests, and outstanding Xcode/iPhone checks.

Definition of done on Linux:
- Real provider workflows and substantive domain behavior exist; the implementation does not consist only of schema shells, mocked strings, or design notes.
- A synthetic household goes through personalized preparations, researched-resource integration, inventory, stress test, adaptive rehearsal, and score compilation using the documented host protocol.
- All six portable scenario rows implement and demonstrate their distinct state/actions/consequences, supported branches, and fallback. Each has an evaluation status and an honest live-model/native verification status.
- The user's corrective requests each map to a concrete implementation and relevant test or an explicit Mac integration dependency; none disappear into an unspecified later audit.
- Confirmed household edits invalidate relevant planning context; practice evidence updates the deterministic score; home-edit persistence contracts handle real failure cases.
- Failures preserve valid local state and useful fallback. Scores remain reproducible under a frozen rubric and accepted evidence.
- Groq fallback includes actual sourced research under a simulated Gemini quota failure, capability-aware routing, shared operation budgets, and fenced state continuity. Its integration preserves the same product outcomes and all-six-hazard gates; section 13H records live, fixture, and pending coverage.
- Contracts and runnable fixtures make native work concrete. Native UI/RoomPlan/Save completion is established only by actual Mac/device testing.
- If provider access, credentials, budget, toolchain, or a newer native branch blocks verification, complete unaffected work and state precisely which tests/changes remain pending. Do not fabricate success or hide an unfinished hazard behind aggregate completion.

15. IMPACT AND DEMONSTRATION

Use a coherent, honest community story to explain the benefit, while demonstrating maturity across all six disasters:

A family with an infant, a dog, and a powered-device dependency imports its actual needs, confirms existing supplies, sees three relevant actions, identifies suitable preparation resources, and practices a home-specific outage/storm scenario. The exercise reveals a shared battery, inaccessible supplies, or a brittle contact/route. A confirmed improvement changes the plan, the controlled retest, and the explained score.

Pair it with a two-adult/no-special-dependency household to demonstrate real personalization. Show manual home input and offline fallback so the benefit is not limited to people with a LiDAR iPhone.

Include a brief six-hazard comparison using the same home so the audience can see different objectives, meaningful actions, and consequences. One flagship outage demo does not establish that the remaining five scenarios work. Show a completed practice check leaving the queue and its explained score update, plus a saved room/opening correction surviving relaunch when Mac verification is available.

The strongest evidence of impact is an understandable chain:
observed/recorded need -> useful recommendation -> completed preparation -> fewer supported plan failures.

Use the existing shareable plan/card to extend household benefit without requiring every family member to use cloud AI. Do not add a social network, leaderboard, or public upload of private home plans.

Prepare a short demo script and measurable usability/quality results from actual tests. Clearly label synthetic fixtures and recorded replays. Do not invent user adoption, safety outcomes, expert endorsement, or competition results.

16. RESEARCH REFERENCES AND HOW TO USE THEM

Research baseline checked 2026-10-19; Search/URL Context discovery, the six-hazard lesson sources, and Groq fallback documentation were checked on 2026-10-20 UTC. Recheck provider APIs/models/terms at implementation time. Documentation research does not establish that the app's actual Groq account/key, quotas, or deployed fallback work; the coding session must perform the synthetic live tests. Architecture choices, educational mechanics, and numeric rubric values are proposals; official sources do not validate DryRun as a predictive safety system. Keep app guidance short, accurately sourced, versioned, and appropriate to its jurisdiction. Do not indiscriminately copy source pages into prompts or ship a legal essay in the user flow.

R1. Gemini Interactions:
https://ai.google.dev/gemini-api/docs/interactions-overview

R2. Gemini function calling:
https://ai.google.dev/gemini-api/docs/function-calling

R3. Gemini structured output:
https://ai.google.dev/gemini-api/docs/structured-output

R4. Gemini image understanding:
https://ai.google.dev/gemini-api/docs/image-understanding

R5. Official SDK/key security and ADK:
https://ai.google.dev/gemini-api/docs/api-key
https://google.github.io/adk-docs/

R6. Gemini API terms, including data handling, audience, and grounding:
https://ai.google.dev/gemini-api/terms

R7. Grounding capabilities and tool combinations:
https://ai.google.dev/gemini-api/docs/maps-grounding
https://ai.google.dev/gemini-api/docs/google-search
https://ai.google.dev/gemini-api/docs/tool-combination

R8. Google Places setup and content policies:
https://developers.google.com/maps/documentation/places/web-service/get-api-key
https://developers.google.com/maps/documentation/places/web-service/policies

R9. Apple App Review Guidelines, especially personal-data sharing:
https://developer.apple.com/app-store/review/guidelines/

R10. Apple Developer Program License Agreement, Attachment 6:
https://developer.apple.com/support/terms/apple-developer-program-license-agreement/

R11. CDC emergency water supply:
https://www.cdc.gov/water-emergency/about/how-to-create-and-store-an-emergency-water-supply.html

R12. American Red Cross emergency plans:
https://www.redcross.org/get-help/how-to-prepare-for-emergencies/make-a-plan.html

R13. USFA home fire escape plans:
https://www.usfa.fema.gov/prevention/home-fires/prepare-for-fire/home-fire-escape-plans/index.html

R14. FDA medical devices and natural disasters:
https://www.fda.gov/medical-devices/emergency-situations-medical-devices/fda-offers-tips-about-medical-devices-and-natural-disasters

R15. National Weather Service tornado guidance:
https://www.weather.gov/safety/tornado-during

R16. National Weather Service flood guidance:
https://www.weather.gov/safety/flood-during

R17. Consumer Product Safety Commission carbon monoxide information:
https://www.cpsc.gov/Safety-Education/Safety-Education-Centers/Carbon-Monoxide-Information-Center

R18. Wang et al., Large Language Models are not Fair Evaluators, ACL 2024:
https://aclanthology.org/2024.acl-long.511/

R19. Panickssery et al., LLM Evaluators Recognize and Favor Their Own Generations, 2024:
https://arxiv.org/abs/2404.13076

R20. Current model pricing:
https://ai.google.dev/gemini-api/docs/pricing

R21. Gemini URL Context, including combination with Google Search for automatic discovery and reading:
https://ai.google.dev/gemini-api/docs/url-context

R22. National Weather Service cold-weather and power-outage guidance:
https://www.weather.gov/safety/cold-during

R23. National Weather Service heat and grid-strain guidance:
https://www.weather.gov/safety/heat-during

R24. CDC drinking-water advisories, including distinct boil, do-not-drink, and do-not-use conditions:
https://www.cdc.gov/water-emergency/about/drinking-water-advisories-an-overview.html

R25. Groq deprecations, including Compound model retirement:
https://console.groq.com/docs/deprecations

R26. Groq Browser Search and supported built-in tools:
https://console.groq.com/docs/tool-use/built-in-tools/browser-search
https://console.groq.com/docs/tool-use/built-in-tools

R27. Groq Structured Outputs, supported models, and tool/streaming limitations:
https://console.groq.com/docs/structured-outputs

R28. Groq rate-limit headers and error behavior:
https://console.groq.com/docs/rate-limits
https://console.groq.com/docs/errors

R29. Groq API reference, official TypeScript SDK retry/timeout behavior, and response types:
https://console.groq.com/docs/api-reference
https://github.com/groq/groq-typescript
https://github.com/groq/groq-typescript/blob/main/src/resources/chat/completions.ts

R30. Groq data handling and current model capability/status listings:
https://console.groq.com/docs/your-data
https://console.groq.com/docs/models

R31. Gemini project-scoped limits and troubleshooting:
https://ai.google.dev/gemini-api/docs/rate-limits
https://ai.google.dev/gemini-api/docs/troubleshooting
