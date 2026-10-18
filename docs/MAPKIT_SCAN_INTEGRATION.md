# MapKit and RoomPlan integration — October 17

Three destinations: Prepare, Rehearse, Plan. Native iOS 18 deployment baseline, encrypted local vault and
pure deterministic engine remain. A personal household may intentionally have no layout; basic preparations,
contacts and family card still work. Fictional examples never become evidence about a personal home.

## Home-centered planning

The shared MapPlanningView opens from Plan, Home and meeting preparations. Home/private saved annotations are
independent of selection sheets. Places include text-only landmarks, dropped coordinates, purpose, finding
instructions, provenance and check date. Primary nearby and backup/out-of-neighborhood meetup purposes differ.
Saving a resource suggestion does not silently make it a meetup. Geographic meetup links use savedPlaceID and
never invent local indoor geometry.

HomeAddressEditorView supplies Apple completion, manual location/pin correction, separate unit/derived metadata,
and explicit correction versus moving home. Typed planning does not require GPS. One bounded nearby discovery
batch searches hospitals, pharmacies and groceries using independent requests; generation checks reject old
address/category results. Discovery is cancellable/retryable; rural radius expansion/search-area controls exist.
Directions start at saved home by default, with current location/other saved places and mode choices.

Unknown/foreign addresses do not substitute a Texas region. RegionalResourcesStore and the public backend retain
allowlisted Texas coverage only; Apple/local planning is independent. County names are not trusted region IDs.
Apple results do not establish emergency department capability, opening/stock, activated shelter status, safe
arrival, or wheelchair-accessible disaster routes. Saved text details remain available without map tiles.

## Plans, imagery and privacy

PlanBuilder accepts optional home and savedPlaces. Its plain snapshot carries canonical layout, selected places,
qualified current routes and revisions. The family card is useful without map/scan. Live plan updates after edits;
retained scenario output is labeled stale when facts change. Publish follows successful protected save.

PlanMapSnapshotRenderer uses transient MKMapSnapshotter images, adds intended symbols at snapshot coordinates,
keeps Apple's full legal/attribution image and separates distant destinations into panels. Timeout/failure leaves
text and the home diagram. No tile cache or imagery is retained in the vault; explicit temporary PDFs are protected.
Apple documentation and Maps agreement were consulted (Attachment 6, 2.1 attribution and 2.5 limited caching);
this is not a legal certification of every downstream distribution use. Inspect native exports before release.

| Service | Allowed requested inputs | Excluded |
|---|---|---|
| DryRun public service | Allowlisted public region/content queries | Address, search text, coordinates, people, clinical/contact records, scans |
| Apple services | Chosen address/search area/endpoints, optional requested GPS, map snapshot extent | Indoor scan, medical information, contact names |
| Local vault | Household, optional home, private places, retained document | No account/upload required |

Offline essentials are contacts, place text/coordinates, saved home and plan. Live search, fresh alerts, directions
and arbitrary Apple tiles are not promised offline. Optional model explanations are restricted to unparameterized
general authored text; routes and clinical instructions remain deterministic/sourced.

## RoomPlan and correction

Native capture uses RoomCaptureSession support independently of network/location/intelligence. The controller
retains connected rooms in a shared AR frame and processes them with StructureBuilder. Callback generations bind
to originating sessions; cancellation/retry/interruption and repeated Finish must reject stale publication.
Captured floor story is preserved separately from user-confirmed ground/above/below/walkout grade. Stair endpoints
are not guessed by vertical overlap. Windows need explicit emergency-escape suitability, not inventory confirmation.

The same HomeModel drives confirmation, manual canvas, room list, 2D/3D, routes and PDF. Contextual edits preserve
unrelated width/operability. The canvas supports constrained shape-preserving resize/move, explicit levels and
first rooms per level, and two separately positioned stair landings. A new opening-wall selection is required
when changing the selected opening. Captured outlines/walls remain provenance; independent/ambiguous captured
barriers are retained. Corrected rooms and their proposed connections need separate review. Dynamic outline walls
follow additions/deletions without a stale wall cache. Shelter confirmation/planning/simulation share current
floor/window/review checks. Free vertex/CAD and independent captured-wall editing are not provided.
Save is transactional; same-home rescans normalize to stable identity and preserve
geographic places, remapping only assignments supported by capture lineage/manual identity. Moving is a separate confirmed reset of home-specific
geometry/places/checks while family/contact/equipment records persist.

## Evidence limits

Core tests exercise plain import, grade, route purposes, openings, stage state and callback gates. Native tests for
map request isolation and private transactions are authored. **No current native compile, simulator run, Apple
search/snapshot, or physical scan occurred here.** RoomPlan categories/transforms/story/structure assumptions
require installed-SDK build and consenting measured-space verification. Follow CLAUDE_NATIVE_HANDOFF and
DEVICE_CHECKLIST; do not call source parsing device readiness.

The latest map request owner captures origin/mode/destination once and rejects late GPS and SDK results after
cancellation, selection or home changes; cancelled loading state resets. Family sharing uses bounded attributed
map panels and fails closed on a newly requested plan save failure; no old consent selection is exported.
Cards retain dropped-pin coordinates and contact roles as text. Scan review disables accidental dismissal;
explicit save/Finish later retain drafts on failed writes. Shared 2D/3D/list opening status includes actual
blockage, operability, grade and relevant mobility evidence; unknown/no-route starts keep a recorded room marker.

Selected-language follow-up: MapPlanningView uses shared country-aware distance and selected-language travel-time formatting, including unknown invalid estimates, and structured PhoneLink for calling. Resource categories/statuses and source-language fallback labels are localized. Scan-import note forms, floor/opening/marker selected values and default annotation labels now resolve in all three packs without rewriting custom room/annotation text. Locale completeness tests are portable; installed SDK, live Apple calls and actual capture remain pending.

## Latest integration

No-op/unit-only address edits preserve explicitly supported coverage; actual geographic changes clear it.
Official text-only resources now open shared save/contact/directions details. Saved source IDs, publishers,
check dates, phone/URL and Apple suggestion provenance survive privately; saving does not imply activation.
Meetup pins take precedence over optional-resource map caps, retaining matching text numbers.

RoomPlan processing of retained earlier groups freezes the selected group/frame and invalidates callbacks from
the interrupted live session before stopping/processing. Valid groups remain drafts on processing failure.
Room assignments survive rescans only with capture lineage/manual evidence; new ordinal IDs alone are not proof.
Person-scoped window eligibility and canonical helper routes tighten routing. The real SDK transforms, shared
frame, native callback timing and physical measurements are still pending; no native build is implied.

## Claude continuation: current SDK and physical gates

The owner explicitly requested Claude take over PDF/visual refinement and continued goal completion with
ideators and actual UI inspection. Read CLAUDE_CONTINUE_PROMPT and the complete original goal. The latest
hosted Xcode16.4/iOS18.5 run fails both simulator and unsigned iphoneos targets on NearbyDiscovery's task-group
closure at MapKitAdapters:193. Earlier RoomPlan optional-session/NSCoding and MapKit response-transfer/POI
errors were corrected; further errors may surface. No successful app target, simulator journey or physical
capture is claimed. The owner will have a connected LiDAR iPhone Pro and signing account on the existing Mac.
Capture teardown/retry, stable SDK room IDs, endpoint invalidation, shared map extents/provenance and partial
snapshot notices now have source/portable evidence only. Verify the actual device and native renderer before
claiming readiness, especially shared frames, floor transforms/grade and late callbacks.
