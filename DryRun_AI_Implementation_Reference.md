DRYRUN AI IMPLEMENTATION REFERENCE

Purpose
This is the detailed product and engineering specification for DryRun's Gemini integration. Its companion launch prompt is DryRun_AI_Fresh_Context_Goal.txt. Keep this document available to the coding agent and consult it throughout implementation.

Operating context
The coding session starts without previous conversation context and works in an existing native iOS repository on Linux. A separate Claude session on an Xcode-enabled Mac with a connected iPhone owns native integration and device verification. The objective is a working, evaluated architecture with concrete native integration contracts.

How to use this reference
- Read the product, repository, architecture, and authority requirements before designing.
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
6. Shared contracts, evidence, revisions, and proposal acceptance.
7. Personalized preparations and supply inventory.
8. Automatic nearby resources and map integration.
9. Home geometry, optional images, and concern review.
10. Incremental adaptive rehearsal, state, tools, replay, and fallback.
11. Dependency analysis and executable plan stress tests.
12. Numerical scorecard, practice credit, rubric, and agent council.
13. Contract, domain, model, image, rubric, and human/device evaluations.
14. Implementation sequence, deliverables, Mac handoff, and definition of done.
15. Community impact and demonstration.
16. Research sources and re-verification guidance.

The detailed requirements follow. The original research baseline is 2026-10-19; section 16 identifies provider information to recheck at implementation time.

1. PRODUCT INTENT AND CURRENT BASELINE

DryRun helps families make useful emergency preparations, discover weaknesses in their plans, and practice responding to realistic situations in their own home. It should turn incomplete household knowledge into a few concrete improvements with minimal effort.

Product vocabulary:
- Household: family/household members, roles, assistance needs, trusted contacts, and relevant medical/power/storage dependencies.
- Home: a manually editable or RoomPlan-derived representation of rooms, floors, doors/windows, connectors, and relevant locations. Scanner suggestions and user-confirmed facts have different authority.
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
- Home/RoomPlan has clearer labeled 3D views, corrected floor-mesh winding, collapsible family details, and scanner room-type suggestions that require confirmation.
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
3) Trace one rehearsal from native entry through AppModel, domain state/routing, persistence, and scene presentation. Trace one household edit through preparation/plan invalidation.
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
- Authenticates app requests, enforces per-installation and global budgets, invokes Gemini, validates tool calls/output, and handles cancellation and errors.
- Runs a handful of roles using versioned prompts and role-scoped tools.
- Retains private job state only when required for a bounded operation, with an explicit short TTL.
- Returns proposals, evidence references, tool requests, and accepted-result explanations. It is not a second independent simulation database.

Public evidence service:
- Retains the existing public-only scope.
- Supplies reviewed guidance and independently obtained official resource records, with source identifiers, dates, applicability, and freshness.
- Never accepts household profiles, room photos, contact lists, or private exercise histories into a shared public cache.

Build a provider-neutral AgentProvider interface with a Gemini implementation. Keep provider-specific request/response parsing and tool-continuation state inside it. Suggested roles:

1) PreparationPlanner: household-specific tasks and inventory interpretation.
2) ResourceStrategist: useful nearby search plans and supported resource explanations.
3) HomeObserver: visible concern proposals from home context and selected images.
4) RehearsalDirector: adaptive events, pacing, action interpretation, and consequence-based coaching.
5) PlanStressTester: executable counterexamples and dependency analysis.
6) AssessmentCouncil: bounded independent review passes and evidence adjudication.

These are role configurations and tool permissions within one service, not six permanent autonomous services. Reuse context/provenance helpers and combine compatible work in a call. Run the council for meaningful assessments and evaluation, not every tap.

The official SDK plus a small explicit orchestration loop is the default. Google's ADK is an option if its current TypeScript support measurably simplifies tool suspension, validation, and evaluation. Document the choice; do not adopt a framework just to label the app "multi-agent." [R1-R5]

5. PROVIDER CONFIGURATION, DATA HANDLING, AND OPERATIONAL LIMITS

