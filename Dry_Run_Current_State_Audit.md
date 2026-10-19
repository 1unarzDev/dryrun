# Dry Run: current-state audit and integration priorities

**Review date:** October 16, 2026  
**Input:** uploaded `dryrun(1).zip`  
**Repository HEAD:** `163de3212cd06178d8bf26ad7d9f8c0661568449`  
**Companion implementation handoff:** `Dry_Run_MapKit_Codex_Handoff.md`

## Scope and verification

This is a source-level audit of the uploaded repository, not an implementation or a physical-device test. The source archive was extracted and its relevant Swift, TypeScript, JSON, tests, and project documentation inspected. Archive contents were unavailable through file-text search, so source was read directly from the extracted files.

Independently executed:

```text
swift test --package-path packages/DryRunCore
Swift 6.2.1, x86_64 Linux
143 tests in 22 suites passed
```

The raw output accompanies this audit as `dryrun_core_test.log`.

There was no Xcode/iOS SDK, simulator, or LiDAR device in this review environment. The vault and backend suites were not independently rerun. `docs/VERIFICATION.md` records prior Mac/simulator runs, but those are historical project-reported results. Some source comments saying “not compiled” are older than that record. No claim about physical RoomPlan completion follows from either.

No application source was changed. The extracted archive showed executable-mode loss on tracked shell scripts; this is distinct from a semantic code change.

## Bottom line

The app already has the right components for native maps and scanned-home rehearsal. Its next step is integration rather than a rewrite.

**The immediate map blocker is data:** the map filters out records without coordinate pairs, and every bundled resource lacks those pairs. **The main scan blocker is an incomplete end-to-end lifecycle:** capture proposals can reach review, but failed-session state, editable connections, resident assignments, and durable replacement are not fully handled.

Preserve the five current tabs, iOS 18 baseline, native design, deterministic core, and private vault. Complete a useful Help map first; then make scan -> review -> save -> rehearsal trustworthy.

## Findings with source locations

Paths and line numbers refer to the audited commit. They may move in later checkouts.

