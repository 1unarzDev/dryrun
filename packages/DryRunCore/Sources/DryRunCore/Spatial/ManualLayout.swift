import Foundation

/// Manual home building: rectangular rooms attached to each other, doors on real shared walls.
/// Manual geometry is labelled `.manual` and never presented as scan output.
public enum ManualLayout {
    public enum Side: String, Codable, Sendable, CaseIterable { case north, east, south, west }

    public enum LayoutError: Error, Equatable, Sendable {
        case unknownSpace(String)
        case invalidSize
        case overlapsExistingRoom(String)
        case noSharedWall
        case sideNotExterior
        case wallTooShort(available: Double)
    }

    /// A manual draft without invented rooms, openings or exterior-grade facts. Adding the first room is an
    /// explicit household edit; saving a draft does not make it a reviewed layout.
    public static func emptyHome(id: String) -> HomeModel {
        HomeModel(id: id, label: "My home", source: .manual,
                  frame: CoordinateFrame(note: "Manual layout entered by the household; dimensions are estimates until measured."),
                  floors: [Floor(id: "fl-1", level: 0, label: "Level 1", exteriorGrade: .unknown)],
                  spaces: [], portals: [], completeness: .incomplete,
                  completenessNote: "Add the rooms and confirm the floor's relationship to the ground before reviewing routes.")
    }

    /// Explicitly creates the first room from household-entered dimensions. Exterior grade remains unknown.
    @discardableResult
    public static func addFirstRoom(to home: inout HomeModel, label: String, kind: SpaceKind,
                                    width: Double, depth: Double, floorID: String? = nil) throws -> Space {
        guard width.isFinite, depth.isFinite, width > 0.3, depth > 0.3 else { throw LayoutError.invalidSize }
        guard let floor = home.floors.first(where: { floorID == nil || $0.id == floorID }),
              !home.spaces.contains(where: { $0.floorID == floor.id }) else { throw LayoutError.unknownSpace("first-room") }
        var n = home.spaces.count + 1
        while home.spaces.contains(where: { $0.id == "sp-\(n)" }) { n += 1 }
        var space = Space(id: "sp-\(n)", floorID: floor.id, label: label, kind: kind,
                          polygon: SampleHomes.rect(0, 0, width, depth), labelConfirmed: true, needsMeasurement: true)
        space.usesOutlineWalls = true
        home.edit { $0.spaces.append(space) }
        return space
    }

    /// User-entered level order and elevation, never inferred from capture order or an overlapping room.
    @discardableResult
    public static func addFloor(to home: inout HomeModel, label: String, level: Int, elevationMeters: Double) throws -> Floor {
        guard elevationMeters.isFinite else { throw LayoutError.invalidSize }
        var n = home.floors.count + 1
        while home.floors.contains(where: { $0.id == "fl-\(n)" }) { n += 1 }
        let floor = Floor(id: "fl-\(n)", level: level, label: label, elevationMeters: elevationMeters, exteriorGrade: .unknown)
        home.edit { $0.floors.append(floor) }
        return floor
    }

    /// Legacy convenience for callers that explicitly want a provisional starting room.
    public static func newHome(id: String, firstRoomLabel: String = "Living room", width: Double = 5, depth: Double = 4) -> HomeModel {
        HomeModel(id: id, label: "My home", source: .manual,
                  frame: CoordinateFrame(note: "Manual layout entered by the household; dimensions are estimates until measured."),
                  floors: [Floor(id: "fl-ground", level: 0, label: "Ground floor")],
                  spaces: [Space(id: "sp-1", floorID: "fl-ground", label: firstRoomLabel, kind: .livingRoom,
                                 polygon: SampleHomes.rect(0, 0, width, depth), labelConfirmed: true, needsMeasurement: true)],
                  portals: [], completeness: .unknown,
                  completenessNote: "Add every room people sleep in or pass through to get out.")
    }