Provider implementation:
- Read GOOGLE_AI_STUDIO_KEY from the selected runtime's secret mechanism and pass it explicitly to the SDK: env.GOOGLE_AI_STUDIO_KEY for a Cloudflare Worker binding, or process.env.GOOGLE_AI_STUDIO_KEY for Node. Do not copy it into client configuration or assume the SDK discovers this custom variable name.
- Verify the current model/API capabilities and installed SDK. Configure model IDs per role rather than scattering literals. Pin model, SDK, prompt, schema, content, and rubric versions in evaluation records.
- Current official documentation presents Interactions as the recommended API for new work; generateContent remains supported. Interactions stores by default. Use store:false for private requests and keep the required continuation content yourself; do not mix the two APIs' response formats. [R1]
- Preserve required tool-call IDs, signatures, and opaque protocol parts through stateless continuation using the official SDK's supported representation. Retain them only for the active bounded operation. Application code executes function calls. Validate values and semantics even when structured output passes its JSON Schema subset. [R2-R3]
- Start by evaluating a current economical Flash-class model for routine roles and a stronger configured model for difficult inspection/adjudication. Choose using actual fixture quality, latency, and cost.
- Do not require Live voice, Deep Research, browser automation, provider file-search storage, or an always-running agent for this feature set.

Data defaults and deployment fit:
- Use synthetic fixtures for developer testing until the intended private-data configuration is verified. Gemini's unpaid-service terms disallow submitting sensitive/personal information; paid-service handling differs, and provider abuse retention still exists. [R6]
- Google's current terms require developers to be 18+ and restrict API clients directed to, or likely accessed by, under-18s. The owner's age meets the developer minimum; it does not settle the family-app audience question. Record this release-fit issue without blocking synthetic implementation or claiming parental consent alone resolves it. [R6]
- Keep any alternate provider/Vertex deployment behind the adapter and evaluate its actual terms separately. Do not silently change providers or promise that an alternate product automatically resolves all restrictions.
- Keep the product within preparedness education and recorded care requirements; do not implement clinical advice or diagnose medical conditions. [R6, R14]
- Provide a concise native cloud opt-in that identifies the provider and information shared, with a separate understandable review for optional room-photo upload. Apple requires disclosure and permission for personal-data sharing with third-party AI. [R9]

Context minimization:
- Task planning normally needs anonymous member IDs and needs such as infant caregiving, pet care, mobility assistance, or a powered-device dependency, not names, phone numbers, or full medical notes.
- Spatial review needs the home graph and selected images, not the street address.
- Resource strategy normally needs preparation gaps, user travel constraints, and jurisdiction/category context, not the family's medical narrative.
- The exercise director needs relevant committed state and evidence, not the entire photo collection at every turn.
- Build schema-level minimizers and test forbidden fields, not just a prompt asking the model to ignore unnecessary data.
- Household snapshots remain sensitive even after names are removed.

Gateway requirements:
- Do not expose an unauthenticated paid-model proxy. Implement an authorization interface, short-lived scoped sessions, quotas, payload/image limits, and replay protection. Provide an App Attest-compatible native handshake contract and a real server validation path or a clearly identified integration dependency.
- Developer fixture credentials must be restricted to local/dev operation; production must fail closed if its authorization provider is not configured.
- Bind continuations to the authenticated installation/session, operation, context revision, permitted tool name, and pending tool-call ID. Enforce expiry and one-time or idempotent consumption. Reject unsolicited, cross-operation, or out-of-order results. Client responses cannot change role permissions, tool arguments, spend limits, or provider identity. Schema validity alone does not establish a client result's trustworthiness.
- Limit allowed roles, tools, models, and output sizes on the server. Never accept an arbitrary client system prompt or arbitrary tool/URL execution.
- Redact personal payloads from logs and error traces. Record versions, latency, token/tool counts, validation outcomes, and non-sensitive diagnostics.
- Give each operation a deadline, finite tool/call budget, one bounded repair opportunity, cancellation, and typed errors. Use a configurable small development spend cap; start with a synthetic smoke suite and report remaining evaluation work if the cap is reached.
- Prefer inline bounded image requests over persistent provider uploads. If uploads are necessary, implement explicit lifecycle/deletion and document actual retention.
- Treat website text, OCR, household notes, and model output as untrusted data. They cannot change role instructions, tool access, source allowlists, or system state.
- Avoid arbitrary URL fetches, SSRF, private-network access, prompt injection through retrieved documents, and cross-household caches.
- Do not request, display, analyze, or persist hidden chain-of-thought in application records. Preserve only provider-required continuation parts/signatures, unchanged, inside bounded transient operation state; delete them on completion or expiry. Durable records contain concise evidence-linked decisions, tool receipts, accepted commands, and committed events. store:false is an interaction-storage setting, not a guarantee of zero provider retention.

