import Foundation

/// Read-only evidence from a finished authored cursor, never a score or predicted safety outcome.
/// Route feasibility is distinct from an executed arrival; authored runs do not track the latter.
public struct RehearsalDebriefEvidence: Codable, Sendable, Equatable {
    public enum Relocation: String, Codable, Sendable { case used, blocked, notRecorded }
    public var scene: RehearsalScenePresentation
    public var routes: [RouteResult]
    public var resourceReadings: [RehearsalResourceVisual]
    public var serviceIDs: [String]
    public var relocation: Relocation?
    public var relocationEventIDs: [String]
    public var unresolvedRequirementIDs: [String]

    public init(completed cursor: RehearsalCursor) throws {
        let result = cursor.result
        guard cursor.isFinished, let design = RehearsalExperienceDesign.design(scenarioID: result.input.scenarioID),
              let final = result.snapshots.last else { throw SessionError.invalidCommand }
        scene = try RehearsalScenePresentation(hazard: design.hazard, snapshot: final,
            baseline: result.snapshots.first, visibleEvents: result.events, snapshotHistory: result.snapshots)
        switch design.hazard {
        case .homeFire:
            routes = (final.spatialState?.routes ?? []).filter { $0.request.purpose == .outdoorEgress }
            serviceIDs = []; resourceReadings = []
        case .tornado:
            routes = (final.spatialState?.routes ?? []).filter { $0.request.purpose == .interiorShelter }
            serviceIDs = [Svc.alerts]; resourceReadings = []
        case .flashFlood:
            routes = (final.spatialState?.routes ?? []).filter { $0.request.purpose == .higherRefuge }
            serviceIDs = [Svc.roads, Svc.transport]; resourceReadings = []
        case .freezePowerLoss:
            routes = []; serviceIDs = [Svc.heat, Svc.homePower]
            resourceReadings = scene.resources.filter { $0.id.hasPrefix("res.backup.") || $0.id.hasPrefix("res.device.") || $0.id == "res.handset.hours" }
        case .heatGridStrain:
            routes = []; serviceIDs = [Svc.cooling, Svc.homePower]
            resourceReadings = scene.resources.filter { $0.id == "res.water.stored" || $0.id.hasPrefix("res.backup.") }
        case .waterOutage:
            routes = []; serviceIDs = [Svc.waterSupply]
            resourceReadings = scene.resources.filter { $0.id == "res.water.stored" }
        }
        if [.flashFlood, .freezePowerLoss, .heatGridStrain].contains(design.hazard) {
            let events = result.events.filter { $0.evidence.ruleID == "rule.relocation" }
            let used = events.filter { $0.titleKey == "scenario.common.relocation.done" }
            let blocked = events.filter { $0.titleKey == "scenario.common.relocation.blocked" }
            relocation = !used.isEmpty ? .used : !blocked.isEmpty ? .blocked : .notRecorded
            relocationEventIDs = (!used.isEmpty ? used : blocked).map(\.id)
        } else { relocation = nil; relocationEventIDs = [] }
        unresolvedRequirementIDs = final.unmetRequirements.sorted()
    }
}