| Finding | Evidence | Consequence / recommended change |
|---|---|---|
| MapKit is present, but only as an embedded directory map. | `apps/ios/DryRun/Help/HelpViews.swift:48–56,147–158` | Replace the 300-point bottom-of-directory experience with a prominent full-size map destination inside Help. Add camera, selection, details, filters, and an accessible list. |
| All bundled map markers are excluded. | `HelpViews.swift:151–152`; `content/regions/tx-statewide.json`; `content/regions/tx-25-counties.json` | Thirteen unique resources, zero coordinate pairs. Add verified physical-site coordinates; leave nonphysical helplines list-only. |
| Help consumes bundled resources, not updated packs. | `HelpViews.swift:14–16`; `apps/ios/DryRun/Services/PublicAPIClient.swift:46–55`; no caller of `refreshRegionPack` found | Add a shared bundled/cache/refresh store with explicit override precedence and source identity. Use the applicable snapshot for map, list, and plans. |
| The backend is deliberately optional. | `PublicAPIClient.swift:20–30` and `AppModel` client setup | Keep native map/search/directions independent of backend deployment. |
| Geographic presentation metadata is absent. | `packages/DryRunCore/Sources/DryRunCore/Models/PublicData.swift:38–100` | Resource coordinates are optional; region camera hints and alert geometry are not represented. Add small compatible geographic contracts, not Apple objects in the core. |
| Resource provenance/activation semantics already exist. | `HelpViews.swift:121–143`; `Content/PublicDataPolicy.swift` | Reuse these on map details. Coordinates or search matches must not create an “open shelter” claim. |
| Public pack storage validates JSON, not cryptographic signatures. | `packages/DryRunVault/Sources/DryRunVault/PublicPackStore.swift` | Preserve actual guarantees; do not mistake the original signed-pack proposal for an implemented feature. |
| Scan continuation and merge are already implemented. | `apps/ios/DryRun/Spatial/RoomCaptureContainer.swift:37–46,80–91` | Repair the existing shared-session workflow rather than building another scanner. |
| Late callbacks are not scoped to active capture generations. | `RoomCaptureContainer.swift:49–78` | Cancel can clear state, then a queued callback can append a result/change phase. Add session identity, cancellation checks, deduplication, and tracked merge tasks. This is a static failure risk, not an observed device reproduction. |
| Multiroom recovery loses incomplete status. | `RoomCaptureContainer.swift:84–87` | The merge branch always passes `completed: true`, including saved-room recovery after failure. Preserve the actual capture result. |
| Capture setup/lifecycle needs completion. | `RoomCaptureContainer.swift:21–24,95–143`; app scene-phase handling | The capture view is created before the view's support branch. Add explicit permission-driven creation and interruption/background/teardown handling. Native implicit permission behavior was not tested here. |
| Scan review initially shows counts, not a proposed-home preview. | `RoomCaptureContainer.swift:189–201` | Show the normalized 2D/3D home and unresolved elements before replacement. |
| Unresolved interior connections cannot be corrected in confirmation. | `Home/HomeConfirmationView.swift`; `Session/HomeConfirmation.swift:41–49` | Add explicit side-to-room mapping instead of allowing only exterior/reject/skip. Highlight the opening under review. |
| Measured width is dropped for exterior confirmation. | `Session/HomeConfirmation.swift:18–23,76–94` | Generic portal confirmation records width; exterior confirmation neither accepts nor records it. Thread the value through the exterior action and test it. |
| Home replacement does not update people's room references. | `App/AppModel.swift:256–262`; `Simulation/HazardRules.swift:154–157` | Imported IDs differ from the old home. Add resident-room assignments and remove the silent living-room/first-room fallback for unresolved starts. |
| Fire-origin fallback can target a different room. | `Simulation/HazardRules.swift:209–216` | If the requested room kind is missing, a fallback blocks a route's last room. Require an explicit mapping or clearly expose the missing assumption for scanned homes. |
| Save success is presented before persistence completes. | `Home/HomeTabView.swift:130–135`; `AppModel.swift:256–262,459–465` | Stage home and household assignments, await durable save, then publish/dismiss. Preserve prior committed state on failure. |
| Reconstructed outlines can be overly broad. | `Spatial/ScanImport.swift:113–131` | A floor-polygon fallback uses a convex hull. Preserve approximation/measurement requirements and do not enable paths through an invented notch/void. |
| 3D concave floors can overdraw. | `Spatial/DollhouseView.swift:144–154` | Fan triangulation is inadequate for general concave rooms. Validate a proper triangulation or reject unsupported shapes explicitly. |
| Meeting points have local/text semantics, not geographic coordinates. | `Models/Home.swift` annotation model; `Session/HomeConfirmation.swift:103–107` | Add a private geographic saved-place model linked by ID. Do not put latitude/longitude in local `Vec2` fields. |
| New saved fields can be lost at the vault bridge. | `Services/PrivateDataStore.swift`; `Services/VaultPrivateDataStore.swift` | Both load and save map only existing snapshot fields. Extend every boundary and test unrelated edits preserve saved places. |
| New tests would be skipped by the current quick harness. | `scripts/mac/verify.sh`, UI-journey `-only-testing` invocation; `apps/ios/project.yml` | Register new app/unit/UI targets and run their suites explicitly. Script exit zero outside CI is not sufficient evidence; inspect per-step results. |

## Bundled geographic data inventory

The statewide pack contains five resources; the county pack contains eight. Every resource is marked `curated` and `needsReview` in the current JSON. This does not mean every contact is incorrect; it means the app must not overstate verification or activation.

| County | Region ID | County resource count | Coordinate pairs | Current coverage label |
|---|---|---:|---:|---|
| Callahan | 48059 | 0 | 0 | notStarted |
| Comanche | 48093 | 1 | 0 | oemOnly |
| Eastland | 48133 | 0 | 0 | notStarted |
| Erath | 48143 | 1 | 0 | verifiedPartial |
| Hood | 48221 | 1 | 0 | verifiedPartial |
| Jack | 48237 | 1 | 0 | oemOnly |
| Johnson | 48251 | 0 | 0 | notStarted |
| Palo Pinto | 48363 | 1 | 0 | oemOnly |
| Parker | 48367 | 1 | 0 | oemOnly |
| Somervell | 48425 | 1 | 0 | oemOnly |
| Stephens | 48429 | 0 | 0 | notStarted |
| Tarrant | 48439 | 0 | 0 | notStarted |
| Young | 48503 | 1 | 0 | oemOnly |

County resource counts exclude the five statewide services that can also be shown for a county. A coverage label is not a promise of full local coverage, and a county's `verifiedPartial` label does not override its individual resource's `needsReview` state.