Keep the existing local intake, translations/fallbacks, deterministic checklist, saved plan, card, and authored exercises available without cloud access. A network error must not erase useful results.

6. SHARED CONTRACTS AND EVIDENCE MODEL

Define the minimal versioned contracts and fixtures needed for the first runnable slice, then expand them with each role. Reuse existing domain models instead of building a duplicate schema universe. Generate types where useful, but test real TypeScript/Swift round trips rather than assuming identical optional/null/enum behavior.

At minimum define:

- HouseholdContextSnapshot
- HomeSceneContext and RoomImageManifest
- EvidenceRecord and EvidenceReference
- AgentOperationRequest / AgentOperationResult
- ClientToolRequest / ClientToolResult
- ResourceSearchPlan and ResourceRecommendationProposal
- InventoryObservationProposal and ConfirmedInventoryItem
- PreparationTaskProposal
- HomeConcernProposal
- SimulationSessionState, UserActionIntent, DirectorProposal, and CommitReceipt
- StressTestFinding
- RubricDefinition, CriterionAssessment, CouncilReview, and PreparednessScorecard

Use stable IDs and include the relevant household/home/inventory revisions, session ID, monotonic event sequence, context digest, request/proposal ID, creation/expiry timestamps, and contract version. Reject stale responses rather than applying them to newer facts.

Evidence must distinguish:
- User-recorded or explicitly confirmed facts.
- Scanner measurements and unconfirmed scanner suggestions.
- Independently obtained official guidance/resource facts.
- Geographic provider results subject to their own use rules.
- Model observations/suggestions.
- Explicit hypothetical exercise assumptions.
- Engine-derived findings and real committed exercise outcomes.

Do not merge those into a single "AI confidence" field. Include source/evidence IDs, applicable jurisdiction, retrieval/publication date where available, confirmation state, and uncertainty. Model confidence is not verified truth.

A useful operation result is a discriminated union:
- completed: a validated proposal with evidence.
- needs_client_tools: bounded native/core tool calls and an expiring continuation token.
- needs_clarification: one targeted question whose answer changes the next action.
- unavailable/rejected: a typed reason and supported fallback.

The gateway should use opaque, expiring, revision-bound continuation state, preferably retained server-side only for the active operation. Do not expose raw provider history or hidden reasoning to app UI. Provide a local harness that drives the same protocol without an iPhone.

Only app/domain commit handlers write household facts, inventory, task completion, or simulation state. A user's confirmation can approve a batch of related observations in one concise review; do not require repetitive confirmations for the same fact.

7. PERSONALIZED PREPARATIONS AND SUPPLY INVENTORY

Implement a preparation pipeline that combines agent interpretation with source-backed actions and deterministic quantities.

Inputs:
- Confirmed household needs, dwelling and relevant hazards, assistance arrangements, actual supplies, essential dependencies, existing plan, and unresolved evidence.
- Optional cost, effort, transport, and storage constraints. Make these optional and easy to change.
- Existing approved action catalog and content source records, including sourced communication/meetup and home-escape preparations. [R12-R13]

Planner behavior:
- Identify which actions apply and why, adapt their wording, identify dependencies, choose a small useful slate, and ask only the highest-value missing question.
- Show three primary next actions by default, with a compact path to the rest. Do not replace a short list with dozens of generated tasks.
- Keep reviewed life-safety priority constraints. Let the agent meaningfully select and sequence within those constraints using household needs, prerequisites, cost, effort, and expected preparation benefit.
- Every task needs stable action/criterion and subject IDs, an applicability explanation, source/evidence references, completion predicates, the relevant editor/action, and links to inventory/resource/stress-test dependencies.
- Use subject-specific identity so two people needing different support are not collapsed into one task.
- Do not automatically complete a task because the model recommended something or the family succeeded in a simulation.
- Novel uncatalogued suggestions can remain optional reviewable ideas; they do not earn or remove score points until a reviewed criterion supports them.
- Display rough cost/effort bands as estimates when useful. Do not invent current prices or product availability.

