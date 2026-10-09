# Adversarial review: spatial / routing lane

Reviewer: Agent A (did not write this code). Scope: `packages/DryRunCore/Sources/DryRunCore/Spatial/**`, `apps/ios/DryRun/Spatial/**` (read-only).
Probes: `packages/DryRunCore/Tests/DryRunCoreTests/RouteAdversarialTests.swift` (16 tests). Confirmed defects are in `withKnownIssue` blocks,
so the suite stays green and a fix shows up as "known issue was not recorded" (then remove the wrapper).
Run: `DRYRUN_SCRATCH=a scripts/swift.sh packages/DryRunCore test --filter RouteAdversarial`.
Result at review time: full package `105 tests in 17 suites passed with 6 known issues`.

## Confirmed defects

| # | Severity | Where | Failure scenario | Suggested fix |
|---|---|---|---|---|
| 1 | **High** (safety semantics) | `EgressPlanner.swift:296`, `:299-300`, `:303-304` | Hard requirements use `.value` rather than `.confirmedValue`. A household-verified ground-floor window whose operability is only `scanObserved` (`.scanned(true)`) becomes a usable exit. A door whose step-free threshold is only scan-observed satisfies a wheelchair route. Probe: `scannedValuesTreatedAsConfirmed` (2 known issues). | Use `confirmedValue` for operability and step-free checks. Keep using `.value` for the "too narrow" rejection (line 306), which is the conservative direction. |
| 2 | **Medium** (stale results) | `RouteCache.swift:58` `isCurrent(for:)` | Compares only `homeID`, `revision` and algorithm. If an edit forgets to bump the revision (e.g. back door changed to rejected), an old route still reports `isCurrent == true`. `RouteCache` itself is safe because its key includes the content fingerprint, but UI and plan code that call `isCurrent` are not. Probe: `cacheStaleness`. | Store `homeFingerprint` in `RouteResult` (additive field) and compare it in `isCurrent`, or remove `isCurrent` and route all checks through `RouteCacheKey`. Separately, `HomeFingerprint.of` falls back to `Data()` when encoding throws (a NaN coordinate), so every such home gets the same fingerprint. Return nil or throw instead. |
| 3 | **Medium** (false adjacency) | `EgressPlanner.swift:157-158` (`boundaryContactMeters` = 0.05) | Two rooms 9 cm apart (near-touching, with no explicit walls, as in a manual or wall-less home) connect through a portal placed in the gap. Each endpoint is 4.5 cm from both outlines, so both sides accept it. Probe: `nearTouching`. | Also require the two spaces' boundaries to be within the tolerance of *each other* along the portal span, or require the portal segment to lie on a shared edge (both outlines within `epsilon`). Apply the same rule in `HomeValidator.swift:91-93`. |
| 4 | **Medium** (functional, scans) | `EgressPlanner.swift:157-158` vs RoomPlan geometry | Real scans give floor outlines at inner wall faces, with a ~0.10–0.20 m wall between rooms. A door centred in a 15 cm wall is 7.5 cm from each outline (> 5 cm), so after the household verifies every door the planner still drops it as `invalidGeometry`. Verified scanned homes can end up with no connectivity. Probe: `thickWallScan`. | Give each portal a wall-thickness band: accept endpoints within `max(boundaryContact, wallThickness/2 + boundaryContact)` of each side, using the scanned wall thickness. Validate the crossing against explicit walls, as `crossingIsClear` already does. Needs a fixture from a real scan. |
| 5 | **Low–Medium** (geometry honesty) | `ScanImport.swift:121-128` | A room with no floor outline falls back to the convex hull of its walls but is not marked `needsMeasurement`; the note says it needs measurement but the flag is false. An L-shaped room becomes a rectangle that can overlap neighbours, invent adjacency proposals, and allow shortcut paths across the missing corner. Probe: `scanImportProposalsOnly` (known issue). | Set `needsMeasurement = true` and `completeness = .incomplete` on the hull fallback. Better: build the outline from ordered wall endpoints when they form a closed chain. |
| 6 | **Low** (3D display) | `apps/ios/DryRun/Spatial/DollhouseView.swift:68` (`p3`) | The 3D builder stacks floors using only `elevationMeters` and ignores `Floor.toCommon`. Any home whose floors have a non-identity common transform (rotated/offset storeys, or future multi-session scans) shows upper floors misaligned with stairs and routes. 2D is unaffected because it draws per floor. | Apply `floor.toCommon.apply(v)` before mapping to RealityKit (x, elevation, -y). |
| 7 | **Low** (3D cache) | `DollhouseView.swift:24` | The scene cache key is `home.id#revision#floor#exit:length`. An edit without a revision bump, or two different routes with the same exit and length, reuses a stale scene. | Include `HomeFingerprint.of(home)` and a hash of the route points in the key. |

## Probed and holding (no defect found)

- **Shortcut paths:** L-shaped room around a reflex corner and an obstacle on the naive line both produce paths with no wall, boundary or obstacle crossings (`RouteGeometryAudit` is empty) and keep more than 0.3 m from the obstacle.
- **Doors near corners:** a door 0.1 m from a corner is still reachable without violations (the suspected defect did not reproduce).
- **Things that are not exits:** proposed portals, `.unknown` destinations, `.commonArea` (reported as `missingBuildingPlan`), windows with unconfirmed operability, and verified exterior doors on an upper floor.
- **Stairs:** unverified stairs are never used; verified stairs are excluded for step-free routes (`incompatibleMobility`).
- **Step-free unknowns:** unknown width and unknown threshold are both rejected for wheelchair routes.
- **Shared chokepoints:** in the ranch, bed2's two exits through the same hallway are reported `sharesChokepoint` with `sp-hall` listed, not `independent`.
- **Rotation/translation:** rotating 36.87° and translating by (-13.7, 42.1) m keeps the space sequence, exit, and length (within 1e-6), with no violations.
- **Determinism:** symmetric equal-cost exits and reversed portal/space/wall/obstacle arrays give identical primaries and alternatives.
- **ScanImport:** every portal is `.proposed`, no portal is exterior, operability is unknown, widths are unconfirmed, room labels are unconfirmed, and independently framed multi-room captures are refused.
- **Fire rehearsal:** across 3 households × {default, second-exit-blocked}, no route passes through an authored blocked space or portal after its start room, and every drawn segment passes the audit.
- **2D and 3D drawing:** both draw exactly `RoutePath.legs[].points`, one straight segment per pair, no smoothing (`FloorPlanView.swift:127-130`, `DollhouseView.swift:103-106`).

## Gaps that are out of scope for a fix in this lane

- **Helper access (simulation lane, `HazardRules.swift` `assistanceCheck`).** The fire rehearsal says "{helper} helps {person}" but never checks that the helper's path to that person's room avoids the blocked spaces. If the dependent's room is reachable only through the fire origin, the plan still pairs them. No text tells a helper to re-enter (choice `go-back-in` is unsafe and never recommended), but the pairing can be unrealistic. Suggested: plan helper-start → dependent-room under the same exclusions and, if blocked, emit `assist.blocked` and an unmet requirement instead of `assist.assigned`.
- **Same-room alternatives:** an exterior exit in the start room counts as `independent` (the start room is never a chokepoint). That is reasonable, but the UI should say "both exits are in this room" when it happens.
- **Exits on level 0 only** (`Graph.isGround`): a walk-out basement door (level -1) is never an exit. This is conservative but a false negative; consider an explicit per-portal "ground-level exterior" confirmation.
