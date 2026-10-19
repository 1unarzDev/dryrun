# Dry Run — MapKit integration and complete home-scanning handoff

## Assignment

You are a new Codex engineering agent entering an existing repository with no prior conversation context. Read this document completely, inspect the actual checkout, and implement the work. Do not stop at a proposal, a new map component, or a screen backed only by mock data.

**Primary objective:** turn the existing rudimentary MapKit directory into a useful native Apple Maps preparedness experience: regional resources, clear place details, optional device location, search, ordinary travel previews, and privately saved planning places.

**Secondary objective:** complete the existing RoomPlan-to-home workflow so a supported iPhone can capture a home, let the household review and correct it, assign residents to rooms, save it reliably, reopen it, and use that same geometry in rehearsals. Connect an outside meeting place to the map without confusing geographic coordinates with indoor floor-plan coordinates.

Finish the primary map journey before expanding into optional geographic overlays, visual embellishments, or advanced scan features. Preserve the current visual language and app architecture. Use reasonable defaults, resolve routine choices autonomously, and make working, reviewable changes. Do not ask the user to repeat the product brief. Do not deploy services, publish the app, upload household data, overwrite uncommitted work, or make irreversible external changes without authorization.

There is no new hard three-hour deadline in this assignment. The original project had an initial prototype sprint; this task is an integration pass on its resulting code. Use the milestones below, keep a short progress log, and prefer completed vertical features over broad unfinished scaffolding.

## 1. Product context and non-negotiable boundaries

Dry Run is an iPhone-only family disaster-rehearsal app. It models household capabilities, home layout, and dependencies such as electricity -> heating, water pumping, charging, and powered equipment. Six scenarios are implemented: freeze with power loss, heat/grid strain, tornado, flash flood, house fire, and water outage. Families explore accelerated rehearsals, inspect consequences, get ranked preparation actions, and keep offline plans in English, Spanish, and Vietnamese. It is an educational preparedness product for a student Congressional App Challenge project, not emergency dispatch or certified life-safety engineering.

The existing navigation has **five tabs: Next steps, Rehearse, Home, Plan, Help**. Preserve them. Integrate the main map under Help and a meeting-place picker under Home/Plan. Do not introduce a sixth tab or redesign the entire frontend.

Keep these architectural boundaries:

- Household information, home geometry, saved private places, and private plans stay in the existing encrypted local vault. No account or household backend is needed.
- The deterministic rehearsal engine remains independent of Apple frameworks and network availability. Map searches and directions must not become hidden inputs that change replayed simulation results.
- The public backend receives only its allowlisted public identifiers. Do not send exact coordinates, addresses, search terms, home models, people, medical information, or contacts to that backend.
- Apple Maps services are a separate network boundary. Explain that search and travel previews use Apple services and may send relevant queries/endpoints to Apple. Do not claim that nothing leaves the device merely because Dry Run's own server receives no private information.
- A geographic point is not proof that a shelter is activated, accessible, accepts pets, has capacity, or can be reached safely. Preserve unknowns and source timestamps.
- An Apple Maps street route is an ordinary planning preview, not a verified evacuation route, flood-avoidance route, or wheelchair-accessibility certification. Indoor practice paths stay in the existing local egress planner.
- A scan is proposed geometry, not proof that an exit works. Do not simulate smoke physics, survivability, structural integrity, or fire progression from RoomPlan.
- The app must remain useful on non-LiDAR devices and without location permission, Apple Intelligence, a configured backend, or an internet connection. Network-dependent features must show honest limitations.

## 2. Audited starting point — verify against your checkout

The supplied archive was inspected at commit:

`163de3212cd06178d8bf26ad7d9f8c0661568449` — `Merge pull request #3 from 1unarzDev/ui/app-challenge`.

Independent review reran `swift test --package-path packages/DryRunCore` using Swift 6.2.1 on Linux: **143 tests in 22 suites passed**. This review did not run an iOS build, simulator, physical RoomPlan capture, the vault tests, or the backend tests. `docs/VERIFICATION.md` contains earlier project-reported Mac/simulator results; distinguish those from tests you actually execute. Some source comments saying “not compiled” predate the later verification record. Neither those comments nor the simulator record establishes physical scan correctness.

The XcodeGen spec targets **iOS 18.0, Swift 6, complete strict concurrency**. Keep that baseline unless an unavoidable, documented requirement justifies a change. Newer conveniences must have appropriate availability guards and complete fallbacks. Inspect the installed SDK rather than copying signatures from memory.

### What already exists and what is missing