    static func bounds(_ poly: [Vec2]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (poly.map(\.x).min() ?? 0, poly.map(\.y).min() ?? 0, poly.map(\.x).max() ?? 0, poly.map(\.y).max() ?? 0)
    }

    /// Adds a rectangular room sharing the `side` wall of `anchorID`, aligned to the anchor's west/south corner.
    @discardableResult
    public static func addRoom(to home: inout HomeModel, label: String, kind: SpaceKind, width: Double, depth: Double,
                               attachedTo anchorID: String, side: Side, offset: Double = 0) throws -> Space {
        guard width.isFinite, depth.isFinite, offset.isFinite, width > 0.3, depth > 0.3 else { throw LayoutError.invalidSize }
        guard let anchor = home.space(anchorID) else { throw LayoutError.unknownSpace(anchorID) }
        let b = bounds(anchor.polygon)
        let poly: [Vec2]
        switch side {
        case .north: poly = SampleHomes.rect(b.minX + offset, b.maxY, b.minX + offset + width, b.maxY + depth)
        case .south: poly = SampleHomes.rect(b.minX + offset, b.minY - depth, b.minX + offset + width, b.minY)
        case .east: poly = SampleHomes.rect(b.maxX, b.minY + offset, b.maxX + width, b.minY + offset + depth)
        case .west: poly = SampleHomes.rect(b.minX - width, b.minY + offset, b.minX, b.minY + offset + depth)
        }
        for s in home.spaces where s.floorID == anchor.floorID {
            let c = Geometry.centroid(poly)
            if Geometry.contains(s.polygon, c) || poly.contains(where: { Geometry.contains(s.polygon, $0) })
                || s.polygon.contains(where: { Geometry.contains(poly, $0) }) {
                throw LayoutError.overlapsExistingRoom(s.id)
            }
        }
        var n = home.spaces.count + 1
        while home.spaces.contains(where: { $0.id == "sp-\(n)" }) { n += 1 }
        var space = Space(id: "sp-\(n)", floorID: anchor.floorID, label: label, kind: kind, polygon: poly,
                          labelConfirmed: true, needsMeasurement: true)
        space.usesOutlineWalls = true
        home.edit { $0.spaces.append(space) }
        return space
    }

    /// The overlapping, collinear part of two spaces' boundaries (within `boundaryContactMeters`). Nil if they
    /// only near-touch: no shared wall means no door.
    public static func sharedWall(_ a: Space, _ b: Space, tolerance: GeometryTolerance = .standard) -> (Vec2, Vec2)? {
        guard a.floorID == b.floorID else { return nil }
        var best: (Vec2, Vec2)?
        for (p1, p2) in Geometry.edges(a.polygon) {
            let d = Geometry.normalized(p2 - p1)
            let len = p1.distance(to: p2)
            for (q1, q2) in Geometry.edges(b.polygon) {
                // Both endpoints of q within tolerance of the infinite line through p.
                let n = Vec2(-d.y, d.x)
                guard abs(Geometry.dot(q1 - p1, n)) <= tolerance.boundaryContactMeters,
                      abs(Geometry.dot(q2 - p1, n)) <= tolerance.boundaryContactMeters else { continue }
                let t1 = Geometry.dot(q1 - p1, d), t2 = Geometry.dot(q2 - p1, d)
                let lo = max(0, min(t1, t2)), hi = min(len, max(t1, t2))
                if hi - lo > tolerance.boundaryContactMeters, (best.map { $0.0.distance(to: $0.1) } ?? 0) < hi - lo {
                    best = (p1 + d * lo, p1 + d * hi)
                }
            }
        }
        return best
    }

