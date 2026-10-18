import Foundation

// APP-OWNED canonical home model. Owner: lead (schema); Agent B (geometry semantics).
// Units: metres. Each floor has its own 2D plane (x = east-ish, y = north-ish in floor frame,
// right-handed, viewed from above). `Floor.toCommon` places floor coordinates in the shared frame.
// Navigation truth lives here, never in USDZ.

public struct Vec2: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to o: Vec2) -> Double { (self - o).length }
}

public struct Vec3: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
}

/// Rigid 2D transform: rotate (radians, counter-clockwise) then translate. No scaling, no axis snapping.
public struct Transform2D: Codable, Sendable, Hashable {
    public var rotationRadians: Double
    public var translation: Vec2
    public init(rotationRadians: Double = 0, translation: Vec2 = Vec2(0, 0)) {
        self.rotationRadians = rotationRadians; self.translation = translation
    }
    public static let identity = Transform2D()
    public func apply(_ p: Vec2) -> Vec2 {
        let c = cos(rotationRadians), s = sin(rotationRadians)
        return Vec2(c * p.x - s * p.y + translation.x, s * p.x + c * p.y + translation.y)
    }
}

public struct CoordinateFrame: Codable, Sendable, Hashable {
    public var units: String
    public var handedness: String
    /// Which source axis was "up" before projection (RoomPlan uses +y up).
    public var sourceUpAxis: String
    public var note: String?
    public init(units: String = "meters", handedness: String = "right", sourceUpAxis: String = "y", note: String? = nil) {
        self.units = units; self.handedness = handedness; self.sourceUpAxis = sourceUpAxis; self.note = note
    }
}

public enum HomeSource: String, Codable, Sendable, Hashable { case sample, manual, roomPlanScan }

public enum VerificationState: String, Codable, Sendable, Hashable, CaseIterable {
    /// Household confirmed in the confirmation pass.
    case verified
    /// Proposed by geometry/scan; not yet confirmed. Never satisfies a hard route requirement.
    case proposed
    case unknown
    /// Household said this is not a usable connection.
    case rejected
}

public enum ExteriorGrade: String, Codable, Sendable, Hashable, CaseIterable { case unknown, ground, aboveGround, belowGround, walkout }

public struct Floor: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var level: Int
    public var label: String
    public var elevationMeters: Double
    public var toCommon: Transform2D
    /// Captured story is not exterior grade. nil preserves pre-migration manual/sample semantics.
    public var exteriorGrade: ExteriorGrade?
    public var capturedStory: Int?
    public init(id: String, level: Int, label: String, elevationMeters: Double = 0, toCommon: Transform2D = .identity, exteriorGrade: ExteriorGrade? = nil, capturedStory: Int? = nil) {
        self.id = id; self.level = level; self.label = label; self.elevationMeters = elevationMeters; self.toCommon = toCommon
        self.exteriorGrade = exteriorGrade; self.capturedStory = capturedStory
    }
}

public enum SpaceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case bedroom, livingRoom, kitchen, dining, bathroom, hallway, closet, laundry, garage, stairwell, office, other
}

public struct Space: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var floorID: String
    public var label: String
    public var kind: SpaceKind
    /// Simple polygon in floor coordinates (metres), counter-clockwise.
    public var polygon: [Vec2]
    public var labelConfirmed: Bool
    public var needsMeasurement: Bool
    /// Interior room with no exterior windows on the lowest floor, as declared by the household.
    /// A candidate is NOT an engineered safe room.
    public var interiorNoWindowsConfirmed: EvidenceValue<Bool>
    /// An explicitly reviewed higher refuge has a way out and is not a closed attic. Unknown is not suitable.
    public var higherRefugeConfirmed: EvidenceValue<Bool>?
    public init(id: String, floorID: String, label: String, kind: SpaceKind, polygon: [Vec2], labelConfirmed: Bool = true,
                needsMeasurement: Bool = false, interiorNoWindowsConfirmed: EvidenceValue<Bool> = .unknown, higherRefugeConfirmed: EvidenceValue<Bool>? = nil) {
        self.id = id; self.floorID = floorID; self.label = label; self.kind = kind; self.polygon = polygon
        self.labelConfirmed = labelConfirmed; self.needsMeasurement = needsMeasurement
        self.interiorNoWindowsConfirmed = interiorNoWindowsConfirmed; self.higherRefugeConfirmed = higherRefugeConfirmed
    }
}

