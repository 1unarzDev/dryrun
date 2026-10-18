import Foundation

public enum HomeIssueKind: String, Codable, Sendable, Hashable, CaseIterable {
    case invalidPolygon
    case duplicateID
    case unknownFloor
    case exteriorGradeUnknown
    case portalUnverified
    case portalDestinationUnknown
    case portalSpaceMissing
    /// A portal that claims to join spaces/exterior but does not lie on the boundary of each claimed space
    /// (e.g. near-touching walls with a gap). Never treated as a connection.
    case portalNotOnSharedBoundary
    case windowNotAnExit
    case upperFloorExteriorPortal
    case commonAreaOutsideModel
    case noVerifiedExteriorExit
    case missingMeetingPoint
    case connectorUnverified
    case spaceNeedsMeasurement
    case spaceLabelUnconfirmed
    case clearWidthUnknown
    case structureIncomplete
    case overlappingSpaces
    case shelterCandidateNotEngineered
}

public enum HomeIssueSeverity: String, Codable, Sendable, Hashable { case blocking, needsConfirmation, info }

public struct HomeIssue: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(elementID)" }
    public var kind: HomeIssueKind
    public var severity: HomeIssueSeverity
    public var elementID: String
    public var message: String
    public init(kind: HomeIssueKind, severity: HomeIssueSeverity, elementID: String, message: String) {
        self.kind = kind; self.severity = severity; self.elementID = elementID; self.message = message
    }
}