Examples of meaningful personalization:
- Infant: caregiver/reunification arrangements and appropriate feeding, sanitation, and essential supplies based on recorded needs.
- Dog: food/water planning, carrier/leash, transport and destination compatibility.
- Powered medical equipment: documented approved backup arrangements, equipment-provider contact, allocation of available backup capacity, and an earlier preparation priority when a critical requirement is unresolved.
- Two independent adults: applicable household protections, water/food, communication, meetups, and relevant local hazards without irrelevant infant/pet/device tasks.
- A household without a car: reachable resources and assistance/transport plans that do not assume driving.
- A family with limited funds: feasible free or low-cost actions and supported community resources, without hiding genuine shortages.

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

Keep the existing Apple map. Save an address once; resolve geographic context locally where possible, select applicable source packs automatically, and let the user correct an ambiguous jurisdiction. County may remain source metadata or a fallback selector, not the organizing concept of the feature.

Separate three kinds of work.

A. Gemini plans the search around an actual need.
Produce a ResourceSearchPlan containing:
- Related task, household dependency, and hazard IDs.
- Resource category and preparation purpose.
- Mandatory capabilities, preferences, and unknowns that need verification.
- Travel mode/range and optional budget constraints.
- Alternative categories and bounded expansion/stop rules.
- Evidence needed before claiming the resource satisfies the need.

B. The native adapter finds and presents geographic candidates.
- Execute approved search categories through existing MapKit adapters with the saved home as origin.
- Keep geographic results and routes on the native side unless their specific permitted processing path has been established.
- Rank locally by the search plan's constraints and actual returned fields.
- Do not claim Gemini compared individual Apple listings it never received.
- Show the existing map with limited, useful markers and a compact resource overview: name, category, actual location, distance/travel estimate when available, why it matters, what remains unverified, and a direct task/plan action.
- Use "Open in Apple Maps" and ordinary user-initiated calling/navigation controls. Agents do not call locations, contact people, buy items, or begin navigation on their own.
- Give every client tool an explicit cloud-return policy. Geographic tools may rank/present locally without forwarding listings, coordinates, routes, photos, reviews, or derived descriptions. A completion acknowledgement does not authorize forwarding its payload through a generic tool-continuation loop. Use independent official evidence for cloud candidate comparisons and local match reasons for native candidates.

C. Gemini compares legitimate official evidence where available.
- Expose independently curated read-only tools such as find_official_resources(regionID, serviceType), read_resource_evidence(resourceID), and get_preparation_guidance(sourceIDs).
- Return structured evidence with exact source/field IDs, publisher, jurisdiction, timestamps, service facts, and uncertainty.
- Validate every claimed facility capability against those records.
- Join official records to map candidates only after establishing facility identity using stable identifiers where available, complete name/address, and appropriate location checks. A similar name or nearest result is insufficient. Keep ambiguous matches separate; never transfer activation, accessibility, or medical capabilities onto an unverified place match.
- Keep this source collection independent of Google grounding output. Use known official directories, feeds, and reviewed source packs with appropriate reuse rights.
- Preserve the seven Tarrant records and their review status until actually verified. Implement generic category search beyond that county and test an outside-region fallback. Do not imply nationwide official-shelter coverage from a handful of records.

Resource categories should include, when relevant:
- Grocery/food assistance and drinking-water preparation.
- Pharmacies and equipment suppliers for preparation and verified requirements.
- Hardware/general retailers for extinguishers, alarms, flashlights, and appropriate preparation supplies.
- Hospitals/emergency departments, with facility type confirmed where available.
- Police/fire stations and emergency-management offices, with their actual role explained.
- Officially identified warming/cooling centers, shelters, accessible destinations, and trusted meetups.
- Warm clothing/blankets and appropriate heating preparation. Firewood is relevant only when the family has confirmed suitable, properly installed heating equipment; avoid generic indoor-combustion recommendations. [R17]