| Area | Current implementation | Integration consequence |
|---|---|---|
| Map | `HelpViews.swift` imports MapKit and embeds `DirectoryMapView` in a 300-point area below the directory. It creates markers only for resources with both coordinates. | Extend and replace this limited experience; do not start a separate app. |
| Mappable resource data | The two bundled regional JSON files contain 13 unique resources: five statewide contacts/services and eight county records. **None has latitude/longitude.** | In the bundled build the map has no resource markers. Data quality is a release blocker, not just UI polish. |
| Geographic framing | `RegionInfo` has county metadata and NWS IDs but no map bounds/center. | Provide deliberate county/region camera framing even when a county has no physical resources. Never use a centroid as a fake resource position. |
| Directory updates | `PublicAPIClient.refreshRegionPack` exists but has no app caller. Help reads `ContentLibrary.resources(forRegion:)`, i.e. bundled content. | Wire validated cached/refreshed packs into a shared resource store, not just the map. |
| Backend configuration | `PublicAPIClient` defaults to `baseURL == nil`. Alerts have an existing refresh/cache path. | Native maps/search/directions must work independently of Dry Run backend deployment. |
| Public content integrity | `PublicPackStore` validates and atomically stores public JSON. It is not a cryptographic signed-pack implementation. | Preserve its actual guarantees; do not describe ordinary schema validation as signing. |
| Map interactions | No place selection/detail state, local search, location manager, travel preview, saved geographic place model, or map-specific UI tests. | Implement a coherent end-to-end journey, not only markers. |
| Alert geometry | `PublicAlert` is text/zone based; the NWS adapter drops feature geometry. FEMA flood context is fixture-only. | Geographic hazard overlays are a later coordinated schema/adapter/rendering task. Do not draw fake live flood layers. |
| Scanning | RoomPlan capture, same-session room continuation, `StructureBuilder`, a numeric adapter, scan import, confirmation, and 2D/3D views already exist. | Repair and connect these components instead of replacing them with a new scanner. |
| Scan lifecycle | No explicit generation/cancellation guard on late callbacks, no complete interruption/lifecycle model, no explicit app-level camera request flow, and no tracked merge cancellation. | Add a tested coordinator with clear states and ownership. Verify actual hardware behavior separately. |
| Scan completion | The multiroom branch hardcodes `completed: true`, even when using saved rooms after failure. | Preserve incomplete capture and uncertain alignment instead of upgrading them to complete. |
| Home review | Review cannot reassign an unresolved portal to a chosen interior room. Exterior confirmation omits entered clear width. No resident-room assignment is completed by the scan flow. | Make review sufficient to create usable, truthful household geometry. |
| Starting rooms | Replacing the home does not remap `Person.sleepingSpaceID`. `HazardRules.startSpace` silently falls back to a living room or first room. | Stale or missing assignments can produce paths from the wrong room. Fix this alongside scan completion. |
| 3D floors | `DollhouseView.polygonMesh` fan-triangulates polygons. Its comment acknowledges overdraw for concave scans. | Use valid concave triangulation or clearly reject unsupported geometry; preserve visual agreement with the route model. |
| Saving | `AppModel.updateHome` publishes the new home before awaiting persistence. The scan confirmation callback starts an unawaited task and dismisses. | A new scan must commit durably before displaying success; failed saves must preserve the previous committed home. |

The demonstration households matter: **Oak uses Erath County (`48143`), Pine uses Hood (`48221`), Lake uses Tarrant (`48439`)**. Start real regional map coverage with the existing Oak/Pine journeys, then provide honest Tarrant coverage or fallback. Do not assume the original Tarrant-focused proposal is the current dataset.

## 3. Repository orientation and read order

First inspect `AGENTS.md` files if present, `git status`, branch, and existing changes. Adapt paths if the checkout has advanced. Preserve unrelated user work.

Read these groups before assigning work:

1. **App structure and constraints**
   - `README.md`
   - `docs/ARCHITECTURE.md`, `docs/CONTRACTS.md`, `docs/DECISIONS.md`
   - `docs/FRONTEND_HANDOFF.md`, `docs/VERIFICATION.md`, `docs/DEVICE_CHECKLIST.md`
   - `apps/ios/project.yml`
   - `apps/ios/DryRun/App/AppModel.swift`, `RootView.swift`, `Theme.swift`, `DemoLaunch.swift`, `DryRunApp.swift`
2. **Current map and public resources**
   - `apps/ios/DryRun/Help/HelpViews.swift`
   - `apps/ios/DryRun/Services/PublicAPIClient.swift`, `AppServices.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Models/PublicData.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Content/ContentLibrary.swift`, `PublicDataPolicy.swift`, `SampleHouseholds.swift`
   - `packages/DryRunVault/Sources/DryRunVault/PublicPackStore.swift`
   - `content/regions/tx-statewide.json`, `content/regions/tx-25-counties.json`
   - `services/public-api/src/schema.ts`, `app.ts`, `nws.ts`, `fema.ts` and their tests
3. **Private persistence**
   - `apps/ios/DryRun/Services/PrivateDataStore.swift`, `VaultPrivateDataStore.swift`
   - `packages/DryRunVault/Sources/DryRunVault/VaultModels.swift`, `HouseholdVaultRepository.swift`
   - Existing migration, file-protection, integrity, and recovery tests
4. **Scan, review, and geometry**
   - `apps/ios/DryRun/Home/HomeTabView.swift`, `HomeConfirmationView.swift`, `HouseholdSetupView.swift`
   - `apps/ios/DryRun/Spatial/RoomCaptureContainer.swift`, `RoomPlanMapping.swift`, `FloorPlanView.swift`, `DollhouseView.swift`, `ManualHomeEditorView.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Spatial/ScanImport.swift`, `Geometry.swift`, `HomeValidator.swift`, `EgressPlanner.swift`, `PortalAttachment.swift`, `RouteCache.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Models/Home.swift`, `Household.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Session/HomeConfirmation.swift`, `Capabilities.swift`
   - `packages/DryRunCore/Sources/DryRunCore/Simulation/HazardRules.swift`