/// Explicit wall segment (floor coordinates). Portals are openings in walls.
public struct WallSegment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var floorID: String
    public var a: Vec2
    public var b: Vec2
    public var thicknessMeters: Double
    public init(id: String, floorID: String, a: Vec2, b: Vec2, thicknessMeters: Double = 0.12) {
        self.id = id; self.floorID = floorID; self.a = a; self.b = b; self.thicknessMeters = thicknessMeters
    }
}

public enum PortalKind: String, Codable, Sendable, Hashable, CaseIterable {
    case door, slidingDoor, opening, window, garageDoor
}

public enum PortalDestination: Codable, Sendable, Hashable {
    case space(String)
    case exterior
    case commonArea(String)
    case unknown
}

public struct Portal: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var floorID: String
    public var kind: PortalKind
    /// Endpoints of the opening along its wall (floor coordinates).
    public var a: Vec2
    public var b: Vec2
    public var sideA: PortalDestination
    public var sideB: PortalDestination
    public var clearWidthMeters: EvidenceValue<Double>
    /// Can be opened by the household without tools/keys (user-confirmed).
    public var operable: EvidenceValue<Bool>
    /// Step-free threshold (user-confirmed).
    public var stepFree: EvidenceValue<Bool>
    public var verification: VerificationState
    /// Window inventory alone never establishes an emergency escape option.
    public var emergencyEscapeConfirmed: Bool?
    public var note: String?
    public init(id: String, floorID: String, kind: PortalKind, a: Vec2, b: Vec2, sideA: PortalDestination, sideB: PortalDestination,
                clearWidthMeters: EvidenceValue<Double> = .unknown, operable: EvidenceValue<Bool> = .unknown,
                stepFree: EvidenceValue<Bool> = .unknown, verification: VerificationState = .proposed, note: String? = nil, emergencyEscapeConfirmed: Bool? = nil) {
        self.emergencyEscapeConfirmed = emergencyEscapeConfirmed
        self.id = id; self.floorID = floorID; self.kind = kind; self.a = a; self.b = b; self.sideA = sideA; self.sideB = sideB
        self.clearWidthMeters = clearWidthMeters; self.operable = operable; self.stepFree = stepFree
        self.verification = verification; self.note = note
    }
    public var center: Vec2 { Vec2((a.x + b.x) / 2, (a.y + b.y) / 2) }
    public var leadsToExterior: Bool { sideA == .exterior || sideB == .exterior }
}

public struct Obstacle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var floorID: String
    public var label: String
    public var polygon: [Vec2]
    public init(id: String, floorID: String, label: String, polygon: [Vec2]) {
        self.id = id; self.floorID = floorID; self.label = label; self.polygon = polygon
    }
}

public enum ConnectorKind: String, Codable, Sendable, Hashable { case stairs, ramp, elevator }

public struct FloorConnector: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ConnectorKind
    public var fromSpaceID: String
    public var toSpaceID: String
    public var fromPoint: Vec2
    public var toPoint: Vec2
    public var verification: VerificationState
    public init(id: String, kind: ConnectorKind, fromSpaceID: String, toSpaceID: String, fromPoint: Vec2, toPoint: Vec2,
                verification: VerificationState = .proposed) {
        self.id = id; self.kind = kind; self.fromSpaceID = fromSpaceID; self.toSpaceID = toSpaceID
        self.fromPoint = fromPoint; self.toPoint = toPoint; self.verification = verification
    }
}

public enum AnnotationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case smokeAlarm, coAlarm, fireExtinguisher, exteriorHydrant, utilityShutoffWater, utilityShutoffGas,
         utilityShutoffElectric, supplies, medicalEquipment, tornadoShelterCandidate, outsideMeetingPoint
}

