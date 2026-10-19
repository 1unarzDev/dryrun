# Concentrated-flow audit, 2026-10-19

This audit continues all seven outcomes in `DryRun_AI_Implementation_Reference.md`, especially §§7–10 and 13, plus the owner's housing, location, window, marker and apartment-fire requirements. Independent ideator and critic passes inspected the actual checkout. Linux cannot establish clean on-device layout or functional Gemini integration by reading SwiftUI.

## What the app currently does

The app retains three destinations: Prepare, Rehearse and Plan. Home is reached from the existing flows. `AppModel.updateHousehold` stages edits through cleanup and an atomic private snapshot save before publishing/invalidation. Rehearse still starts `RehearsalEngine.run` and presents the existing `RehearsalCursor`; choosing an option reruns that authored schedule. The new portable `SimulationSession`/gateway loop is runnable in the headless harness, but has NOT replaced that native cursor. Prepare's optional briefing remains the existing on-device `FamilyBriefingService`, not Gemini. Native inventory review, image review, resource strategy, scorecard and executable stress adapters/UI remain to integrate. Do not label all seven app features delivered.

## Decisions implemented in this slice

| Surface | Problem found | Change | Evidence and limit |
|---|---|---|---|
| Prepare | Supporting setup and generated prose precede useful actions | Put the short action list first; keep family/home/card entry points nearby; collapse optional briefing and generate on expansion | Native source syntax parsed; small-phone order still needs device review |
| Prepare | Prose could outlive its source | Bind accepted briefing to full revision key, exact localized steps and locale; reject cancellation/staleness; authored fallback stays available | Existing on-device service retained; not cloud-integration evidence |
| Prepare/debrief | Inconsistent icons and stale/unrelated task navigation | Shared action symbols; canonical aliases and exact subjects across todo/completed/recorded; changed-task message returns explicitly to current Prepare root | Six new portable concentrated-flow cases cover routing/labels/geometry/safety |
| Rehearse | Assumptions/history displace the current decision; every answer gets green success | Scene/current decision first, assumptions after, collapsed history; neutral acknowledgment; Reduce Motion honored | Actual unsafe consequences remain host/authored feedback, never icon-based certification |
| Rehearse | A second path looks independent even if both use one stair | Display host independent/shared/none status and forward shared chokepoints and alternative connectors to Gemini | Home-context schema additive, historical absent status remains unknown |
| Home | Similar room names on different floors | Floor-qualified room labels in assignments, choices, affected/exposed rooms, routes and editor | Same canonical HomeModel powers both renderers; native rendering pending |
| Home | Markers were hidden, auto-confirmed, poorly placed or impossible to relocate | Collapsed per-floor icon list with direct editing; bounded concave-room anchor; new location proposed; room/local-metre relocation; location-only confirmation | Saved place ID/notes preserved. Save/All items apply visible edits and keep invalid edits open; functional readiness never credited |
| 2D/3D | 2D legend overstated exits; all 3D connectors looked like stairs | Selected-floor opening/hazard/marker legends in 2D/3D; distinct stairs/ramp/elevator shapes/icons; excluded connector X/color in both views | 3D rendering only syntax parsed; check actual geometry/orientation/contrast on iPhone |
| Apartment fire | Elevator shortcuts must never appear | Existing host excludes every elevator; explicit native fire warning; 2D/3D excluded cues; two executable synthetic fire cases | With stairs: supported route uses stairs only. Elevator-only: no supported route, exact replay, unchanged real source |

No new primary tab, AI dashboard or transcript was added. New translations in EN/ES/VI are drafts awaiting human review. The floor-plan editor keeps breaker/electrical panel, extinguisher, supply/emergency storage, alarms, shutoffs, shelter candidate and meeting markers. A tornado closet is only a reviewable candidate; a manufactured home never earns interior tornado-shelter credit. Recorded floor elevation is not geographical flood elevation. Site provenance, datum, source age and official route activation remain explicit unknowns when missing.

## Model output inspection