    /// The `side` edge of a rectangular-ish space, if no other space on the floor shares it.
    public static func exteriorWall(of space: Space, side: Side, in home: HomeModel) -> (Vec2, Vec2)? {
        let b = bounds(space.polygon)
        // Use an actual outline segment on the chosen extreme, never a bounding-box edge spanning a
        // concave notch. Rotated/irregular outlines without this wall need a different recorded connection.
        let candidates = Geometry.edges(space.polygon).filter { edge in
            switch side {
            case .north: abs(edge.0.y - b.maxY) < 0.01 && abs(edge.1.y - b.maxY) < 0.01
            case .south: abs(edge.0.y - b.minY) < 0.01 && abs(edge.1.y - b.minY) < 0.01
            case .east: abs(edge.0.x - b.maxX) < 0.01 && abs(edge.1.x - b.maxX) < 0.01
            case .west: abs(edge.0.x - b.minX) < 0.01 && abs(edge.1.x - b.minX) < 0.01
            }
        }.sorted { $0.0.distance(to: $0.1) > $1.0.distance(to: $1.1) }
        return candidates.first { edge in
            !home.spaces.contains { other in
                other.id != space.id && other.floorID == space.floorID &&
                sharedWall(space, other).map { Geometry.collinearOverlap($0.0, $0.1, edge.0, edge.1, epsilon: 0.01) } == true
            }
        }
    }

    /// Adds a door/opening centred on the shared wall (or exterior side). New doors start `.proposed` unless
    /// the household marks them verified.
    @discardableResult
    public static func addPortal(to home: inout HomeModel, kind: PortalKind = .door, from spaceID: String,
                                 to destination: PortalDestination, exteriorSide: Side? = nil, width: Double = 0.8,
                                 widthMeasured: Bool = false, verified: Bool = false, operable: Bool? = nil,
                                 stepFree: Bool? = nil) throws -> Portal {
        guard let a = home.space(spaceID) else { throw LayoutError.unknownSpace(spaceID) }
        let wall: (Vec2, Vec2)
        switch destination {
        case .space(let otherID):
            guard let b = home.space(otherID) else { throw LayoutError.unknownSpace(otherID) }
            guard let w = sharedWall(a, b) else { throw LayoutError.noSharedWall }
            wall = w
        case .exterior, .commonArea, .unknown:
            guard let side = exteriorSide, let w = exteriorWall(of: a, side: side, in: home) else { throw LayoutError.sideNotExterior }
            wall = w
        }
        let len = wall.0.distance(to: wall.1)
        guard len >= width + 0.1 else { throw LayoutError.wallTooShort(available: len) }
        let d = Geometry.normalized(wall.1 - wall.0)
        let mid = Vec2((wall.0.x + wall.1.x) / 2, (wall.0.y + wall.1.y) / 2)
        var n = home.portals.count + 1
        while home.portals.contains(where: { $0.id == "pt-\(n)" }) { n += 1 }
        let portal = Portal(id: "pt-\(n)", floorID: a.floorID, kind: kind, a: mid - d * (width / 2), b: mid + d * (width / 2),
                            sideA: .space(spaceID), sideB: destination,
                            clearWidthMeters: widthMeasured ? .confirmed(width, unit: "m") : .unknown,
                            operable: operable.map { .confirmed($0) } ?? .unknown,
                            stepFree: stepFree.map { .confirmed($0) } ?? .unknown,
                            verification: verified ? .verified : .proposed)
        guard PortalAttachment.check(portal, in: home).attached else { throw LayoutError.noSharedWall }
        home.edit { $0.portals.append(portal) }
        return portal
    }

    /// Dynamic outlines are never cached into captured walls; later edits cannot leave stale derived segments.
    public static func derivedWalls(_ home: HomeModel) -> [WallSegment] {
        var out = home.walls
        for s in home.spaces where home.walls.isEmpty || s.usesOutlineWalls == true {
            for (i, e) in Geometry.edges(s.polygon).enumerated() {
                if out.contains(where: { $0.floorID == s.floorID && Geometry.collinearOverlap($0.a, $0.b, e.0, e.1, epsilon: 0.01)
                    && abs($0.a.distance(to: $0.b) - e.0.distance(to: e.1)) < 0.01 }) { continue }
                out.append(WallSegment(id: "dw-\(s.id)-\(i)", floorID: s.floorID, a: e.0, b: e.1))
            }
        }
        return out
    }
}
