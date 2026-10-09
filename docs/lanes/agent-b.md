# Agent B lane report — home model, geometry, routing, RoomPlan adapter

Author: AI (Agent B, Claude). All code below is AI-generated; see docs/AI_ASSISTANCE.md.

## Status

| Item | Status | Evidence |
|---|---|---|
| `SampleHomes` (ranch, two-storey, apartment), fictional | TESTED_CORE | `fixtures/homes/*.json` regenerated + equality test |
| Geometry utilities (`Geometry`, `GeometryTolerance`, `RigidTransform3D`) | TESTED_CORE | `GeometryTests` |
| `HomeValidator` → typed `HomeIssue` (short, user-readable `message`) | TESTED_CORE | `SpatialFixtureTests` |
| `PortalAttachment` (single shared-edge / wall-band rule used by planner, validator, audit) | TESTED_CORE | `RouteTests`, `RouteAdversarialTests` |
| `EgressPlanner` (verified portal graph, hard exclusions, Dijkstra, alternative independence, typed no-route) | TESTED_CORE | `RouteTests` (10 tests) |
| `RouteCache` / `HomeFingerprint` / `RouteResult.isCurrent(for:)` / `HomeModel.edit` | TESTED_CORE | `editingDoorVerificationInvalidatesCachedRoute` |
| `RouteGeometryAudit.violations` (wall/boundary/obstacle crossing check of drawn paths) | TESTED_CORE | used by every route test |
| `ScanImport` (plain RoomPlan mirror → proposed `HomeModel`) | TESTED_CORE (synthetic input only) | `GeometryTests` scan cases |
| `ManualLayout` (attach rooms, shared walls, doors, derived display walls) | TESTED_CORE | `SpatialManualLayoutTests` |
| `RoomPlanMapping`, `RoomCaptureController`, `RoomScanFlowView` | IMPLEMENTED (authored; `swiftc -parse` only) | no iOS SDK here |
| `FloorPlanView`, `DollhouseView`, `HomeRoomListView`, `ManualHomeEditorView` | IMPLEMENTED (authored; `swiftc -parse` only) | no iOS SDK here |
| Real RoomPlan capture, multiroom on device, RealityView rendering | PENDING hardware | nothing device-tested |

Test command: `DRYRUN_SCRATCH=b scripts/swift.sh packages/DryRunCore test` → full package 119 tests in 19 suites pass, 0 known issues
(Swift 6.2, Linux, Docker; after the routing-review fixes below). Spatial-lane suites: RouteTests, SpatialFixtureTests, GeometryTests,
SpatialManualLayoutTests, plus Agent A's RouteAdversarialTests.
Regenerate home fixtures: run the same with `DRYRUN_WRITE_FIXTURES=1` passed into the container (scripts/swift.sh does not forward env; see `.build-linux/b-tools/stage.sh` pattern or add `-e`).

## Public API (DryRunCore)

- `SampleHomes.ranch | twoStory | apartment | all`, `SampleHomes.rect(...)`
- `EgressPlanner(tolerance:)`: `EgressPlanning.plan(_:in:) -> RouteResult`
- `RouteCache(planner:)`: `route(_:in:)`, `count`, `invalidateAll()`; `RouteCacheKey`; `HomeFingerprint.of(_:)` (128-bit FNV over
  sorted-key JSON; NaN/inf encoded as strings so encoding never collapses to a constant)
- `RouteResult.homeFingerprint` (additive optional field in Models/Home.swift, set by the planner) and `RouteResult.isCurrent(for:)`,
  which requires id + revision + algorithm + content fingerprint; a result without a fingerprint is never current
- `HomeModel.edit { }` (mutate + bump revision)
- `PortalAttachment.check / underlyingWall`
- `RouteGeometryAudit.violations(_ path:, in:)`
- `RoomPaths.anchor / path / segmentOK` (within-room geometry)
- `HomeValidator.validate(_:) -> [HomeIssue]` (`kind`, `severity`, `elementID`, `message`)
- `ScanImport.importCapture(_:homeID:label:) throws -> ScanImportResult` with `ScanCapture/ScanRoom/ScanSurface/ScanObject`
- `ManualLayout.newHome / addRoom / addPortal / sharedWall / exteriorWall / derivedWalls`
- `Geometry`, `GeometryTolerance.standard`, `RigidTransform3D`

iOS (apps/ios/DryRun/Spatial/): `FloorPlanView(home:routes:highlightedFloorID:)`, `DollhouseView(home:routes:floorID:)`,
`HomeRoomListView(home:)` (rows only, for use inside a List section), `ManualHomeEditorView(home:onSave:)`,
`RoomScanFlowView(onFinish:)`. None depend on `AppModel`.

Contract change (requested by lead): additive `RouteResult.homeFingerprint: String?` (+ defaulted init param) in `Models/Home.swift`.

## Routing rules (as implemented)

- Hard exclusions before search: scenario-blocked spaces/portals/connectors; portals not `.verified` (proposed/unknown/rejected);
  `.unknown` destinations; `.commonArea` destinations (building corridor is outside the model → `missingBuildingPlan`);
  windows as interior connections; any exterior portal not on a ground floor (`level == 0 && elevation <= 1.0 m`) — covers
  upper-floor windows and balconies; doors whose operability is unknown/false; step-free and clear-width mobility checks.
- Clear width: only a CONFIRMED width satisfies a requirement. A scanned (unconfirmed) or unknown width excludes the
  portal for step-free profiles and adds `<portal>.clearWidth` to `verificationNeeded` for walking. A known width below the
  envelope (walking 0.70 m, wheelchair 0.82 m — planning envelopes, not accessibility certification) excludes it.
