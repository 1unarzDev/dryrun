import Foundation

// Plain, Foundation-only mirror of the RoomPlan data Dry Run uses. The iOS adapter
// (apps/ios/DryRun/Spatial/RoomPlanMapping.swift) converts CapturedRoom/CapturedStructure into these.
// Nothing here is proof of exit safety, centimetre accuracy, operability, or code compliance.

public enum ScanConfidence: String, Codable, Sendable, Hashable { case low, medium, high }

public enum ScanSurfaceCategory: String, Codable, Sendable, Hashable {
    case wall, doorOpen, doorClosed, window, opening, floor
}

public struct ScanSurface: Codable, Sendable, Hashable {
    public var id: String
    public var category: ScanSurfaceCategory
    /// Surface-local -> scan world, column-major. RoomPlan: +y up, right-handed, metres.
    public var transform: RigidTransform3D
    /// width (local x), height (local y), depth (local z), metres.
    public var dimensions: Vec3
    /// Optional outline corners in the surface's local frame (floors).
    public var polygonCorners: [Vec3]
    public var confidence: ScanConfidence
    public var parentID: String?
    public init(id: String, category: ScanSurfaceCategory, transform: RigidTransform3D, dimensions: Vec3,
                polygonCorners: [Vec3] = [], confidence: ScanConfidence, parentID: String? = nil) {
        self.id = id; self.category = category; self.transform = transform; self.dimensions = dimensions
        self.polygonCorners = polygonCorners; self.confidence = confidence; self.parentID = parentID
    }
}

public struct ScanObject: Codable, Sendable, Hashable {
    public var id: String
    /// RoomPlan object category name, e.g. "stairs", "sofa", "bed", "table", "storage", "refrigerator".
    public var category: String
    public var transform: RigidTransform3D
    public var dimensions: Vec3
    public var confidence: ScanConfidence
    public init(id: String, category: String, transform: RigidTransform3D, dimensions: Vec3, confidence: ScanConfidence) {
        self.id = id; self.category = category; self.transform = transform; self.dimensions = dimensions; self.confidence = confidence
    }
}

public struct ScanRoom: Codable, Sendable, Hashable {
    public var id: String
    public var story: Int
    public var surfaces: [ScanSurface]
    public var objects: [ScanObject]
    public init(id: String, story: Int = 0, surfaces: [ScanSurface], objects: [ScanObject] = []) {
        self.id = id; self.story = story; self.surfaces = surfaces; self.objects = objects
    }
}

public struct ScanCapture: Codable, Sendable, Hashable {
    public var rooms: [ScanRoom]
    /// True when every room was captured in ONE shared coordinate frame (single session / shared ARSession /
    /// StructureBuilder output). Independently scanned rooms are never placed by guessing.
    public var sharedCoordinateFrame: Bool
    /// True when the capture session ended normally.
    public var sessionCompleted: Bool
    public init(rooms: [ScanRoom], sharedCoordinateFrame: Bool, sessionCompleted: Bool = true) {
        self.rooms = rooms; self.sharedCoordinateFrame = sharedCoordinateFrame; self.sessionCompleted = sessionCompleted
    }
}

public enum ScanImportError: Error, Equatable, Sendable {
    case empty
    /// Multiple rooms without a shared frame: we refuse to position them relative to each other.
    case unsharedCoordinateFrames(roomCount: Int)
}

public struct ScanImportResult: Sendable, Hashable {
    public var home: HomeModel
    public var notes: [String]
}

public enum ScanImport {
    /// Apple's published MultiRoom recommendation (~2,000 sq ft, single floor). Not a reliability guarantee.
    public static let recommendedMaxAreaSquareMeters = 185.8