Meaningful card examples:
- "This hardware-store candidate may help with your missing extinguisher task. Stock is unverified; check before going."
- "Your plan depends on an electrically powered well. This task is to store drinking water before an outage; a nearby grocery is a preparation option, not guaranteed water during the event."
- "This official location lists a warming service; current activation and transport access still need confirmation."

Do not infer that:
- A police/fire station accepts evacuees or functions as a public storm shelter.
- A school/church is an activated shelter.
- A store has stock or will operate during an outage.
- The nearest hospital is the appropriate destination for an individual medical emergency.
- A current driving route is safe during a future or active flood.

For flood planning, use supported official advisories/hazard evidence and clearly hypothetical road-closure tests. Ordinary map routing is not an evacuation clearance. For tornadoes, focus on advance shelter selection and a reachable appropriate location; do not suggest leaving home to drive to a generic distant shelter during a warning. Distinguish these hazards explicitly. [R15-R16]

Provider/data-rights decision:
- For this implementation, keep Google-grounded answers out of the permanent resource database and PDF pipeline. Search and Maps have different display, retention, and reuse terms; this design avoids making either grounded-answer product the source of durable household records. A later integration must implement its specific requirements. [R6-R7]
- Direct Google Places has separate setup and map-display policies. It is not automatically enabled by the Gemini key and is unnecessary for the existing Apple map. [R8]
- Apple also limits map-data reuse, storage, and display. Keep a provenance-aware native adapter and distinguish user/official plan facts from provider map content. Verify intended snapshot/export handling without undoing the existing native renderer. [R10]
- An optional attributed Google discovery answer can be investigated later if it adds value and meets its requirements; it is not required for this goal's primary resource workflow.

After cloud opt-in, refresh strategy only when its relevant normalized inputs change: preparation gap/category, transport or budget constraint, jurisdiction, or an explicit strategy dependency. Unrelated medical notes, contacts, or photos must not trigger another resource call. Native searches have a separate geographic fingerprint. Debounce edits, deduplicate equivalent requests, cancel stale work, bound expansion, and retain useful results during refresh. Revoking cloud opt-in stops new jobs and cancels active work where possible; native search and saved plans remain usable.

9. HOME CONTEXT, OPTIONAL IMAGES, AND REVIEWABLE CONCERNS

Define HomeSceneContext so the agent can reason about the actual home instead of interpreting an unlabeled screenshot alone.

Include:
- Schema/home revision, units, coordinate conventions, per-floor origins/transforms and elevations.
- Stable floor, room, wall, opening, door/window, connector, obstacle, and relevant object IDs.
- Room polygons, adjacency, opening dimensions and operability where recorded, stairs/ramps, exterior access and grade, and known accessible routes.
- Verification status and provenance for every safety-relevant attribute.
- Confirmed room uses, shelter/exit/meetup candidates, storage/equipment locations, and anonymous assistance needs.
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

Generate reviewable in-app findings, not autonomous emergency alerts or unsolicited push notifications. Keep capture/manual input alternatives equally useful.

10. GENUINELY ADAPTIVE REHEARSAL

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

A DirectorProposal needs session/proposal/request IDs, base revision and event sequence, home/household revisions, context digest, permitted commands, next boundary, purpose, evidence/assumption references, and presentation intent.

Expose a small, composable action language:
- External conditions: power loss/restoration, water-service advisory, communications loss, unavailable destination, modeled road closure.
- Spatial incidents: startIncident(roomID, hazardType, reviewedProfileID), advance permitted hazard stage, affected portal/room relationships calculated by the core.
- User actions: moveTo(destinationID), take/transfer supplies, assign a helper, allocate a power source, contact a simulated contact, close an operable door, choose a plan alternative.
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
- On timeout/provider failure, retain the same session, resource balances, pending event queue, and history. A local fallback director supplies validated next commands for that state, or the app pauses. Never restart an authored scenario, replay default choices, reset supplies, or reapply incidents for fallback. Test switching from Gemini to local continuation and back without lost/duplicated effects.
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
- Unsafe choices get no credit for the affected competency. Feedback never retroactively changes the original answer.
- Collect comparable evidence from an optional short "Practice check" within the existing Rehearse flow using approved equivalent variants. Guided/adaptive training still provides feedback and insights but arbitrary scenario difficulty cannot directly determine the score.
- Use the latest eligible practice assessment, not a best-attempt maximum or drill count. Support learning and later retesting with an equivalent variant. Persist attempt identity, variant, and pre-feedback answers; interruptions resume that attempt. Restarting cannot erase errors or silently reroll a variant. A newer incomplete attempt is provisional, retaining observed results and unknown remaining competencies. Show an older completed result as history, not the current score while suppressing newer contrary evidence.
- VoiceOver, translation, alternative input, and additional reading time are accessibility support, not coaching. Provide an equivalent text/manual option with the same grading anchors.
- Do not score reaction speed, expensive equipment, photo quality, LiDAR ownership, physical ability, animation completion, or the number of rehearsals.
- Until variant comparability is evaluated, mark practice results provisional and avoid invented difficulty multipliers.