public struct Annotation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: AnnotationKind
    public var floorID: String?
    /// nil for exterior annotations (hydrant, meeting point) that are described rather than placed.
    public var spaceID: String?
    public var position: Vec2?
    public var label: String
    public var verification: VerificationState
    public var note: String?
    /// Explicit link to a privately saved geographic place; its coordinates never become indoor metres.
    public var savedPlaceID: String?
    public init(id: String, kind: AnnotationKind, floorID: String? = nil, spaceID: String? = nil, position: Vec2? = nil,
                label: String, verification: VerificationState = .proposed, note: String? = nil, savedPlaceID: String? = nil) {
        self.savedPlaceID = savedPlaceID
        self.id = id; self.kind = kind; self.floorID = floorID; self.spaceID = spaceID; self.position = position
        self.label = label; self.verification = verification; self.note = note
    }
}

public enum HomeCompleteness: String, Codable, Sendable, Hashable { case complete, incomplete, unknown }

public struct HomeModel: Codable, Sendable, Hashable, Identifiable {
    public static let schemaVersion = 1
    public var id: String
    public var revision: Int
    public var schemaVersion: Int
    public var label: String
    public var source: HomeSource
    public var frame: CoordinateFrame
    public var floors: [Floor]
    public var spaces: [Space]
    public var walls: [WallSegment]
    public var portals: [Portal]
    public var obstacles: [Obstacle]
    public var connectors: [FloorConnector]
    public var annotations: [Annotation]
    public var completeness: HomeCompleteness
    public var completenessNote: String?
    public var isFictional: Bool
    public init(id: String, revision: Int = 1, label: String, source: HomeSource, frame: CoordinateFrame = CoordinateFrame(),
                floors: [Floor], spaces: [Space], walls: [WallSegment] = [], portals: [Portal], obstacles: [Obstacle] = [],
                connectors: [FloorConnector] = [], annotations: [Annotation] = [], completeness: HomeCompleteness = .complete,
                completenessNote: String? = nil, isFictional: Bool = false) {
        self.id = id; self.revision = revision; self.schemaVersion = Self.schemaVersion; self.label = label; self.source = source
        self.frame = frame; self.floors = floors; self.spaces = spaces; self.walls = walls; self.portals = portals
        self.obstacles = obstacles; self.connectors = connectors; self.annotations = annotations
        self.completeness = completeness; self.completenessNote = completenessNote; self.isFictional = isFictional
    }
    public mutating func bumpRevision() { revision += 1 }
    public func space(_ id: String) -> Space? { spaces.first { $0.id == id } }
    public func portal(_ id: String) -> Portal? { portals.first { $0.id == id } }
    public var meetingPoint: Annotation? { annotations.first { $0.kind == .outsideMeetingPoint } }
}

// MARK: - Route contract (Agent B implements `EgressPlanner` in Spatial/)

public struct MobilityProfile: Codable, Sendable, Hashable {
    public var requiresStepFree: Bool
    /// Conservative clearance envelope (metres) for planning, not an accessibility certification.
    public var minimumClearWidthMeters: Double
    public init(requiresStepFree: Bool = false, minimumClearWidthMeters: Double = 0.70) {
        self.requiresStepFree = requiresStepFree; self.minimumClearWidthMeters = minimumClearWidthMeters
    }
    public static let walking = MobilityProfile()
    public static let wheelchair = MobilityProfile(requiresStepFree: true, minimumClearWidthMeters: 0.82)
}

/// Authored exercise exclusions (fire/smoke/blockage). Never inferred from physics.
public struct ScenarioExclusions: Codable, Sendable, Hashable {
    public var blockedSpaceIDs: [String]
    public var blockedPortalIDs: [String]
    public var blockedConnectorIDs: [String]
    public init(blockedSpaceIDs: [String] = [], blockedPortalIDs: [String] = [], blockedConnectorIDs: [String] = []) {
        self.blockedSpaceIDs = blockedSpaceIDs; self.blockedPortalIDs = blockedPortalIDs; self.blockedConnectorIDs = blockedConnectorIDs
    }
    public static let none = ScenarioExclusions()
}

public enum RoutePurpose: String, Codable, Sendable, Hashable { case outdoorEgress, interiorShelter, higherRefuge }

