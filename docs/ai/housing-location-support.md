# Housing, safety markers and site evidence

This extends the original seven-outcome goal and root `DryRun_AI_Implementation_Reference.md` §§7–13. The `.txt` is absent. Existing native models/renderers were inspected before design; the October 19 baseline passed 14 spatial/shelter/context tests. Native PDF/navigation/RoomPlan work was preserved. Native changes here are limited to the existing dollhouse using the shared 3D transform and clearing site evidence on moving; neither change was Xcode-tested on Linux.

## Existing support and repaired gaps

The checkout already supported HomeType apartment/manufacturedHome/townhouse/duplex/other, manual floors, transformed multi-floor geometry, stairs/ramps, step-free exclusions, person-specific window escape evidence, RoomPlan window proposals, safety markers and a unit-only third-floor apartment. Reuse those interfaces. Common areas remain nonedges unless represented as actual spaces with confirmed portals/connectors.

The cloud household snapshot previously omitted dwelling type and utility dependencies. Current `HouseholdContextSnapshot(household, at:)` includes `AnonymousHousing` plus minimized `SiteHazardContext`; historical optional fields decode without fabricated facts. It contains no names, address, coordinates or exact elevation. `HomeSceneContext(home, household:)` is the current producer: it binds dwelling constraints, adds host baseline `planningRoutes` and `planningNeeds`, and sends safety-marker floor/position/kind/room/status. Private labels, finding instructions, scan IDs and native map payloads stay local. Use this initializer in both initial requests and inspectScene; the home-only initializer lacks household-specific baseline routes.

The original `dryrun.home-scene/2` safety fields remain strict. Added dwelling/marker/baseline-planning fields are optional additive fields; historical /1 and /2 shapes remain accepted. `planningRoutes` has explicit baseline-only scope. Current hazards, actual occupant positions, blocked routes and helper reach MUST come from committed receipts and host tools. A successful baseline route is not real-world safety clearance.

A window excludes a room from the simple windowless tornado rule even if proposed/inoperable/rejected as an escape option. Imported window proposals remain unverified and cannot manufacture exit operability. Manufactured-home shelter rejection is enforced in `ShelterSuitability`, the household-bound scene and **household-assessment/6**, including a household paired with a legacy untyped ranch. /5 could award that legacy model's shelter suitability despite manufactured housing; /6 deliberately records unsuitable interior shelter and does not invent an external route. Frozen old assessments remain replayable. The numerical rubric/weights are unchanged. An advance external arrangement is planning work, not assessed structural performance or live evacuation clearance.

`prep.shelterPlan` reuses the existing Home/transport edit targets. It stays visible for a manufactured home while an appropriate advance arrangement needs review; a generic destination or shopping completion cannot establish tornado suitability. Missing ordinary shelter candidates route back to existing home review. The bounded task selector preserves manufactured-home advance planning alongside essential medical backup before generic shopping. New English content and Spanish/Vietnamese drafts are versioned in content 2026.10.5; language/safety review remains pending.

## Runnable models and representations

| Canonical source | Meaningful tested behavior |
| --- | --- |
| `SampleHomes.apartment` | Preserved third-floor unit only: unmodeled common corridor and balcony do not establish ground egress. |
| `SampleHomes.apartmentComplex` | Same unit plus actual third/second/ground shared corridors, two stair connectors and final exterior door. Walking route exists; the shared entry/stairs are dependencies. Missing/blocked stairs, elevator replacement and wheelchair needs prevent supported egress. |
| `SampleHomes.manufactured` | Narrow original model with stepped exterior doors, proposed bedroom window, supplies, breaker and extinguisher. Walking egress exists; a step-free route is not established. A deliberately marked windowless closet never becomes tornado shelter. |
| `SampleHomes.twoStory` | Existing bedrooms upstairs, 2.8 m relative floor elevation, reviewed stair geometry and operable upstairs windows. Removing/blocking the stair prevents a supported upper-floor walking exit; windows do not create one. |
| `SampleHomes.ranch` | Existing one-floor/marker/window/shelter regression case. |