5. **Plans, localization, and verification**
   - `packages/DryRunCore/Sources/DryRunCore/Plan/PlanBuilder.swift`, `PlanDocument.swift`, `OutageCard.swift`
   - `content/locales/{en,es,vi}/`, translation manifest/baseline
   - `apps/ios/DryRunUITests/`
   - `scripts/mac/verify.sh`, `screens.sh`, `device.sh`

Do not treat older architecture prose as more authoritative than current behavior and tests.

## 4. Desired user journeys

### Journey A: Find a regional resource

A user opens Help without granting location access. Existing emergency contact and assistance access remains immediately available. A prominent map entry opens a full-size native map framed to the selected county. The user can switch between map and accessible list, filter categories, select an actual office, see its source and contact details, and choose whether to call, open its official site, save it, or preview travel.

A county with no verified coordinates shows a sensible regional map and an explicit “No mapped local resources yet” state. Statewide helplines remain in the list; they do not acquire invented map pins.

### Journey B: Search and plan an ordinary trip

The user selects “Search Apple Maps,” reads a short provider/privacy explanation, and searches a place in the visible area. Results are distinctly labeled as Apple Maps search results, not officially activated emergency resources. The user selects a start point and transport mode, then explicitly requests a travel preview. The app shows the returned route with a planning-only explanation and an explicit “Open in Apple Maps” action. Search and directions never auto-launch navigation or silently use an exact home address.

### Journey C: Save an outside meeting place

From Home or Plan, the user keeps the existing text-only meeting place or opens a map picker. They choose a geographic point, label it, and explicitly link it to their home’s outside meeting-place annotation. The point is encrypted in the local vault, survives relaunch, and appears in the household plan with its text/address where available. The map pin does not prove an outdoor path is safe and does not extend an indoor route automatically.

### Journey D: Finish a real home scan

On a supported phone, the user opts into camera access, captures one or more rooms in an aligned session, finishes processing, reviews a 2D/3D proposed home, corrects connections and relevant measurements, assigns people to rooms, then replaces the previous home through an awaited durable save. Relaunch shows the same reviewed home, and a rehearsal starts each person at their explicitly selected room or clearly reports an unresolved starting point.

Unsupported hardware still has the sample/manual home and the entire map experience.

## 5. MapKit implementation — highest priority

### 5.1 Use the native stack and the current design

Use SwiftUI `Map` with explicit camera and selection state, `Marker`/`Annotation`, appropriate native controls, and `MapPolyline` for travel previews. Use `MKLocalSearchCompleter`/`MKLocalSearch` for Apple place search and `MKDirections` for requested travel previews. Use a narrowly scoped UIKit MapKit adapter only if an essential behavior genuinely requires it; do not default to a WebView, MapKit JS, an external map SDK, or server-side map credentials.

Retain `Theme`, current type hierarchy, navigation, cards, and button conventions. Map interactions should feel native: a readable map, compact controls, a selected-place sheet with detents, and an accessible list equivalent. Preserve Apple's attribution/legal UI and map controls using safe-area-aware layout. At large Dynamic Type sizes, prefer an expanded detail/list presentation instead of squeezed controls.

Place the map entry near the top of Help, after immediate assistance access. Do not leave the primary experience as a tiny map at the bottom of a long list. Do not load a full interactive map behind every resource row or keep multiple hidden maps active.

### 5.2 Geographic framing and selection

Introduce validated Foundation-only geographic value types as needed. Keep geographic degrees separate from `Vec2` indoor meters. Add optional region camera hints to the public contract or a small tested public region-geography catalog; document their source and approximation. Full county bounds are browsing context, not a claim that an entire county belongs to a district or is under a particular alert.

Initial camera precedence: an explicitly requested saved/selected place, then the chosen region's bounds/center, then a sensible Texas fallback. Never require a home address or current location to open the map.

Keep browsing county separate from the household's saved region. Changing the map's county must not silently change the household or invalidate rehearsals.

Use stable, namespaced selection identifiers across directory resources, search results, and private saved places. Keep map/list filters and selected detail synchronized. Do not reset the camera on every resource refresh, body evaluation, or gesture. Reframe only for deliberate actions such as switching counties, showing search results, selecting a destination, or recentering.

Avoid force-unwrapped coordinates. Reject non-finite values, latitude outside [-90,90], longitude outside [-180,180], and a coordinate pair with only one member. A rejected location must not remove a useful contact from the list.

### 5.3 Fix the resource pipeline before claiming a useful map

Implement a shared regional-resource repository/store with:

- Immediate bundled baseline.
- Validated per-region cached packs.
- Optional refresh using the existing `PublicAPIClient` when a backend is configured.
- Explicit precedence for new packs and resource/source IDs. `ContentLibrary` currently takes the first duplicate ID; appending updates behind bundled data would keep obsolete records.
- Explicit requested-region identity, cancellation/generation checks, and rejection of mismatched or late responses.
- Separate coverage, provenance, activation, and freshness. Do not upgrade a record to “reviewed” merely because it decoded or has coordinates.
- A stable snapshot shared by Help list, map, and relevant plan/contact generation. A browsing-only region must not substitute into the household's exported plan.

