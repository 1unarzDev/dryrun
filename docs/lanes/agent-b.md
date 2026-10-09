# Agent B lane report — home model, geometry, routing, RoomPlan adapter

Author: AI (Agent B, Claude). All code below is AI-generated; see docs/AI_ASSISTANCE.md.

## Status

| Item | Status | Evidence |
|---|---|---|
| `SampleHomes` (ranch, two-storey, apartment), fictional | TESTED_CORE | `fixtures/homes/*.json` regenerated + equality test |
| Geometry utilities (`Geometry`, `GeometryTolerance`, `RigidTransform3D`) | TESTED_CORE | `GeometryTests` |
| `HomeValidator` → typed `HomeIssue` (short, user-readable `message`) | TESTED_CORE | `SpatialFixtureTests` |
| `EgressPlanner` (verified portal graph, hard exclusions, Dijkstra, alternative independence, typed no-route) | TESTED_CORE | `RouteTests` (10 tests) |
| `RouteCache` / `HomeFingerprint` / `RouteResult.isCurrent(for:)` / `HomeModel.edit` | TESTED_CORE | `editingDoorVerificationInvalidatesCachedRoute` |
| `RouteGeometryAudit.violations` (wall/boundary/obstacle crossing check of drawn paths) | TESTED_CORE | used by every route test |
| `ScanImport` (plain RoomPlan mirror → proposed `HomeModel`) | TESTED_CORE (synthetic input only) | `GeometryTests` scan cases |
| `ManualLayout` (attach rooms, shared walls, doors, derived display walls) | TESTED_CORE | `SpatialManualLayoutTests` |
| `RoomPlanMapping`, `RoomCaptureController`, `RoomScanFlowView` | IMPLEMENTED (authored; `swiftc -parse` only) | no iOS SDK here |
| `FloorPlanView`, `DollhouseView`, `HomeRoomListView`, `ManualHomeEditorView` | IMPLEMENTED (authored; `swiftc -parse` only) | no iOS SDK here |
| Real RoomPlan capture, multiroom on device, RealityView rendering | PENDING hardware | nothing device-tested |

Test command: `DRYRUN_SCRATCH=b scripts/swift.sh packages/DryRunCore test --filter "RouteTests|SpatialFixtureTests|GeometryTests|SpatialManualLayoutTests"` → 22 tests, all pass (Swift 6.2, Linux, Docker).
Regenerate home fixtures: run the same with `DRYRUN_WRITE_FIXTURES=1` passed into the container (scripts/swift.sh does not forward env; see `.build-linux/b-tools/stage.sh` pattern or add `-e`).

## Public API (DryRunCore)

- `SampleHomes.ranch | twoStory | apartment | all`, `SampleHomes.rect(...)`
- `EgressPlanner(tolerance:)`: `EgressPlanning.plan(_:in:) -> RouteResult`
- `RouteCache(planner:)`: `route(_:in:)`, `count`, `invalidateAll()`; `RouteCacheKey`; `HomeFingerprint.of(_:)`
- `RouteResult.isCurrent(for: HomeModel)`; `HomeModel.edit { }` (mutate + bump revision)
- `RouteGeometryAudit.violations(_ path:, in:)`
- `RoomPaths.anchor / path / segmentOK` (within-room geometry)
- `HomeValidator.validate(_:) -> [HomeIssue]` (`kind`, `severity`, `elementID`, `message`)
- `ScanImport.importCapture(_:homeID:label:) throws -> ScanImportResult` with `ScanCapture/ScanRoom/ScanSurface/ScanObject`
- `ManualLayout.newHome / addRoom / addPortal / sharedWall / exteriorWall / derivedWalls`
- `Geometry`, `GeometryTolerance.standard`, `RigidTransform3D`

iOS (apps/ios/DryRun/Spatial/): `FloorPlanView(home:routes:highlightedFloorID:)`, `DollhouseView(home:routes:floorID:)`,
`HomeRoomListView(home:)` (rows only, for use inside a List section), `ManualHomeEditorView(home:onSave:)`,
`RoomScanFlowView(onFinish:)`. None depend on `AppModel`.

No changes to lead-owned contract files.

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
- Portals must lie on the boundary of each space they claim to join (0.05 m) — near-touching rooms never connect.
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

## Known gaps / risks

- iOS files are not compiled. Likely friction points to check first in Xcode: `RoomCaptureViewDelegate` NSCoding requirements
  under Swift 6 isolation; `CapturedRoom` Sendability when hopping to the main actor; `realityViewCameraControls` availability;
  `MeshResource.generate(from:)` isolation; floor `polygonCorners` frame (assumed surface-local — verify with a real scan).
- Scan import derives adjacency only from door/opening surfaces near room boundaries; room labels default to "Room N" (RoomPlan
  sections/labels not used yet). Concave floor slabs render with a fan (display only).
- Within-room routing is portal-to-portal visibility, not a navmesh; very narrow or highly concave rooms can yield no edge
  (fails closed). Anchor point is the centroid or nearest valid 0.25 m grid point; per-person positions are not modelled.
- Wall clearance is enforced along segments; door approach points sit 0.45 m from the wall, so the effective envelope is
  capped at 0.40 m half-width.
- Manual editor supports one floor and rectangular rooms; stairs/connectors and multi-floor manual layouts are backlog.
- `HomeValidator` messages are English-only strings (not yet locale keys).