    /// Build a PROPOSED home: every portal `.proposed`, operability unknown, windows never exits, exterior sides
    /// never assumed, connectors require confirmation. Rotation/translation are applied exactly; nothing is snapped.
    public static func importCapture(_ capture: ScanCapture, homeID: String, label: String = "Scanned home",
                                     tolerance: GeometryTolerance = .standard) throws -> ScanImportResult {
        guard !capture.rooms.isEmpty else { throw ScanImportError.empty }
        if capture.rooms.count > 1 && !capture.sharedCoordinateFrame {
            throw ScanImportError.unsharedCoordinateFrames(roomCount: capture.rooms.count)
        }
        var notes: [String] = []
        var incomplete = !capture.sessionCompleted
        if !capture.sessionCompleted { notes.append("Scan session did not finish; parts of the home may be missing.") }

        // Floors by story.
        let stories = Set(capture.rooms.map(\.story)).sorted()
        var floorElev: [Int: Double] = [:]
        for r in capture.rooms {
            for s in r.surfaces where s.category == .floor {
                let y = s.transform.translation.y
                floorElev[r.story] = min(floorElev[r.story] ?? y, y)
            }
        }
        let base = floorElev[stories.first!] ?? 0
        let floors = stories.map { st in
            Floor(id: "fl-\(st)", level: st - stories.first!, label: st == stories.first! ? "Scanned floor" : "Scanned floor \(st - stories.first! + 1)",
                  elevationMeters: (floorElev[st] ?? base) - base)
        }

        var spaces: [Space] = []
        var walls: [WallSegment] = []
        var obstacles: [Obstacle] = []
        var rawPortals: [(surface: ScanSurface, floorID: String, a: Vec2, b: Vec2)] = []
        var stairsObjects: [(ScanObject, String)] = []

        for (ri, room) in capture.rooms.enumerated() {
            let fid = "fl-\(room.story)"
            let spaceID = "sp-scan-\(ri + 1)"
            // Room outline: the floor surface polygon, transformed and projected.
            var outline: [Vec2] = []
            var hullFallback = false
            if let floor = room.surfaces.first(where: { $0.category == .floor }), floor.polygonCorners.count >= 3 {
                outline = floor.polygonCorners.map { RigidTransform3D.projectToFloor(floor.transform.apply($0)) }
            } else {
                let pts = room.surfaces.filter { $0.category == .wall }.flatMap { endpoints($0) }
                outline = convexHull(pts)
                hullFallback = true
                incomplete = true
                notes.append("Room \(ri + 1): no floor outline; using the outline of its walls. Needs measurement.")
            }
            if Geometry.signedArea(outline) < 0 { outline.reverse() }
            let lowConfidence = room.surfaces.contains { $0.confidence == .low }
            spaces.append(Space(id: spaceID, floorID: fid, label: "Room \(ri + 1)", kind: .other, polygon: outline,
                                labelConfirmed: false, needsMeasurement: hullFallback || lowConfidence || outline.count < 3))
            for w in room.surfaces where w.category == .wall {
                let e = endpoints(w)
                walls.append(WallSegment(id: "w-\(w.id)", floorID: fid, a: e[0], b: e[1], thicknessMeters: max(0.05, w.dimensions.z)))
            }
            for p in room.surfaces where [.doorOpen, .doorClosed, .window, .opening].contains(p.category) {
                let e = endpoints(p)
                rawPortals.append((p, fid, e[0], e[1]))
            }
            for o in room.objects {
                if o.category == "stairs" { stairsObjects.append((o, fid)); continue }
                obstacles.append(Obstacle(id: "ob-\(o.id)", floorID: fid, label: o.category, polygon: footprint(o)))
            }
        }

        // De-duplicate portals reported by both adjoining rooms, deterministically (first by input order wins).
        var portals: [Portal] = []
        var kept: [(Vec2, String, ScanSurfaceCategory)] = []
        for rp in rawPortals {
            let c = Vec2((rp.a.x + rp.b.x) / 2, (rp.a.y + rp.b.y) / 2)
            if kept.contains(where: { $0.1 == rp.floorID && $0.2 == rp.surface.category && $0.0.distance(to: c) < tolerance.scanDuplicatePortalMeters }) { continue }
            kept.append((c, rp.floorID, rp.surface.category))
            // Proposed adjacency: spaces on this floor whose boundary passes near the opening. Never verified here.
            let near = spaces.filter { $0.floorID == rp.floorID && Geometry.distanceToBoundary($0.polygon, c) <= tolerance.scanPortalAttachMeters }
                .map(\.id).sorted()
            let kind: PortalKind
            switch rp.surface.category {
            case .window: kind = .window
            case .opening: kind = .opening
            default: kind = .door
            }
            let sideA: PortalDestination = near.count >= 1 ? .space(near[0]) : .unknown
            let sideB: PortalDestination = (kind != .window && near.count >= 2) ? .space(near[1]) : .unknown
            if near.count > 2 { notes.append("Opening \(rp.surface.id) is near more than two rooms; confirm where it leads.") }
            portals.append(Portal(id: "pt-\(rp.surface.id)", floorID: rp.floorID, kind: kind, a: rp.a, b: rp.b, sideA: sideA, sideB: sideB,
                                  clearWidthMeters: .scanned(rp.surface.dimensions.x, unit: "m"), operable: .unknown, stepFree: .unknown,
                                  verification: .proposed,
                                  note: kind == .window ? "Scanned window: not an exit" : "Scanned; confirm where this leads"))
            if case .unknown = sideB { incomplete = true }
        }

        // Stairs: a connector is only proposed when the other story's space containing the stairs is known.
        var connectors: [FloorConnector] = []
        for (o, fid) in stairsObjects {
            let c = RigidTransform3D.projectToFloor(o.transform.translation)
            let here = spaces.first { $0.floorID == fid && Geometry.contains($0.polygon, c) }
            let other = spaces.first { $0.floorID != fid && Geometry.contains($0.polygon, c) }
            if let here, let other {
                connectors.append(FloorConnector(id: "cn-\(o.id)", kind: .stairs, fromSpaceID: here.id, toSpaceID: other.id,
                                                 fromPoint: c, toPoint: c, verification: .proposed))
            } else {
                incomplete = true
                notes.append("Stairs detected; the floor they connect to was not captured. Confirm the connection before routes can use it.")
            }
        }

        let area = spaces.reduce(0) { $0 + abs(Geometry.signedArea($1.polygon)) }
        if area > recommendedMaxAreaSquareMeters {
            incomplete = true
            notes.append("Scanned area exceeds Apple's published multiroom recommendation; check for missing or misplaced rooms.")
        }
        notes.append("Scanned doors and openings are proposals. Confirm each connection and choose your exterior exits.")

        let home = HomeModel(id: homeID, revision: 1, label: label, source: .roomPlanScan,
                             frame: CoordinateFrame(units: "meters", handedness: "right", sourceUpAxis: "y",
                                                    note: "Projected from RoomPlan world (x, y-up, z) to floor plane (x, -z)."),
                             floors: floors, spaces: spaces, walls: walls, portals: portals, obstacles: obstacles,
                             connectors: connectors, annotations: [], completeness: incomplete ? .incomplete : .unknown,
                             completenessNote: incomplete ? "Scan is incomplete or has unconfirmed openings." : "Confirm the scan covers the whole home.",
                             isFictional: false)
        return ScanImportResult(home: home, notes: notes)
    }

