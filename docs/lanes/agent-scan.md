# RoomPlan and home-review lane

Ownership for this lane covers `apps/ios/DryRun/Spatial`, the scan confirmation view, and the portable spatial
import/geometry tests in `packages/DryRunCore`. The lane deliberately leaves `AppModel`, vault persistence, and map
state to the integration owners.

Implemented in this pass:

- Room capture callbacks are accepted only while the matching stop is processing. Cancel, duplicate callbacks,
  retry, and background interruption cannot publish a late room. Retrying after an interruption invalidates the shared
  AR frame instead of silently merging rooms from separate sessions.
- Multiroom proposed homes retain `sessionCompleted == false` after a failed/interrupted capture. A saved-room
  recovery is never upgraded to complete by the UI controller.
- Confirmation can assign an unresolved interior opening side to a selected room before operability and route
  verification. Exterior confirmation has a measured-width answer that stores a finite positive width as confirmed
  evidence; the original no-measurement answer remains available. The review controls preserve unknown
  operability/step-free evidence instead of forcing a yes/no answer.
- Dollhouse floor slabs use the shared core ear-clipping triangulator. Concave outlines preserve their notches and
  malformed/self-intersecting outlines return no mesh.

Portable core and vault verification ran through the repository's Swift 6.2 Docker harness, and every iOS Swift source
file passes `swiftc -parse` there. Native RoomPlan callbacks, StructureBuilder alignment, RealityKit rendering,
simulator behavior, and physical LiDAR capture remain device/SDK checks for the final integration pass.