Overall proposed score:
Base = 0.90 * C + 0.10 * P
Overall = min(Base, applicableCriticalGapCap)

C is the uncapped preparation subscore. For each of four practice competencies: independently correct = 1, explicitly anchored partial = 0.5, incorrect/unsafe = 0; unassessed earns 0 while retaining unknown status. P = 100 * sum(competency credits) / 4. Unassessed competencies remain in the denominator. Use the lowest triggered critical cap, or 100 if none applies. Apply it after combining C and P; round only the displayed result.

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
Then the three most useful improvements and a short "How this is calculated" view. Missing backup documentation alone must not be reclassified as confirmed absence.

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
- Same committed log gives identical state/route hashes offline.
- Duplicate/stale/out-of-order proposals and failed atomic persistence cannot double-consume resources or corrupt the session.
- Conservation, simultaneous power allocation, access constraints, unit conversion, depletion boundaries, and temperature assumptions.
- Current example floor plan plus varied houses: studio/apartment, one floor, multiple floors, split levels, disconnected/missing connector, inaccessible stairs, narrow/blocked portal, ambiguous exterior windows, and a home without an appropriate confirmed shelter.
- Vary fire starting rooms/portals, flooded low areas, tornado assumptions, occupants/helpers, and supplies. Include a person starting in an affected room and no supported route.
- Unsupported geometry and photo observations cannot manufacture routes or confirmed safety.
- External incident schedules stay controlled in before/after intervention tests.
- Test past-time incidents, scheduling-budget exhaustion, fallback/resume, interior routing, and source household/home edits during a session. Source edits invalidate pending proposals and require a supported snapshot refresh/fork or continuation against the identified original snapshot; never mix old geometry with new facts.
- Demonstrate that distinct household actions yield materially different valid continuations and that the director creates sequences beyond the old fixed choice IDs.

C. Inventory, tasks, resources:
- Two adults versus infant + dog + powered-device household.
- Duplicate images/items, unreadable labels, unknown quantities, expiry, inaccessible supplies, shared battery capacity, missing device specifications.
- Priority constraints, subject-specific tasks, no duplicate shopping, and limited actionable recommendations.
- Ambiguous addresses, no results, rural distances, no-car travel, outside-source-pack regions, closed/unknown services, stale official records, and prompt injection in resource text.
- No invented inventory, shelter activation, hospital capability, retailer stock, or route safety.
- Verify that actual supported facts drive the resource explanation and checklist link.

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

Produce an evaluation report with clear "passed on Linux," "live model tested," "synthetic only," "native pending," and "human review pending" categories. Never report an unrun test as passed.

14. IMPLEMENTATION SEQUENCE AND DELIVERABLES

Work in vertical slices and keep them runnable.

Milestone 1: Verify the repository baseline and state owners. Implement the minimum private gateway, Gemini adapter, authorization seam, context/contracts, and incremental host seam needed for one runnable director/tool/commit loop. Deliver a synthetic smoke runner that exercises actual portable state before expanding role scaffolding.

Milestone 2: Implement inventory interpretation and deterministic gaps, personalized top actions, resource search strategy, official evidence tools, and native MapKit adapter protocol. Demonstrate a household change producing different task/resource plans.

Milestone 3: Implement the incremental simulation host, validated director loop, client-tool continuation, resource ledger, replay, and local fallback. Demonstrate a live or recorded Gemini session whose next events depend on committed user actions.

