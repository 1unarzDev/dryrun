# MapKit and RoomPlan integration

This integration pass keeps Dry Run's five-tab navigation, iOS 18 deployment target, encrypted local vault, and deterministic rehearsal engine. The map is opened from **Help** and the same map flow is available as a meeting-place picker from **Home**. RoomPlan remains an optional capture path; manual and sample homes work when LiDAR, camera access, network access, or Apple services are unavailable.

## Architecture

- `MapPlanningView` owns map/list parity, county browsing, category filtering, selection sheets, search presentation, route-preview state, and private-place confirmation.
- `RegionalResourcesStore` exposes one validated snapshot to Help, map/list views, and plan generation. Bundled packs are immediate; a validated cached or refreshed region pack replaces matching resource IDs. A county refresh cannot overwrite a newer county selection.
- `AppleMapSearchService`, `AppleMapDirectionsService`, and `OptionalLocationService` keep MapKit and Core Location objects in the app layer. They return plain values to the view, are explicitly started by user actions, and cancel or ignore stale work.
- Public coordinates use `GeographicCoordinate` (degrees) and are never represented as indoor `Vec2` metres. County centers and spans are browsing context, not resource positions or alert polygons.
- `RoomCaptureController` owns one RoomPlan session for a multi-room visit. Processed callbacks are accepted only for the matching finish operation. Cancellation, duplicate callbacks, background interruption, and a retry with a different AR frame cannot publish an unearned complete home.
- `HomeConfirmation` is the gate between proposed scan geometry and verified routing. It supports interior portal assignment, measured exterior width, and unknown operability/step-free evidence. `AppModel.updateHome` writes the complete candidate snapshot before publishing the replacement home.

## Data and privacy boundaries

| Boundary | Data that crosses it | Data that stays out |
| --- | --- | --- |
| Dry Run public service | Allowlisted region ID and public content/resource requests; validated public packs and alerts | Home address, exact coordinates, search text, household, people, medical information, contacts, and indoor models |
| Apple Maps services | Explicit Apple Maps search text, map/directions endpoints, and an optional current-location origin after the user asks for it | Dry Run household records and private vault contents are not sent to the Dry Run service; Apple Maps has its own privacy policy and may receive the requested map inputs |
| Encrypted local vault | Household, home geometry, plans, text meeting annotation, and `SavedPlace` coordinates | No account or household backend is required; the app does not upload these values |

Directory pins carry source IDs and coordinate check dates. A pin does not establish activation, capacity, accessibility, pet acceptance, or safe arrival. Apple route previews are ordinary travel planning aids and are not evacuation, flood-avoidance, or wheelchair-accessibility certifications. Indoor practice routes continue to use the local egress planner.

## Coverage and provenance

The bundled state pack provides statewide contacts and a deliberate Texas browsing frame. The county pack provides frames for all 13 supported counties. Curated physical pins in this pass are the Erath County office (`32.2201556, -98.2023049`, OSM way `119041755`, source `S50`) and Hood County office (`32.4441111, -97.8063216`, OSM way `855408462`, source `S51`). The remaining county records have no verified physical resource pin; the list remains useful and the map reports that gap rather than inventing a marker. Tarrant has a frame for the Lake demo household but no mapped local resource.

## Offline and failure behavior

The bundled directory and private plans open without a backend URL, location permission, or network. A failed refresh keeps the last known-good cached pack; an invalid, oversized, mismatched, or late response is rejected. Apple search and directions show an unavailable state and leave directory contacts, saved places, home geometry, rehearsals, and plans usable. No alert data is treated as an all-clear.

## Vault compatibility and save failures

`VaultPayload` still uses schema version 1. Decoding an older payload with no `savedPlaces` key supplies an empty array, so existing households are not reset. A place, household edit, or home replacement is encoded as one complete candidate snapshot and is published only after the vault save succeeds. A linked-place edit clears the derived plan document so the Plan tab cannot present a document that predates the private place; the household can regenerate it. If a save fails, the previous committed state remains observable and the draft remains in its editor. Replacing a home clears resident room IDs that do not exist in the new geometry; an unresolved person start is reported as unknown by the rehearsal engine instead of falling back to a different room.

## Physical RoomPlan checklist

The Linux checkout cannot run Xcode, the iOS simulator, or a LiDAR device. On a supported iPhone, verify with fictional/demo data and a consenting test space:

1. Grant camera access only after tapping **Start scanning**; scan one room, finish, and inspect the proposed 2D/3D geometry.
2. Continue into a second room in the same visit, finish processing, and check relative placement, duplicate door merging, and floor/portal labels.
3. Finish with a failed/interrupted capture, background the app, cancel, repeat finish taps, and retry. Confirm no late callback adds a room and incomplete work stays incomplete.
4. In review, assign an unresolved interior opening, record a measured exterior width, leave operability or step-free status unknown, and verify unknown evidence stays out of routes.
5. Assign every resident to an explicit room (or leave it unresolved), save the replacement, relaunch, and confirm the same model appears in 2D, 3D, route output, and plan generation.
6. Start a fire rehearsal and verify each person starts in the selected room; a missing/stale assignment reports an unknown start rather than using the living room.
7. Test an unsupported/non-LiDAR phone or denied camera permission: manual/sample homes, map planning, plans, and rehearsals must remain available.

The integration pass has no simulator screenshots or physical-device results to report from this environment; those checks remain open until a Mac/Xcode and LiDAR-capable iPhone are available.