Extend public Swift models, Zod schemas, validation, fixtures, and content together. Keep existing version-1 JSON readable where additive optional fields suffice; otherwise supply a deliberate migration/version policy. Do not break the existing public-query allowlist to support private map searches.

The initial bundled inventory is 13 resources with zero coordinates. Add source-backed coordinates for real physical resources in the existing Erath and Hood sample journeys first. Their listed office addresses are candidates for verification, not authoritative coordinates. Expand further only from traceable official public directories/GIS or other appropriately licensed sources. Record coordinate provenance and verification time. Do not invent coordinates, use a county centroid for an office, or bulk republish proprietary search data without checking permitted use.

Keep statewide assistance lines/registries/federal-aid links in the nonphysical directory unless there is a separately verified relevant public-facing site. An emergency-management office is not automatically a walk-in shelter. Correctly label partial county coverage.

Provide isolated fictional map fixtures for deterministic tests/demos. Never ship fictional pins into the ordinary official directory or present them as live.

### 5.4 Place details and filters

Support useful existing service categories without implying unsupported coverage: emergency management, shelters/cooling/warming sites when sourced, transportation, utility/public-health contacts, and private saved places. Keep nonphysical contact results accessible even though they cannot appear as pins.

A detail view should expose name, category, address when known, source/publisher, last checked time, activation status for relevant sites, accessibility/pet information or explicit unknowns, phone, and official website. Reuse the semantics in `PublicDataPolicy.activationDisplay` and existing `ResourceRow`; extend reusable presentation rather than implementing contradictory badge logic in a new view.

Use text and icons in addition to color. “Location known,” “source reviewed,” and “activated as a shelter” are different states. Distinguish them.

### 5.5 Location permission and lifecycle

Own the location manager for the feature's lifetime through an injectable `@MainActor` service. Request When In Use authorization only after a user action such as “Use my location.” Do not trigger permission on launch, onboarding, opening Help, or displaying a saved home. Ensure adding `UserAnnotation` or a location control does not bypass that intended flow.

Handle not determined, authorized, reduced accuracy, denied, restricted, location services disabled, stale/no fix, timeout, and returning from Settings. Prefer a one-shot location request for a planning task. Avoid background/Always authorization and continuous tracking unless a separately explicit foreground feature needs it, then stop when that feature ends.

Location is optional. Manual origin selection, county browsing, saving a dropped pin, and offline plans remain available. Current location is not automatically the home's location. Do not demand full accuracy for browsing regional resources.

Update the existing `NSLocationWhenInUseUsageDescription` in **project.yml**, not generated Info.plist, to accurately describe the implemented feature. Never log exact coordinates or permission-derived identifiers.

### 5.6 Search

Separate **Filter saved/official resources** (local, offline) from **Search Apple Maps** (network service). Use region-aware suggestions and resolution, a modest debounce, cancellation, and a request-generation guard so old responses cannot replace a later query or county selection. A search-region hint is not proof that every returned place lies within county boundaries.

Do not send private household labels or device descriptions as search queries. Do not auto-search on every map pan. Use a deliberate search action or “Search this area” interaction after panning.

Keep search results in their own ephemeral state. Selecting one does not turn it into a curated public resource, active shelter, or safe destination. A user can explicitly save an independently labeled planning place. Persist only the minimum permissible data needed for that user action, not archived Apple object graphs or bulk POI caches; verify relevant current provider terms.

### 5.7 Travel preview

Ask for an explicit origin and transport mode. Offer current location only with permission; support a selected point or explicitly saved location. Do not silently assume a car or label a walking route wheelchair accessible.

Create `MKDirections` requests only after the user taps a preview action. Cancel superseded requests; handle offline, no route, unsupported transport, timeout, and throttling. Scope a result to its origin, destination, transport, and request generation. Never retain a route from a previous selection after state changes.

Render returned geometry, distance, and travel estimate with wording such as “Planning route — road and emergency conditions may differ.” Show applicable provider advisories. “Open in Apple Maps” is a separate explicit action that leaves Dry Run; an in-app preview remains available without doing that.

Do not call this the safest route, claim it avoids floodwater/fire, or represent a map overlay intersection as a verified alternative-routing engine. Do not auto-navigate or automatically call any telephone number.

Keep this service outside `DryRunCore`'s egress graph and deterministic simulation. An actual device-location estimate is not an indoor starting-room detector.

### 5.8 Offline behavior and honest status

The reliable offline experience is the local resource list, saved private places and their text, cached dated public records, household model, rehearsals, and plans. Apple basemap tiles, new searches, and new travel previews are network-dependent. Consumer Apple Maps offline downloads are not exposed to third-party MapKit apps, and undocumented tile caching is not an offline guarantee.

Do not implement tile scraping/preloading, fake download progress, or “download county map” controls. Do not treat a successful snapshot or path-monitor result as proof all visible map tiles are available. Use actual request errors plus connectivity as a hint, keep the accessible list usable, and explain map limitations without claiming an exact per-tile status the API does not expose.

Avoid persistent cached turn-by-turn instructions in this milestone. They can become misleading and introduce additional provider-data obligations. Preserve user-authored destination details and official contact information with dates.

### 5.9 Optional later layer: real official alert geometry