Milestone 4: Implement home scene/image schemas, observation proposals, confirmation lifecycle, and scenario links. Demonstrate supported concern -> review -> task/scenario linkage with honestly labeled fixtures.

Milestone 5: Implement dependency stress tests, executable findings, fixed scoring rubric, practice evidence, council, and repeatable evaluation. Compare a real intervention under the same recorded incident schedule.

Milestone 6: Complete native integration contracts, synthetic demo package, documentation, and status report for Claude/Mac. Resolve portable failures before declaring handoff ready.

Suggested repository deliverables, adapted to actual conventions:
- Private AI service with role prompts, SDK adapter, tools, schemas, validation, configuration, and README.
- Shared contract fixtures/schema definitions.
- Portable domain changes for session state/reducer, inventory/evidence, stress-test outputs, and scoring.
- Versioned guidance/action/rubric content and source registry.
- Headless exercise and agent-evaluation runner.
- Development/holdout fixtures and adversarial/mutation tests.
- docs/ai/architecture.md, data-flow.md, rubric.md, evaluation-report.md, and mac-integration-handoff.md.
- Non-secret configuration example and exact setup/test commands.
- Synthetic demonstration households and recorded replay logs, visibly labeled as fixtures.

The Mac handoff must identify:
- Current branch/commit and shared-file changes.
- Native protocols and DTOs with exact call/response examples.
- App context building and proposal acceptance points.
- Incremental engine and native scene synchronization.
- MapKit search/result presentation and attribution responsibilities.
- RoomPlan/AR image selection, calibration, redaction, deletion, and fallback capture.
- Consent, Keychain/authorization handshake, background/resume/cancellation handling.
- Existing-screen placement for task suggestions, supplies, concern review, stress findings, practice check, and scorecard.
- Locale/VoiceOver/Dynamic Type behavior and human-reviewed critical language.
- Existing PDF/card integration: only accepted plan content, intentional privacy selection, and permitted map content, never raw council deliberations.
- Exact Xcode/iPhone tests still needed and expected observable results.

Definition of done on Linux:
- Real provider adapter and bounded role workflows exist, not only mocked strings.
- A complete synthetic household can pass through personalization, resource strategy, inventory, stress test, adaptive session, and score compilation using the documented host protocol.
- At least one accepted adaptive trace demonstrates substantive tool use and a continuation changed by the family's action.
- Failures preserve valid local state and provide useful fallback.
- Score/rubric behavior is reproducible and its limitations are documented.
- Contracts and runnable fixtures make the remaining native work specific.
- If credentials/provider access/budget/toolchain block part of verification, complete all unaffected work, report the exact blocked tests, and do not fabricate success.

15. IMPACT AND DEMONSTRATION

Prioritize one compelling, honest community story over feature count:

A family with an infant, a dog, and a powered-device dependency imports its actual needs, confirms existing supplies, sees three relevant actions, identifies suitable preparation resources, and practices a home-specific outage/storm scenario. The exercise reveals a shared battery, inaccessible supplies, or a brittle contact/route. A confirmed improvement changes the plan, the controlled retest, and the explained score.

Pair it with a two-adult/no-special-dependency household to demonstrate real personalization. Show manual home input and offline fallback so the benefit is not limited to people with a LiDAR iPhone.

The strongest evidence of impact is an understandable chain:
observed/recorded need -> useful recommendation -> completed preparation -> fewer supported plan failures.

Use the existing shareable plan/card to extend household benefit without requiring every family member to use cloud AI. Do not add a social network, leaderboard, or public upload of private home plans.

Prepare a short demo script and measurable usability/quality results from actual tests. Clearly label synthetic fixtures and recorded replays. Do not invent user adoption, safety outcomes, expert endorsement, or competition results.

16. RESEARCH REFERENCES AND HOW TO USE THEM

Research checked 2026-10-19. Recheck provider APIs/models/terms at implementation time. The architecture choices and numeric rubric above are proposals; official sources do not validate DryRun as a safety system. Keep app guidance short, accurately sourced, versioned, and appropriate to its jurisdiction. Do not indiscriminately copy source pages into prompts or ship a legal essay in the user flow.

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