- Windows: an exit ONLY if verified + operable confirmed + ground floor + not step-free profile, and then carries
  `<portal>.windowEscapeEveryPerson`. None of the sample windows qualify.
- Elevators are never used for egress; stairs require `.verified` and are excluded for step-free profiles.
- Portal attachment (`PortalAttachment.check`, one rule for planner, validator, and audit):
  shared edge = the two OUTLINES are within `boundaryContactMeters` (0.05 m) of each other at the portal; otherwise the portal must
  sit inside the gap between the outlines and the gap must be a plausible wall — at most the thickness of an explicit wall under the
  portal (+ contact), or, with no explicit wall, between `minimumWallThicknessMeters` 0.10 m (framed 2x4 + drywall ≈ 0.114 m) and
  `maximumWallThicknessMeters` 0.45 m. A 6–9 cm unexplained gap never connects; a door centred in a 15 cm scanned wall does.
  One-sided (exterior) portals: within contact of the outline plus half an explicit wall's thickness. Approach points are offset past
  the wall band so the clearance envelope still holds; the audit allows crossings inside each used portal's band.
- Hard requirements use `confirmedValue`: operability, step-free thresholds, window operability, and clear width are satisfied only by
  confirmed values. Scan-observed or unknown values never satisfy them; a known "no"/too-narrow value (even unconfirmed) still rules out.
- Within-room paths: straight segment if it crosses no wall/space edge, keeps the clearance envelope from walls/corners and
  obstacles, and stays in the room; otherwise a visibility-graph detour via obstacle corners and inward-offset room corners;
  otherwise no edge. Portal crossings may meet walls only inside that portal's span (minus 5 cm).
- Dijkstra ties break by node ID; exit ties by node ID → deterministic.
- Alternative: re-plan excluding the primary exit AND every interior chokepoint (all spaces after the start, all interior portals,
  connectors). Found → `independent`. Otherwise re-plan excluding only the primary exit → `sharesChokepoint` with
  `sharedChokepoints`; else `none`. On the ranch, the living room has an independent alternative; bedrooms share the hall.
- No-route diagnosis (typed): `unknownStartSpace`, `invalidGeometry`, start blocked → `blockedByScenario`; then relax mobility
  (→ `incompatibleMobility`), then scenario (→ `blockedByScenario`); else `missingBuildingPlan` if a common-area portal exists;
  else `incompleteConnectivity` or `noVerifiedExteriorExit`.
- Exterior paths end just outside the exit; the outside route to the meeting point is NOT drawn (outdoor geometry is unknown).

## Sample home facts other lanes rely on (ranch)

Exits `pt-front` (living, step-free, 0.90 m) and `pt-back` (kitchen, one step). `pt-bed1-hall` width unknown (wheelchair: no route
from sp-bed1). `sp-closet` is the tornado candidate (`interiorNoWindowsConfirmed` true; annotation note says not engineered).
Fire demo: blocking `sp-kitchen` leaves bedrooms → hall → living → front; blocking `sp-hall` → `blockedByScenario` from bedrooms;
from `sp-living` blocking `pt-front` → back door. Confirming `pt-win-bed1` (verified + operable) makes it a window exit for walkers.

## Routing review fixes (docs/lanes/review-routing.md, Agent A)

All seven items fixed; the five `withKnownIssue` probes in `RouteAdversarialTests.swift` are now ordinary assertions and pass.
1 confirmedValue for hard requirements · 2 fingerprint in `isCurrent`, NaN-safe fingerprint · 3 near-touching gaps rejected
(validator too, reported once per portal) · 4 thick-wall scans route (walking and wheelchair, audit clean) · 5 hull fallback flagged ·
6 DollhouseView applies `Floor.toCommon` (authored; parse-checked only) · 7 DollhouseView scene key = id + revision + content
fingerprint + floor + every route point (authored; parse-checked only).
Not changed (out of lane / by design): helper-access planning (simulation lane); same-room alternatives are `independent`
(UI should say "both exits are in this room"); exits only on level 0 (walk-out basements need an explicit confirmation feature).

## Known gaps / risks

- iOS files are not compiled. Likely friction points to check first in Xcode: `RoomCaptureViewDelegate` NSCoding requirements
  under Swift 6 isolation; `CapturedRoom` Sendability when hopping to the main actor; `realityViewCameraControls` availability;
  `MeshResource.generate(from:)` isolation; floor `polygonCorners` frame (assumed surface-local — verify with a real scan).
- Scan import: a room without a floor outline falls back to the convex hull of its walls and is marked `needsMeasurement` and the home
  `incomplete` (an L-shape would otherwise silently become a rectangle). Building the outline from an ordered wall chain is backlog.
- Scan import derives adjacency only from door/opening surfaces near room boundaries; room labels default to "Room N" (RoomPlan
  sections/labels not used yet). Concave floor slabs render with a fan (display only).
- Within-room routing is portal-to-portal visibility, not a navmesh; very narrow or highly concave rooms can yield no edge
  (fails closed). Anchor point is the centroid or nearest valid 0.25 m grid point; per-person positions are not modelled.
- Wall clearance is enforced along segments; door approach points sit 0.45 m from the wall, so the effective envelope is
  capped at 0.40 m half-width.
- Manual editor supports one floor and rectangular rooms; stairs/connectors and multi-floor manual layouts are backlog.
- `HomeValidator` messages are English-only strings (not yet locale keys).