Do this only after the primary map journey and scan-repair core are integrated. Extend `PublicAlert`, the NWS adapter, Swift/Zod schemas, caches, and fixtures for optional bounded GeoJSON Polygon/MultiPolygon data from official responses. Null geometry is a supported case: show the text/area description without inventing a polygon. Handle multiple rings and holes correctly or clearly decline unsupported rendering.

Preserve issuance/expiry, classification, and source. Official alerts use real wall-clock time, not the rehearsal's 72-hour virtual time. Demo scenario geometry must be opt-in and visibly labeled as an exercise. No alert retrieved must never imply “all clear.” Reuse one shared alert state rather than duplicate refresh loops in map and Help.

Do not show fixture-only FEMA flood context as live inundation. Do not build radar, a flood-prediction engine, or automatic emergency navigation in this pass.

## 6. Private saved places and the home/map connection

Introduce a minimal plain-data private model, for example `SavedPlace`/`PrivateMapState`, with stable ID, purpose, label, optional valid geographic coordinate, optional address text, provenance/verification metadata, and optional reference to a public resource. Support outside meeting point, backup meeting place, fallback destination, and optionally user-marked exterior hydrant/home reference. Keep a point's user confirmation distinct from facility activation evidence.

Use explicit IDs to associate a saved place with the relevant `homeID` and outside-meeting-place annotation. Existing `Annotation.position` is indoor/local `Vec2`; do not put latitude/longitude in it. A text-only meeting point remains valid and useful without a geographic coordinate.

Thread the new data through **every persistence boundary**: `PrivateSnapshot`, in-memory test store, `VaultPayload`, load mapping, save mapping, deletion, and plan generation. The current `VaultPrivateDataStore.save` constructs a fresh payload; forgetting to carry new fields forward would silently drop them on the next unrelated save.

Use backward-compatible decoding or an explicit tested migration. Never reset the vault because a new field is absent, a key is temporarily unavailable, or decoding encounters an unsupported version. Preserve encrypted originals and the existing recovery behavior. Do not place coordinates in UserDefaults, plaintext JSON, logs, screenshots, or analytics.

Save edits transactionally: stage and validate a candidate snapshot, await the protected write, then publish success. Serialize conflicting mutations or use a revision/epoch check so an async save cannot overwrite newer household changes. A failed save must leave the committed state intact and keep the draft available for retry. Apply this to the new map-place and home-replacement flows without an unrelated whole-app rewrite.

When a saved meeting place changes, update/rebuild the relevant plan. Extend the plan's revision/dependency model or deliberately bump the associated home revision so an old saved plan is not mistaken for current. Test ordinary unrelated household edits retain saved places. Replacing a home requires review of stale annotation links rather than silently attaching them to a different structure.

For now, show the geographic meeting point and the separate indoor floor plan. A georeferenced 3D building footprint is **deferred**: RoomPlan's arbitrary local frame does not supply reliable outdoor alignment by itself. Do not invent translation, scale, or north orientation from indoor tracking/GPS.

## 7. Complete the house-scanning feature

### 7.1 Make session ownership and states explicit

Refactor the current controller into a clear coordinator/state machine while keeping RoomPlan behind the app's adapter boundary. It needs supported/unsupported, permission, scanning, room processing, between-room continuation, merging, review, saving, complete, cancelled, and recoverable failure states. A small typed state model is preferable to unrelated booleans.

Create capture resources only after runtime support and camera authorization are satisfied. Request access on “Start scanning,” not at app launch. Preserve Settings and manual/sample fallbacks. Do not add LiDAR to global required-device capabilities.

Own the capture session and merge task. Associate results with a capture-session/generation ID and deduplicate processed room callbacks. Handle delegate errors, interruption/tracking problems, backgrounding, cancellation, view dismantling, and returning from Settings. Reject late results after cancel/replacement and prevent duplicate merge/finish actions. Check current SDK delegate concurrency requirements; do not silence them with blanket `@unchecked Sendable` or by disabling strict concurrency.

The existing between-room `stop(pauseARSession: false)` approach is the appropriate starting point for an uninterrupted shared-frame multiroom capture. Track whether the frame actually remained shared. A session reset or lost alignment must invalidate the merge assumption or require an explicit supported relocalization workflow. Do not hardcode `sharedFrame: true` after every retry.

Keep the first complete supported workflow to single-room and same-session, single-floor multiroom homes. Existing multi-floor/manual data must not regress, but independently captured floors and automatic cross-session alignment are not requirements for declaring this milestone complete.

### 7.2 Normalize geometry conservatively

Keep `RoomPlanMapping` as the conversion boundary and `ScanImport` as testable Foundation-only logic. Do not pass `CapturedRoom`, `ARSession`, RealityKit objects, CoreLocation objects, or Apple matrix types into the core package.

Validate the installed SDK's surface transforms, floor `polygonCorners` frame, dimensions, and story behavior. The current conversion should not be declared correct or wrong solely from a synthetic fixture that repeats its assumptions. Add a physical-device worksheet with known shapes/orientations and approximate measured dimensions.

Use stable source identities and deterministic normalization within a capture; do not rely only on array indexes when reviewing/merging reordered rooms. Validate finite coordinates, polygon shape, duplicate surfaces, doorway attachments, and coordinate-frame consistency. Preserve scan uncertainty separately from household confirmation.