Actual retained text, not schema success alone, drove corrections. `housing-features-live-v7.json` overstated two primary exits when paths shared one stair. Current contexts now include alternativeStatus, alternativeConnectorIDs and sharedChokepointIDs. Preparation/8 compiles the drill explanation from those host results; fresh v8 preserved the shared-stair warning. Its smoke-alarm rationale nevertheless said a test ensures operation during a fire. Preparation/9 compiles that explanation as present functional evidence without guaranteeing future performance. Resource prompt remains /5. Fresh preparation/9 v9 passed six real calls across these three synthetic layouts, with final compiled text inspected. Director/7 adds explicit fire escape/assistance constraints after director/6 v3 suggested suppression; fresh v4 completed the real host-preview/validated-commit loop without that suggestion. Both raw traces remain retained, and narration is still unverified. The audit reports word bands as review flags, never truncates safety information and never counts schema acceptance as semantic correctness.

`elevator-fire-live-v2.json` used two actual Gemini calls. Both acknowledged elevator exclusion and matched host supported/no-route booleans. Raw prose still speculated about a bedroom window and claimed the kitchen blocked the primary path without a host before/after proof. Those are retained QUALITY DEFECTS; they must not be displayed as validated facts. No-route UI should use the host result and building-specific posted procedures/assistance review, never an invented window descent or carry technique. Fresh `housing-director-elevator-live-v2.json` then tests the actual director/7 gateway/host loop with elevator-only geometry, asserts no primary route after the fire commit, preserves exact replay and rejects a duplicate. Its actual purpose requests building procedures and assistance review without inventing an exit (2 calls, USD0.00487950). These finite synthetic tests do not establish real apartment-fire safety.

## Concentration plan for the Mac owner

| Original outcome | Existing place to integrate | Primary view | Secondary detail |
|---|---|---|---|
| Personalized preparations | Prepare | At most three next actions with task-specific icons and one concrete reason | Evidence, uncertainty and provenance disclosure |
| Nearby resource strategy | Existing Plan map + linked preparation | Why this result addresses this gap; known service and missing verification | Source freshness/capabilities; no generic list of pins |
| Supply intake | Existing supply editor opened from a preparation | Review inferred item/quantity once; deterministic remaining gap | Evidence/photo, expiry/access/units |
| Home/image inspection | Existing Home scene and marker/room list | Inline possible-concern review, image evidence, one confirmation | Source image and unknowns; no extra dashboard |
| Adaptive rehearsal | Existing scene/decision view | Committed consequences and one meaningful decision | Optional assumptions/history; receipt-based routes/resources |
| Executable stress | Plan/debrief linked to the same preparation | One dependency and concrete before/after consequence | Controlled schedule, scope and retest evidence |
| Numerical scorecard | Prepare/Plan summary | Score, coverage, critical cap and next useful action | Versioned rubric/predicates and eligible first practice |

One accepted confirmation should refresh the linked inventory/preparation/resource strategy/score through existing state owners. Do not maintain independent AI truth or add completion toggles to hide missing predicates. Manufactured-home external-shelter planning still lacks a reviewed evidence path that can close its task: current transport destinations do not establish tornado protection. Implement a source-backed confirmation path or keep it honestly unresolved.

## Required native audit

Use isolated fictional demos with `-demoHousehold hh-oak -demoHome apartment-complex|manufactured|twostory`; custom home demos clear fictional site/location evidence and do not touch the real vault. `HousingDemoTests`, the new `DemoJourneyUITests` and expanded `ScreenshotTourUITests` are AUTHORED, NOT EXECUTED. Screenshot checks demonstrate neither rendering correctness nor elevator routing by themselves. Exercise mode selection AND every floor, then compare room/window/marker/connector positions against the canonical JSON and host route.

Build/typecheck with Xcode, install over the cable, inspect actual screenshots in EN/ES/VI, smallest supported phone, large accessibility text, VoiceOver, Reduce Motion and contrast without relying on color. Check keyboard/toolbar reachability and floating-tab overlap. Test marker edits with Save without Apply, invalid coordinates, unchanged verification, relocation, undo, failed save and restart. Test an actual elevator-containing synthetic graph, blocked sole stairs, step-free/assistance need and honest no-route state. Never invent elevator exceptions, an upstairs walking exit or a manufactured-home tornado closet.

Wire the full committed user-action → Swift host → Gemini/tool continuation → preview/validated commit → next-turn loop in the existing Rehearse surface, render receipts and test stale/duplicate/cancel/background/offline/resume. Inspect every actual Gemini explanation on screen for evidence, appropriate length/depth and useful next action. Report unresolved production auth, external data/terms, human safety/rubric/language review and real RoomPlan/camera validation separately. Preserve PDFs, navigation, RoomPlan and on-device AI improvements.