Original fictional geometry is bundled under fixtures/homes. Shared IDs/coordinates produce per-floor annotated SVG and OBJ under fixtures/homes/representations; comparison SVG/PNG files were generated and visually inspected on Linux. They are portable representations, NOT RealityKit/RoomPlan/phone evidence. `HomeModelExport.point3D` applies the recorded floor transform and maps `(x,y)` to `(common.x, elevation, -common.y)`; the native dollhouse now calls that same helper before centering. Analytical rotated/translated-floor tests check the mapping. OBJ floor faces, wall/opening lines, connector lines and marker points are inspection assets, not a structural mesh or imported USDZ.

```sh
DRYRUN_WRITE_FIXTURES=1 scripts/swift.sh packages/DryRunCore test --filter 'HousingSupportTests|SpatialFixtureTests'
python3 scripts/render-housing-fixtures.py # requires cairosvg
pnpm --dir services/ai-orchestrator exec tsx scripts/housing-layout-eval.ts # actual host, zero model calls
```

The buildingSMART sources and licenses in [housing-location-research.md](housing-location-research.md) are candidates for future native import comparison. They have not been imported or validated, and no licensed manufactured-home external model was established. The shipped original fixtures do not require an IFC importer and exercise the same domain and rendering inputs as the app.

## Safety markers

`AnnotationKind` already includes electrical breaker/shutoff, gas/water shutoffs, fire extinguisher, smoke/CO alarms, supplies, medical equipment, tornado shelter candidate and outside meeting point. Existing ManualHomeEditorView adds markers, labels and finding instructions; HomeRoomListView, FloorPlanView and DollhouseView present them. `HomeSafetyMarkers.place` adds/relocates a marker only to a finite point inside its recorded reviewed room, preserves floor/room association, bumps revision and returns a candidate for atomic native save. It throws without mutating the original. Marker verification describes location confirmation, not extinguisher function, alarm readiness or structural protection. Separate readiness records, shelter evidence/grade and current route rules still apply.

Mac must test precise placement, editing/undo/delete, fallback room lists, 2D/3D alignment, failed save/relaunch and PDF privacy; do not infer these passes from Linux Codable tests. Native marker placement currently starts at the room centroid; wire the shared placement helper where the existing editor needs more precise controls without adding a new navigation surface.

## Private site-hazard contract

`HouseholdProfile.siteHazards` is additive optional encrypted data. `SiteHazardEditing.replace` is an explicit local household edit and bumps revision. Inside an existing revision-owning transaction use `SiteHazardEditing.stage` instead; `AppModel.updateSiteHazards` follows that save-first path. Explicit household dwelling-type changes update the associated home context atomically, and Home saves preserve the household type; Gemini and simulation tools have no mutation path. `SiteHazardBinding` is a local-only home/location fingerprint. A changed address/home ID, mismatched jurisdiction, expired/future/unreviewed/nonofficial evidence or duplicate source identity prevents cloud credit. Moving also clears the native profile. Editing location without moving must refresh/review evidence rather than reuse it merely because the county is unchanged.

Local `SiteHazardProfile` stores:

- Source ID, authority, publisher, HTTPS source reference, jurisdiction, retrieval/expiry, review status, optional publication date/dataset version.
- Elevation in metres, terrain vs finished-floor surface, vertical datum, explicit uncertainty and optional horizontal reference/resolution.
- Independently sourced design flood level with datum and uncertainty.
- Wildfire rating plus community/parcel scale and source.
- Hurricane official planning zone, route IDs, source, private directions and optional saved-destination reference.

`SiteHazardContext` exports only evidence availability, conservative comparison class, wildfire rating/scale, hurricane planning-record status, source IDs/publisher/jurisdiction/timestamps/vintage and explicit scope limits. It never sends exact elevation, coordinates, zone/route IDs, instructions, source URL or the location-binding digest. The local full source remains necessary for native review. The contract rejects extra geographic fields.