A convex hull reconstructed from wall endpoints may invent traversable area in an L-shaped room. Such a fallback must remain explicitly approximate and must not enable navigation through unverified space. Validate/repair it or require manual review/correction before affected routes become usable. Likewise, do not conceal a second floor surface or unsupported boundary shape through a silent first-surface assumption.

Fix the dollhouse's fan triangulation for concave polygons using a tested triangulation approach. Preserve actual polygon area and do not cover notches/voids with floor mesh. Reject unsupported holes/non-simple polygons with an honest state rather than drawing reassuring but incorrect geometry. 2D, 3D, route calculations, and printed diagrams must derive from the same canonical model.

### 7.3 Correct partial-result behavior

`RoomCaptureController.makeProposedHome` currently passes `completed: true` whenever there is more than one saved room. Fix this so recovering saved rooms after an error keeps incomplete status. Capture completion, geometry coverage, successful normalization, and household review are different facts.

Offer a usable proposed-home preview, not just room/door counts: render the existing floor-plan view and optional dollhouse before replacement. Keep capture notes, unsupported elements, and the remaining review tasks visible. No raw camera images, ARWorldMap, or USDZ export is required or should be added casually to persistence.

### 7.4 Make review sufficient for real scans

Improve `HomeConfirmationView` and core confirmation actions to support:

- Selecting/highlighting the actual room or opening currently under review.
- Naming rooms and assigning their types, with an explicit unknown option.
- Correcting an opening's two sides to identified interior spaces or a genuinely applicable exterior/common-space connection.
- Recording operability, step-free status, and measured clear width without forcing unknowns into true/false.
- **Preserving measured width in exterior confirmation.** The current `.markPortalExterior` action drops it.
- Keeping windows out of generic walking exits, preserving floor constraints and per-person access requirements.
- Marking geometry/layout as partially reviewed versus sufficiently reviewed only after concrete checks. Do not interpret “Done scanning” as “whole home verified.”
- Assigning each household member to an existing starting/sleeping room, or explicitly leaving it unresolved.
- Keeping a text meeting point and optionally choosing/linking a geographic meeting place.

Do not require the user to certify an exit's safety from the scan alone. Use narrowly worded questions about the facts the planner needs. Existing manual editing should be able to repair the same essential connection/measurement metadata; avoid a professional CAD editor scope.

### 7.5 Repair home replacement and rehearsal assumptions

Stage the proposed home separately from the committed one. Ask before replacing an existing home, but not before routine review edits inside the draft. Remap or explicitly clear stale `Person.sleepingSpaceID` references and offer assignments before final commit. Persist the home and corresponding household changes together. Only dismiss as successful when the durable write completes.

Remove the silent “living room or first room” starting-space substitution in `HazardRules` for missing/invalid assignments. Return the existing typed unknown-start result, or use a visibly selected, recorded exercise assumption. Update tests and UI copy accordingly; unknown must not become a claim of entrapment.

Review scenario origin selection as well: the current authored fire `originKind` fallback can block a different room when the requested room kind is absent. A scanned home with all rooms unclassified should not silently produce a kitchen-fire label for an unrelated location. Require explicit room mapping or surface the missing scenario input honestly.

Preserve existing revision invalidation and ensure an old home route/plan never survives a successful replacement as current. Confirm a relaunch loads the same home, assignments, and private map-place links. Verify failed saves preserve the previous home and do not show a success toast or navigate away from the draft.

## 8. Suggested ownership and parallel work

Use available subagents if the environment supports them; otherwise execute the same lanes sequentially. Do not pretend to spawn agents when no such capability exists. Keep the number small and bounded.

**Lead/integration owner:** initial inspection, shared contracts, `AppModel`, private persistence bridge, `project.yml`, navigation entry points, migrations, integration commits, and final verification. Own the common design and resolve interface decisions early.

**Map experience owner:** `Maps/` feature views/state, app-layer MapKit search/directions/location adapters, resource detail/list selection, cancellation and permission handling, saved-place picker UI, map-focused unit/UI tests.

**Public-data owner:** coordinate/source audit, region camera metadata, shared public-resource loading policy, paired Swift/Zod contract updates after lead agreement, validated real resources, public fixtures and contract tests. Optional actual alert polygons only after primary integration.

**Home-capture owner:** RoomPlan coordinator, geometry conversion/import validation, confirmation controls, concave mesh fix, scan fixture tests, and device checklist. Coordinate household assignment and atomic replacement through the lead; do not edit shared AppModel/vault files concurrently.

A final independent review pass should inspect privacy, route wording, unknown states, cancellation, migration safety, and whether new tests actually run. Integrate after each coherent milestone instead of allowing long-lived divergent rewrites. Document ownership before edits, avoid force resets/rebases over user work, and preserve an honest AI-assistance record in the repository's existing documentation.

Suggested new folders/types are `apps/ios/DryRun/Maps/`, an app-layer `RegionalResourcesStore`, `LocationService`, `MapSearchService`, and `MapDirectionsService`, and small Foundation-only geographic/private-place models. These names are suggestions, not a demand to create many empty abstractions. Keep platform objects in adapters and copy plain values across concurrency boundaries deliberately.

## 9. Milestones and completion gates