The existing demo profile sequence is Oak/Erath, Pine/Hood, Lake/Tarrant. Therefore start real mapped-resource verification with Erath and Hood rather than inventing a fresh demonstration geography. Tarrant should show either newly verified real resources or a clear coverage gap.

## Proposed map experience

**Help -> prominent map entry -> county-framed native map -> select a place -> source-aware details -> explicit planning action.** Keep emergency contacts and statewide assistance directly available. Preserve the current five-tab layout.

The map should offer a synchronized list, category filters, deliberate region switching, optional current location, local directory filtering, clearly separate Apple place search, explicit ordinary travel previews, and vault-backed saved meeting/fallback places. Show source, checked date, activation evidence, unknown accessibility/pet information, and contact actions in each relevant detail.

Initial map camera framing must work without location permission and with no markers. County framing must not fabricate an office location. User camera movement must not be reset by every fetch. Old search/route results must not overwrite newer selections.

Use the existing public client for public regional packs, not for private search queries or routes. MapKit can remain usable while the Dry Run backend is unconfigured. The optional NWS polygon layer belongs after these features; the existing alert model/adapter needs a coordinated extension before it can render actual source geometry.

## Proposed home-to-map connection

Represent three distinct things:

1. The private metric home model used by the local rehearsal engine.
2. A private saved geographic place used for meeting/fallback planning.
3. Publicly sourced regional facilities and alerts.

Link a home's meeting-place annotation to an explicitly selected saved geographic place by stable IDs. Text-only meeting points remain supported. Selecting a map pin does not georeference the whole scanned house or prove an outdoor route is usable. Defer automatic building-footprint overlay and arbitrary cross-session/multistory alignment.

## Completion priorities

| Priority | Outcome |
|---|---|
| M0 | Baseline tests, installed-SDK check, shared public/private geographic contracts, test ownership. |
| M1 | Actual regional pins, full-size Help map, camera framing, filters, details, source/coverage states, offline list. |
| M2 | Optional location, Apple search, explicit travel preview, saved meeting place, migration and plan integration. Primary map objective complete. |
| M3 | Capture lifecycle repair, geometric preview, editable connections/widths, resident assignments, atomic home replacement, truthful rehearsal assumptions. |
| M4 | New suites included in the harness, screenshots reviewed, localization/large-text checks, real-device checklist, optional actual alert geometry. |

The full handoff defines agent ownership, suggested files, commands, 27 acceptance checks, and the required final report. It does not require another planning conversation before implementation.

## Apple platform constraints verified during this review

Native SwiftUI MapKit provides camera control, annotation selection, map styles, and overlays. This supports the recommended native interface without introducing a web map architecture. [Apple: Meet MapKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10043/)

Apple's Technical Support guidance says the consumer Maps app's offline downloads are not available to third-party apps, and the system basemap has no app-controlled tile preloading/cache interface. Preserve offline contacts, places, and plans; do not promise downloadable Apple county basemaps. [Apple DTS: MapKit tile/offline behavior](https://developer.apple.com/forums/thread/772258)

Directions use a server-backed service. Treat a preview as network-dependent and distinguish requests to Apple from requests to Dry Run's own public backend. [Apple: Providing Directions](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/ProvidingDirections/ProvidingDirections.html)

RoomPlan's multiroom workflow relies on properly aligned captures. Preserving an AR session between rooms and then using the structure builder is the appropriate basis for the current code; interrupted or unrelated frames require additional handling. [Apple: Explore enhancements to RoomPlan](https://developer.apple.com/videos/play/wwdc2023/10192/)

For occasional location use, Apple documents a one-shot `requestLocation` workflow rather than unnecessarily running continuous location updates. [Apple: Reduce Location Accuracy and Duration](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)

## Definition of a successful review build

A user can open Oak, find a source-backed regional facility on the map without location permission, inspect its limitations, deliberately preview travel, and retain an outside meeting place privately. On supported hardware they can capture/review/save a home, assign residents to its rooms, relaunch, and run the fire exercise without silent room substitutions. On unsupported hardware, the sample/manual workflow and map remain fully usable.

A simulator-tested capture UI is not physical scan verification. A green core suite is not proof of a working map. A rendered route is not proof of safe travel. The final engineering report should keep those distinctions explicit.