    /// Wall/door/window endpoints along the surface's local x-axis, projected to the floor plane.
    static func endpoints(_ s: ScanSurface) -> [Vec2] {
        let h = s.dimensions.x / 2
        return [RigidTransform3D.projectToFloor(s.transform.apply(Vec3(-h, 0, 0))),
                RigidTransform3D.projectToFloor(s.transform.apply(Vec3(h, 0, 0)))]
    }

    static func footprint(_ o: ScanObject) -> [Vec2] {
        let hx = o.dimensions.x / 2, hz = o.dimensions.z / 2
        let pts = [Vec3(-hx, 0, -hz), Vec3(hx, 0, -hz), Vec3(hx, 0, hz), Vec3(-hx, 0, hz)].map { RigidTransform3D.projectToFloor(o.transform.apply($0)) }
        return Geometry.signedArea(pts) < 0 ? pts.reversed() : pts
    }

    /// Andrew's monotone chain; deterministic.
    static func convexHull(_ pts: [Vec2]) -> [Vec2] {
        let p = pts.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard p.count >= 3 else { return p }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in p {
            while lower.count >= 2 && Geometry.cross(lower[lower.count - 1] - lower[lower.count - 2], q - lower[lower.count - 2]) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2 && Geometry.cross(upper[upper.count - 1] - upper[upper.count - 2], q - upper[upper.count - 2]) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