public struct RouteRequest: Codable, Sendable, Hashable {
    public var personID: String?
    public var startSpaceID: String
    public var mobility: MobilityProfile
    public var exclusions: ScenarioExclusions
    /// nil on legacy routes means outdoor egress.
    public var purpose: RoutePurpose?
    public var destinationSpaceID: String?
    public init(personID: String? = nil, startSpaceID: String, mobility: MobilityProfile = .walking, exclusions: ScenarioExclusions = .none, purpose: RoutePurpose = .outdoorEgress, destinationSpaceID: String? = nil) {
        self.purpose = purpose; self.destinationSpaceID = destinationSpaceID
        self.personID = personID; self.startSpaceID = startSpaceID; self.mobility = mobility; self.exclusions = exclusions
    }
}

public enum NoRouteReason: String, Codable, Sendable, Hashable, CaseIterable {
    case noVerifiedExteriorExit
    case incompleteConnectivity
    case incompatibleMobility
    case blockedByScenario
    case missingBuildingPlan
    case invalidGeometry
    case unknownStartSpace
}

public struct RouteExclusion: Codable, Sendable, Hashable {
    public var elementID: String
    public var reason: String
    public init(elementID: String, reason: String) { self.elementID = elementID; self.reason = reason }
}

public struct RoutePath: Codable, Sendable, Hashable {
    /// Points per floor, in floor coordinates. A floor change starts a new leg.
    public struct Leg: Codable, Sendable, Hashable {
        public var floorID: String
        public var points: [Vec2]
        public init(floorID: String, points: [Vec2]) { self.floorID = floorID; self.points = points }
    }
    public var legs: [Leg]
    public var spaceSequence: [String]
    public var portalSequence: [String]
    public var connectorSequence: [String]
    public var exitPortalID: String
    public var lengthMeters: Double
    /// Elements that would need verification before this route can be trusted (e.g. unknown clearance).
    public var verificationNeeded: [String]
    public init(legs: [Leg], spaceSequence: [String], portalSequence: [String], connectorSequence: [String] = [],
                exitPortalID: String, lengthMeters: Double, verificationNeeded: [String] = []) {
        self.legs = legs; self.spaceSequence = spaceSequence; self.portalSequence = portalSequence
        self.connectorSequence = connectorSequence; self.exitPortalID = exitPortalID; self.lengthMeters = lengthMeters
        self.verificationNeeded = verificationNeeded
    }
}

public enum AlternativeStatus: String, Codable, Sendable, Hashable {
    /// Different exterior exit and no shared interior chokepoint.
    case independent
    /// Exists but shares a chokepoint with the primary route.
    case sharesChokepoint
    case none
}

public struct RouteResult: Codable, Sendable, Hashable {
    public static let algorithmVersion = "egress-portal-graph/1"
    public var request: RouteRequest
    public var primary: RoutePath?
    public var alternative: RoutePath?
    public var alternativeStatus: AlternativeStatus
    /// Shared chokepoint element IDs between primary and alternative (if any).
    public var sharedChokepoints: [String]
    public var noRouteReason: NoRouteReason?
    public var exclusions: [RouteExclusion]
    public var homeID: String
    public var homeRevision: Int
    /// Content fingerprint of the home this was computed from (HomeFingerprint.of). nil = unknown → never current.
    public var homeFingerprint: String?
    public var algorithmVersion: String
    public init(request: RouteRequest, primary: RoutePath?, alternative: RoutePath?, alternativeStatus: AlternativeStatus,
                sharedChokepoints: [String] = [], noRouteReason: NoRouteReason?, exclusions: [RouteExclusion],
                homeID: String, homeRevision: Int, homeFingerprint: String? = nil, algorithmVersion: String = RouteResult.algorithmVersion) {
        self.request = request; self.primary = primary; self.alternative = alternative; self.alternativeStatus = alternativeStatus
        self.sharedChokepoints = sharedChokepoints; self.noRouteReason = noRouteReason; self.exclusions = exclusions
        self.homeID = homeID; self.homeRevision = homeRevision; self.homeFingerprint = homeFingerprint; self.algorithmVersion = algorithmVersion
    }
}

/// Implemented by Agent B. Pure, deterministic, Foundation-only.
public protocol EgressPlanning: Sendable {
    func plan(_ request: RouteRequest, in home: HomeModel) -> RouteResult
}