/// Produces the confirmation-pass checklist. Pure and deterministic (sorted by severity, kind, element).
public enum HomeValidator {
    public static func validate(_ home: HomeModel, tolerance: GeometryTolerance = .standard) -> [HomeIssue] {
        var out: [HomeIssue] = []
        let floors = Dictionary(home.floors.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let spaces = Dictionary(home.spaces.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var seen = Set<String>()
        let allIDs = home.floors.map(\.id) + home.spaces.map(\.id) + home.portals.map(\.id) + home.walls.map(\.id)
            + home.obstacles.map(\.id) + home.connectors.map(\.id) + home.annotations.map(\.id)
        for id in allIDs where !seen.insert(id).inserted {
            out.append(HomeIssue(kind: .duplicateID, severity: .blocking, elementID: id, message: "ID \(id) is used more than once."))
        }

        for floor in home.floors where floor.exteriorGrade == .unknown || (home.source == .roomPlanScan && floor.exteriorGrade == nil) {
            out.append(HomeIssue(kind: .exteriorGradeUnknown, severity: .needsConfirmation, elementID: floor.id,
                message: "Confirm how \(floor.label) relates to exterior ground; captured story order cannot establish a walking exit."))
        }
        for s in home.spaces {
            if floors[s.floorID] == nil { out.append(HomeIssue(kind: .unknownFloor, severity: .blocking, elementID: s.id, message: "\(s.label) refers to a missing floor.")) }
            if !Geometry.isSimplePolygon(s.polygon) {
                out.append(HomeIssue(kind: .invalidPolygon, severity: .blocking, elementID: s.id, message: "\(s.label) has an invalid outline."))
            }
            if s.needsMeasurement { out.append(HomeIssue(kind: .spaceNeedsMeasurement, severity: .needsConfirmation, elementID: s.id, message: "\(s.label) needs measurement.")) }
            if !s.labelConfirmed { out.append(HomeIssue(kind: .spaceLabelUnconfirmed, severity: .needsConfirmation, elementID: s.id, message: "Confirm the name of this room.")) }
        }
        // Overlap check: a vertex of one space strictly inside another on the same floor.
        for (i, a) in home.spaces.enumerated() {
            for b in home.spaces[(i + 1)...] where a.floorID == b.floorID {
                let ca = Geometry.centroid(a.polygon), cb = Geometry.centroid(b.polygon)
                if a.polygon.contains(where: { Geometry.contains(b.polygon, $0, tolerance: tolerance.boundaryContactMeters) })
                    || b.polygon.contains(where: { Geometry.contains(a.polygon, $0, tolerance: tolerance.boundaryContactMeters) })
                    || Geometry.contains(b.polygon, ca) || Geometry.contains(a.polygon, cb) {
                    out.append(HomeIssue(kind: .overlappingSpaces, severity: .blocking, elementID: "\(a.id)|\(b.id)", message: "\(a.label) and \(b.label) overlap."))
                }
            }
        }

        var verifiedGroundExit = false
        for p in home.portals {
            guard let floor = floors[p.floorID] else {
                out.append(HomeIssue(kind: .unknownFloor, severity: .blocking, elementID: p.id, message: "Opening refers to a missing floor.")); continue
            }
            let ground = Graph.isGround(floor, tolerance) && !(home.source == .roomPlanScan && floor.exteriorGrade == nil)
            for side in [p.sideA, p.sideB] {
                switch side {
                case .unknown:
                    out.append(HomeIssue(kind: .portalDestinationUnknown, severity: .needsConfirmation, elementID: p.id, message: "Where does this \(p.kind.rawValue) lead?"))
                case .commonArea:
                    out.append(HomeIssue(kind: .commonAreaOutsideModel, severity: .needsConfirmation, elementID: p.id,
                                         message: "This opens to a shared building area that is not modelled. Use the building's posted evacuation route."))
                case .space(let sid):
                    guard let s = spaces[sid] else {
                        out.append(HomeIssue(kind: .portalSpaceMissing, severity: .blocking, elementID: p.id, message: "Opening refers to a missing room.")); continue
                    }
                    if (s.floorID != p.floorID || !PortalAttachment.check(p, in: home, tolerance: tolerance).attached)
                        && !out.contains(where: { $0.kind == .portalNotOnSharedBoundary && $0.elementID == p.id }) {
                        out.append(HomeIssue(kind: .portalNotOnSharedBoundary, severity: .blocking, elementID: p.id,
                                             message: "This opening is not on a wall of \(s.label); it is not treated as a connection."))
                    }
                case .exterior: break
                }
            }
            if p.verification != .verified && p.verification != .rejected {
                out.append(HomeIssue(kind: .portalUnverified, severity: .needsConfirmation, elementID: p.id, message: "Confirm the \(Self.describe(p, in: home))."))
            }
            if p.leadsToExterior {
                if !ground {
                    out.append(HomeIssue(kind: .upperFloorExteriorPortal, severity: .info, elementID: p.id, message: "Above ground level: not a walking exit."))
                } else if p.kind == .window {
                    out.append(HomeIssue(kind: .windowNotAnExit, severity: .info, elementID: p.id,
                                         message: "Windows are not exits unless you confirm everyone who would use it can open it and climb out."))
                } else if p.verification == .verified {
                    verifiedGroundExit = true
                }
            }
            if p.clearWidthMeters.value == nil && p.kind != .window && p.verification != .rejected {
                out.append(HomeIssue(kind: .clearWidthUnknown, severity: .needsConfirmation, elementID: p.id, message: "Measure the clear width of the \(Self.describe(p, in: home))."))
            }
        }
        if !verifiedGroundExit {
            out.append(HomeIssue(kind: .noVerifiedExteriorExit, severity: .blocking, elementID: home.id, message: "No verified ground-level exterior exit."))
        }
        if home.meetingPoint == nil {
            out.append(HomeIssue(kind: .missingMeetingPoint, severity: .needsConfirmation, elementID: home.id, message: "Choose an outside meeting point."))
        }
        for c in home.connectors where c.verification != .verified {
            out.append(HomeIssue(kind: .connectorUnverified, severity: .needsConfirmation, elementID: c.id, message: "Confirm these \(c.kind.rawValue) connect the two floors."))
        }
        for a in home.annotations where a.kind == .tornadoShelterCandidate {
            out.append(HomeIssue(kind: .shelterCandidateNotEngineered, severity: .info, elementID: a.id,
                                 message: "A shelter candidate is a planning choice, not an engineered safe room."))
        }
        if home.completeness != .complete {
            out.append(HomeIssue(kind: .structureIncomplete, severity: .needsConfirmation, elementID: home.id,
                                 message: home.completenessNote ?? "Parts of this home are not modelled."))
        }
        let rank: [HomeIssueSeverity: Int] = [.blocking: 0, .needsConfirmation: 1, .info: 2]
        // One issue per (kind, element): `HomeIssue.id` must be unique for SwiftUI lists.
        var seenIssues = Set<String>()
        out = out.filter { seenIssues.insert($0.id).inserted }
        return out.sorted { (rank[$0.severity]!, $0.kind.rawValue, $0.elementID) < (rank[$1.severity]!, $1.kind.rawValue, $1.elementID) }
    }

    /// "window in Kitchen", "door between Hallway and Kitchen", "door from Kitchen to outside": which opening an issue
    /// is about, in the household's own room names, so several "Confirm this window" rows can be told apart.
    static func describe(_ p: Portal, in home: HomeModel) -> String {
        func name(_ side: PortalDestination) -> String? {
            switch side {
            case .space(let id): home.space(id)?.label
            case .exterior: "outside"
            case .commonArea(let label): label
            case .unknown: nil
            }
        }
        let kind = p.kind == .window ? "window" : p.kind.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2",
                                                                                         options: .regularExpression).lowercased()
        let a = name(p.sideA), b = name(p.sideB)
        switch (a, b) {
        case let (a?, "outside"), let ("outside", a?): return p.kind == .window ? "\(kind) in \(a)" : "\(kind) from \(a) to outside"
        case let (a?, b?): return p.kind == .window ? "\(kind) in \(a)" : "\(kind) between \(a) and \(b)"
        case let (a?, nil), let (nil, a?): return "\(kind) in \(a)"
        case (nil, nil): return kind
        }
    }
}
