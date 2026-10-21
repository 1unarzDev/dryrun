import Foundation

/// Authored educational scene. Geometry exclusions, text and both renderers read these same values.
/// No fields represent predicted physical spread, safe time or injury risk.
public struct SpatialExerciseOptions: Codable, Sendable, Hashable {
    public var originSpaceID: String?
    public var startingSpaceIDs: [String: String]
    public var floodAffectedSpaceIDs: [String]
    public var floodIsHouseholdLeak: Bool
    public var refugeSpaceID: String?
    public init(originSpaceID: String? = nil, startingSpaceIDs: [String: String] = [:], floodAffectedSpaceIDs: [String] = [],
                floodIsHouseholdLeak: Bool = false, refugeSpaceID: String? = nil) {
        self.originSpaceID = originSpaceID; self.startingSpaceIDs = startingSpaceIDs
        self.floodAffectedSpaceIDs = floodAffectedSpaceIDs; self.floodIsHouseholdLeak = floodIsHouseholdLeak
        self.refugeSpaceID = refugeSpaceID
    }
}

/// Committed exercise position, never evidence that a person physically completed an action.
public struct ExerciseOccupantState: Codable, Sendable, Hashable {
    public var personID: String
    public var currentSpaceID: String?
    public var exteriorExitPortalID: String?
    public var shelteredSpaceID: String?
    public var accountedOutside: Bool
    public init(personID: String, currentSpaceID: String? = nil, exteriorExitPortalID: String? = nil,
                shelteredSpaceID: String? = nil, accountedOutside: Bool = false) {
        self.personID = personID; self.currentSpaceID = currentSpaceID
        self.exteriorExitPortalID = exteriorExitPortalID; self.shelteredSpaceID = shelteredSpaceID
        self.accountedOutside = accountedOutside
    }
}

public struct SpatialExerciseState: Codable, Sendable, Hashable {
    /// Absent in historical snapshots. Route overlays alone never establish arrival.
    public var occupants: [ExerciseOccupantState]?
    public var hazard: HazardKind
    public var seed: UInt64
    public var stageID: String
    public var originSpaceID: String?
    public var affectedSpaceIDs: [String]
    public var affectedPortalIDs: [String]
    public var destinationSpaceID: String?
    public var routes: [RouteResult]
    public var assumption: String
    public var assumptionKey: String?
    public var exposedSpaceIDs: [String]?
    public init(hazard: HazardKind, seed: UInt64, stageID: String, originSpaceID: String? = nil,
                affectedSpaceIDs: [String] = [], affectedPortalIDs: [String] = [], destinationSpaceID: String? = nil,
                routes: [RouteResult] = [], assumption: String, assumptionKey: String? = nil, exposedSpaceIDs: [String]? = nil) {
        self.assumptionKey = assumptionKey; self.exposedSpaceIDs = exposedSpaceIDs
        self.hazard = hazard; self.seed = seed; self.stageID = stageID; self.originSpaceID = originSpaceID
        self.affectedSpaceIDs = affectedSpaceIDs; self.affectedPortalIDs = affectedPortalIDs
        self.destinationSpaceID = destinationSpaceID; self.routes = routes; self.assumption = assumption
    }
}

public extension RehearsalInput {
    /// Native preflight choices use recorded variants so replay and comparison retain exactly the same assumptions.
    var effectiveSpatialOptions: SpatialExerciseOptions {
        if let spatialOptions { return spatialOptions }
        var options = SpatialExerciseOptions()
        for variant in variants {
            if variant.hasPrefix("origin:") { options.originSpaceID = String(variant.dropFirst(7)) }
            if variant.hasPrefix("waterEntry:") { options.floodAffectedSpaceIDs = [String(variant.dropFirst(11))] }
            if variant.hasPrefix("refuge:") { options.refugeSpaceID = String(variant.dropFirst(7)) }
            if variant == "householdLeak" { options.floodIsHouseholdLeak = true }
            if variant.hasPrefix("start:") {
                let values = variant.dropFirst(6).split(separator: "|", maxSplits: 1).map(String.init)
                if values.count == 2 { options.startingSpaceIDs[values[0]] = values[1] }
            }
        }
        return options
    }
}