A finished-floor/design-level comparison requires reviewed current official sources, compatible known datums and explicit nonnegative uncertainties. Terrain does not substitute for floor height. The two uncertainty bounds must separate before reporting above/below design level; overlap stays explicit. None of these classes means safe. USGS EPQS terrain, if used natively, cannot invent missing datum/accuracy. USFS community risk is not an individual-home or active-fire determination. Static official hurricane references are not current orders, activated contraflow or safe routes. See the primary-source research for actual service limits and the unsuccessful FEMA-page access.

`HousingPlanning.strategyDependencies` provides bounded normalized housing/egress/site classes for resource refresh. The headless `resourceKey` uses these by default; native should pass them deliberately into `ResourceStrategyKey.normalized`. No image, private note or exact geographic payload belongs in that key. Native official ingestion/manual-review UI and refresh scheduling remain Mac integration work. No real-location hazard lookup or nationwide evacuation dataset coverage is claimed. Current wildfire/hurricane physical simulation and scoring are outside the reviewed six-hazard packs/rubric.

## Actual model evaluation and response presentation

`housing-layout-eval.ts` submits synthetic real host contexts and computed route outcomes to Gemini for six differing courses, then runs actual preparation/resource roles for three dwelling types. It validates exact IDs and feasible-under-recorded-assumptions vs not-established status. This tests interpretation of host results, not independent safety expertise. Bounded one-repair history is retained. Original failed attempts (invalid evidence ID, oversized evidence list) remain recorded; the early harness did not retain the offending raw text, a diagnostic limitation corrected for subsequent attempts.

The first passing live outputs still had semantic problems: inappropriate electric-equipment CO causation, an omitted manufactured-home advance shelter task, and overly absolute no-exit wording. Current preparation/7 and resources/5 preserve a mandatory advance-plan task, compile grounded CO task/search explanations and reject unsupported hazard IDs. Electric heaters/well pumps do not produce CO; an alarm review still matters because other combustion sources may be unassessed. `output-quality/1` adds role-specific action/reason/unknown guidance and discourages unnecessary permission questions. No one-size truncation, padded minimum or word-count safety pass is applied.

`output-quality-eval.ts` audits actual retained text by field. Short council explanations and long director purposes are review flags; raw council opinions are not user-visible accepted facts. Native must check each real phone surface with progressive disclosure and the committed host receipt. Claim cues need evidence review even when their word count is ideal.

```sh
# Synthetic live tests, sequentially; server environment key only. Output paths must be new.
DRYRUN_LIVE_HOUSING=1 DRYRUN_HOUSING_OUTPUT=../../fixtures/ai/new-housing-live.json pnpm --dir services/ai-orchestrator exec tsx scripts/housing-layout-eval.ts
DRYRUN_HOUSING_DIRECTOR_OUTPUT=../../fixtures/ai/new-housing-director.json pnpm --dir services/ai-orchestrator exec tsx scripts/housing-director-eval.ts
pnpm --dir services/ai-orchestrator exec tsx scripts/output-quality-eval.ts
scripts/verify-ai-portable.sh
```

The complete fresh integrated pipeline and its exact frozen-score/receipt replay are separately retained in integrated-pipeline-current.json and pipeline-current-assessment-replay.json. They precede the housing/assessment-6 changes; do not relabel them as current-contract housing evidence. Future pipeline runs preserve unique output paths/source hashes and refuse overwrite before spending.

Native/wired-device integration, actual scans and site adapters, useful small-screen length/depth, broader model generalization and qualified safety/rubric/language review remain pending. See the updated [Claude wired-phone prompt](CLAUDE_WIRED_IPHONE_HANDOFF_PROMPT.txt) and [Codex prompt](CODEX_WIRED_IPHONE_HANDOFF_PROMPT.txt); both explicitly retain all seven original outcomes and the new objectives.

The latest v5 live feature-only run (three households, six calls) predates final preparation/7 and exposed a bathroom-lock question plus overly absolute upstairs-window wording. Those exact replies now drive regression checks for host-compiled review wording. No subsequent preparation/7 live run is claimed. Read evaluation-report.md for all retained successes/failures, actual accounting and output-quality flags.