### M0 — establish baseline and contracts

Inspect environment and checkout; run feasible baseline tests; record current failures without masking them. Establish geographic/private-place models, resource-update precedence, saved-place migration, and ownership. Confirm native build early on a Mac.

### M1 — a useful map with real data

Complete full-size Help map, sensible county camera, at least source-verified physical pins in Erath/Hood, map/list selection, filters, details, contact actions, provenance, coverage gaps, and offline fallback. Existing statewide assistance remains immediately available. The app must work with backend URL unset.

### M2 — location, search, travel preview, and saved meeting places

Complete user-triggered permission handling, local-vs-Apple search distinction, explicit route preview, cancellation, safe wording, vault-backed saved places, and Home/Plan meeting-point linkage. Map/list/plan data dependencies are coherent. This completes the **primary objective**.

### M3 — complete and repair scanning

Complete supported capture -> processing -> geometric preview -> meaningful review -> resident assignments -> atomic save -> reopen -> rehearsal. Fix incomplete multiroom status, late callbacks, width loss, unknown interior sides, unsafe room fallbacks, and concave rendering. Run mock-based state tests and simulator fallback/review tests. Physical-device validation remains separately identified.

### M4 — verification and optional improvements

Run regression suites, new map/scan tests, screenshot review, localization/large-text checks, and a privacy review. Add actual alert polygons or optional Look Around only if core objectives are complete and tested. Do not let these defer a reliable map or save flow.

## 10. Required tests and review evidence

Implement tests that exercise behavior, not only successful construction or snapshots. Use injected clocks, map/search/directions/location adapters, and scan-event fixtures where hardware/network access would make tests flaky.

### Map and public data

1. Missing coordinates remain list-only; half pairs, non-finite/out-of-range coordinates, and wrong-region packs are rejected appropriately.
2. Every supported county has deliberate geographic framing or a documented fallback; a county without resources does not render a fake resource marker.
3. Updated public resources override their old bundled version with correct source references, while unrelated/statewide contacts remain available. The map, list, and household plan resolve the same applicable snapshot.
4. Backend URL unset does not disable native map/search/directions. A successful backend refresh is not necessary to open the feature.
5. No location prompt occurs at launch or merely opening Help/map. Denied, reduced-accuracy, disabled services, and Settings-return paths preserve a useful UI.
6. A late search/location/directions response cannot overwrite a newer query, county, origin, destination, or cancelled view.
7. No travel request happens before an explicit preview action. Selecting another destination clears the prior route. Unknown vehicle access does not silently choose driving.
8. Official resources, Apple search results, personal pins, and fixture/demo data have distinct provenance. Unknown/expired activation is never labeled as an open shelter.
9. Offline map failure leaves contacts, saved-place text, household models, rehearsals, and plans usable. No available alert data is not shown as an all-clear signal.
10. Private location/search/household values cannot enter the Dry Run public-query builder or request log. No private screenshots or coordinates enter test artifacts.

### Vault and plan integration

11. Existing version-1 payloads load after the new feature without resetting the vault. Unsupported/locked/corrupt cases keep their existing distinctions and preserve originals.
12. Saving a place, then editing a household field, then relaunching retains the place. Deleting private data removes it.
13. Save failure leaves the last committed home/place state unchanged and the draft available. Concurrent edits do not overwrite one another silently.
14. Changing a linked meeting place invalidates/rebuilds affected plans. Changing a browsing county does not change the household plan's region.
15. Private home/annotation associations are reviewed or invalidated when a home is replaced. Geographic points are never interpreted as metric floor-plan coordinates.

### Scanning and geometry

16. Unsupported/denied devices never start the capture session; manual/sample flows remain usable.
17. Cancel/background/teardown prevents late callbacks from publishing a home; duplicate callbacks and repeated finish taps cannot append duplicate rooms or trigger multiple commits.
18. Failed capture with multiple saved rooms remains incomplete. A reset/lost frame cannot be merged as an uninterrupted shared-frame scan.
19. Rotated, translated, concave, empty, malformed, and duplicate-surface fixtures have explicit expected results. Concave mesh triangle area matches the accepted polygon rather than filling a notch.
20. Review can assign an unknown portal to an interior room, save measured exterior clear width, preserve unknown operability/accessibility, and reject an invalid connection.
21. Replacing a sample home with scan IDs cannot leave a resident implicitly starting in a different room. Explicit assignments route from the chosen room; unresolved ones remain unresolved.
22. An authored fire origin absent from the home is not silently mislabeled as another room. Existing deterministic scenarios remain reproducible with explicit assumptions.
23. Durable save/relaunch uses the same canonical model in 2D, 3D, route output, and plan. Failed replacement retains the previous committed model.

### UI and actual hardware

24. Deterministic UI journeys cover map entry, selection, filtering, details, denied/offline states, saved meeting point, and scan-fixture review/save. Add screenshot checkpoints for these screens; existing tours never established the map was working.
25. New app-layer unit tests are included in a test target if necessary, and new UI suites actually run through the scheme and verification scripts. Do not merely add test files excluded by `-only-testing` filters.
26. Review EN/ES/VI and large accessibility text for new screens. Add localized keys and maintain the translation baseline; do not claim draft translations are professionally reviewed.
27. Record real LiDAR-device results separately: one room, same-floor multiroom, next room, finish, retry, cancel, interruption/background, privacy indicator teardown, geometry/doorway checks, save/relaunch. Synthetic imported captures and simulator UI are not hardware proof.

Use fictional houses and public facilities for screenshots. Capture at least: regional map with actual curated pins; empty county; selected resource; search-result distinction; explicit route preview; offline list; saved meeting-point picker; proposed scan preview; portal review with width; resident assignments; imported home after relaunch. Inspect screenshots, not just generate them. Avoid recording private homes during test evidence collection.

## 11. Commands and environment handling

Inspect current manifests and scripts before running commands. Suggested baseline from the repository root:

```sh
git status --short
git rev-parse HEAD
swift --version
swift test --package-path packages/DryRunCore
swift test --package-path packages/DryRunVault
(cd services/public-api && pnpm install --frozen-lockfile && pnpm test && pnpm typecheck)
```

On a Mac with Xcode available:

```sh
xcodebuild -version
xcrun simctl list devices available
(cd apps/ios && xcodegen generate)
bash scripts/mac/verify.sh --quick
bash scripts/mac/screens.sh --locales en,es,vi
bash scripts/mac/screens.sh --locales en --xxl
```

Important harness details:

- `project.yml` is the source of truth; regenerate the project rather than editing generated project/plist files.
- The existing quick verification script only selects `DryRunUITests/DemoJourneyUITests`. Extend the scheme/script or run explicit additional `xcodebuild` tests so new app tests, map journeys, and scan journeys really execute.
- The script can exit zero outside CI even when an individual step failed. Inspect its step summary and logs; exit zero is not sufficient evidence.
- A zip extraction may lose executable bits on tracked shell scripts. Restore only the intended tracked script modes if necessary; do not treat this as a source-code regression or chmod the entire repository blindly.
- Preserve dependency locks. Do not upgrade unrelated dependencies to hide an installation/build issue.
- Do not automatically run remote-Mac provisioning, cloud deployment, device signing changes, or destructive cleanup commands. Use an already available authorized environment.

Without a Mac/iOS SDK, complete portable logic, contracts, fixtures, backend tests where possible, and native source changes. Report native compilation and device behavior as unverified. Do not stop all progress because RoomPlan hardware is absent, but do not claim scanning complete on device.

## 12. Final deliverables

Leave an integrated repository, not disconnected examples. Add a concise `docs/MAPKIT_SCAN_INTEGRATION.md` describing architecture, data provenance, privacy boundaries, offline behavior, migrations, and the physical scan checklist. Update existing relevant verification, backlog, and AI-assistance records.

Your final review report must include:

- Implemented features, mapped to M1/M2/M3 and remaining gaps.
- Exact commands run, results, environment, and log/result-bundle locations.
- Which outcomes are verified by portable tests, iOS compilation, simulator journeys, or actual device tests.
- Screenshots from fictional/demo data and findings from visually reviewing them.
- Real resource coordinates added, their official sources, and counties still without mapped coverage.
- A short explanation of what goes to Apple, what goes to Dry Run's public service, and what remains encrypted locally.
- Backward-compatibility and save-failure results.
- Concrete steps for the user to review: launch demo Oak, open map, inspect a resource, preview travel, save a meeting point, open scan/manual review, and confirm a rehearsal uses assigned rooms.
- Any specific hardware/credential/network blocker, with completed fallback work and no invented verification.

Do not call placeholders, mocked maps, fixture weather, a “Start scan” button, or an untested RoomPlan session a complete feature. The primary success criterion is that a real user can make a useful, source-aware map planning choice and retain it privately, then use a correctly reviewed home in the existing app.

## 13. Official technical references

Use these as reference starting points, then check current documentation and installed-SDK declarations for exact signatures and iOS availability. Prefer primary documentation. These links do not authorize unsupported claims about safety or hardware testing.

- Native SwiftUI MapKit, camera, markers, selection, overlays and controls: https://developer.apple.com/videos/play/wwdc2023/10043/
- MapKit for SwiftUI: https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui
- Local search: https://developer.apple.com/documentation/mapkit/mklocalsearch
- Search suggestions: https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter
- Directions: https://developer.apple.com/documentation/mapkit/mkdirections
- Apple directions architecture, server/network behavior: https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/ProvidingDirections/ProvidingDirections.html
- MapKit offline-cache limits, Apple Developer Technical Support response: https://developer.apple.com/forums/thread/772258
- When In Use location authorization: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()
- One-shot location: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()
- Apple Maps privacy: https://www.apple.com/legal/privacy/data/en/apple-maps/
- RoomPlan multiroom/shared-session workflow: https://developer.apple.com/videos/play/wwdc2023/10192/
- Merging captures: https://developer.apple.com/documentation/roomplan/merging-multiple-scans-into-a-single-structure
- Room capture session: https://developer.apple.com/documentation/roomplan/roomcapturesession
- Floor polygon API to verify against the installed SDK: https://developer.apple.com/documentation/roomplan/capturedroom/surface/polygoncorners
- NWS API: https://www.weather.gov/documentation/services-web-api

Begin with environment inspection and baseline tests, establish shared contracts, then implement M1. Continue through M2 and the scan repairs rather than waiting for a design review of isolated components.
