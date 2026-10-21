import Foundation

/// Transactional household corrections shared by scanned and manual layouts. These edits never confirm a route.
public enum HomeGeometryEditor {
    public enum CorrectionError: Error, Equatable, Sendable {
        case unknownRoom, invalidDimensions, invalidOutline, overlappingRoom
        case unknownConnector, differentFloorsRequired, invalidLanding, unknownPortal
    }

    public static func dimensions(of room: Space) -> Vec2 {
        let b = ManualLayout.bounds(room.polygon)
        return Vec2(b.maxX - b.minX, b.maxY - b.minY)
    }

    /// Labels, dates, markers and retained capture provenance do not invalidate a physical exit check.
    /// Room/obstacle boundaries, opening usability and floor connections do.
    public static func requiresNewEscapeCheck(previous: HomeModel?, updated: HomeModel) -> Bool {
        guard let previous else { return true }
        func geometry(_ source: HomeModel) -> HomeModel {
            var h = source
            h.revision = 0; h.label = ""; h.frame.note = nil; h.originalCapturedWalls = nil
            h.annotations = []; h.completenessNote = nil
            // Recording the dwelling type moves no opening or route; shelter suitability reads it live instead.
            h.dwellingType = nil
            for i in h.floors.indices { h.floors[i].label = ""; h.floors[i].capturedStory = nil }
            for i in h.spaces.indices {
                h.spaces[i].label = ""; h.spaces[i].kind = .other; h.spaces[i].labelConfirmed = true
                h.spaces[i].needsMeasurement = false; h.spaces[i].originalCapturedPolygon = nil
                h.spaces[i].interiorNoWindowsConfirmed = .unknown; h.spaces[i].higherRefugeConfirmed = nil
            }
            for i in h.obstacles.indices { h.obstacles[i].label = "" }
            for i in h.portals.indices {
                h.portals[i].note = nil
                h.portals[i].clearWidthMeters.recordedAt = nil; h.portals[i].clearWidthMeters.verifiedAt = nil
                h.portals[i].operable.recordedAt = nil; h.portals[i].operable.verifiedAt = nil
                h.portals[i].stepFree.recordedAt = nil; h.portals[i].stepFree.verifiedAt = nil
            }
            return h
        }
        return geometry(previous) != geometry(updated)
    }

    /// Changes the outline without guessing where physical openings, landings, obstacles or equipment moved.
    /// Scaling preserves concave outlines; it does not replace a captured polygon with a rectangle.
    public static func correctRoom(in home: inout HomeModel, roomID: String, width: Double, depth: Double,
                                   translation: Vec2 = Vec2(0, 0)) throws {
        guard let index = home.spaces.firstIndex(where: { $0.id == roomID }) else { throw CorrectionError.unknownRoom }
        guard width.isFinite, depth.isFinite, width > 0.3, depth > 0.3,
              translation.x.isFinite, translation.y.isFinite else { throw CorrectionError.invalidDimensions }
        let room = home.spaces[index], size = dimensions(of: room), b = ManualLayout.bounds(room.polygon)
        guard size.x > 0, size.y > 0, Geometry.isSimplePolygon(room.polygon) else { throw CorrectionError.invalidOutline }
        let points = room.polygon.map {
            Vec2(b.minX + ($0.x - b.minX) * width / size.x + translation.x,
                 b.minY + ($0.y - b.minY) * depth / size.y + translation.y)
        }
        if points == room.polygon { return }
        var candidate = home
        candidate.spaces[index].polygon = points
        guard Geometry.isSimplePolygon(points) else { throw CorrectionError.invalidOutline }
        guard !HomeValidator.validate(candidate).contains(where: {
            $0.kind == .overlappingSpaces && $0.elementID.split(separator: "|").contains(Substring(roomID))
        }) else { throw CorrectionError.overlappingRoom }
        if home.source == .roomPlanScan {
            candidate.spaces[index].originalCapturedPolygon = room.originalCapturedPolygon ?? room.polygon
            candidate.originalCapturedWalls = home.originalCapturedWalls ?? home.walls
        }
        candidate.spaces[index].geometryNeedsReview = true
        candidate.spaces[index].usesOutlineWalls = true
        candidate.spaces[index].needsMeasurement = true
        candidate.spaces[index].interiorNoWindowsConfirmed = .unknown
        candidate.spaces[index].higherRefugeConfirmed = nil
        for i in candidate.portals.indices where candidate.portals[i].sideA == .space(roomID) || candidate.portals[i].sideB == .space(roomID) {
            if candidate.portals[i].verification != .rejected { candidate.portals[i].verification = .proposed }
            candidate.portals[i].emergencyEscapeConfirmed = nil
            candidate.portals[i].emergencyEscapePersonIDs = nil
        }
        for i in candidate.connectors.indices where candidate.connectors[i].fromSpaceID == roomID || candidate.connectors[i].toSpaceID == roomID {
            if candidate.connectors[i].verification != .rejected { candidate.connectors[i].verification = .proposed }
        }
        for i in candidate.annotations.indices where candidate.annotations[i].spaceID == roomID {
            if candidate.annotations[i].verification != .rejected { candidate.annotations[i].verification = .proposed }
        }
        // Replace only a boundary segment whose ownership is unambiguous. Internal or shared captured
        // barriers retain their physical coordinates; a correction must never open a path in another room.
        candidate.walls.removeAll { exclusivelyBounds($0, room: room, in: home) }
        candidate.bumpRevision()
        home = candidate
    }

    private static func exclusivelyBounds(_ wall: WallSegment, room: Space, in home: HomeModel) -> Bool {
        guard wall.floorID == room.floorID,
              Geometry.edges(room.polygon).contains(where: {
                  Geometry.distancePointSegment(wall.a, $0.0, $0.1) <= 0.01 &&
                  Geometry.distancePointSegment(wall.b, $0.0, $0.1) <= 0.01
              }) else { return false }
        // An entire captured segment can extend past one room or serve another one. Keep it if uncertain.
        return !home.spaces.contains { other in
            other.id != room.id && other.floorID == room.floorID &&
                Geometry.distanceSegmentPolygon(wall.a, wall.b, other.polygon) <= 0.01
        }
    }

    /// Removes the inventory item and its records. Independently captured/shared barriers are retained.
    public static func removeRoom(in home: inout HomeModel, roomID: String) throws {
        guard let room = home.space(roomID) else { throw CorrectionError.unknownRoom }
        let removedWallIDs = Set(home.walls.filter { exclusivelyBounds($0, room: room, in: home) }.map(\.id))
        home.edit { h in
            h.spaces.removeAll { $0.id == roomID }
            h.walls.removeAll { removedWallIDs.contains($0.id) }
            h.portals.removeAll { $0.sideA == .space(roomID) || $0.sideB == .space(roomID) }
            h.annotations.removeAll { $0.spaceID == roomID }
            h.connectors.removeAll { $0.fromSpaceID == roomID || $0.toSpaceID == roomID }
            h.completeness = .incomplete
        }
    }

    /// A separate explicit physical review, after the proposed outline has been checked in the real home.
    /// Connections still need their own confirmations; reviewing an outline cannot verify a door or stairs.
    public static func reviewRoom(in home: inout HomeModel, roomID: String) throws {
        guard let index = home.spaces.firstIndex(where: { $0.id == roomID }) else { throw CorrectionError.unknownRoom }
        guard Geometry.isSimplePolygon(home.spaces[index].polygon) else { throw CorrectionError.invalidOutline }
        guard !HomeValidator.validate(home).contains(where: {
            $0.kind == .overlappingSpaces && $0.elementID.split(separator: "|").contains(Substring(roomID))
        }) else { throw CorrectionError.overlappingRoom }
        guard home.spaces[index].geometryNeedsReview == true else { return }
        home.edit { $0.spaces[index].geometryNeedsReview = false }
    }

    public static func validLandings(_ connector: FloorConnector, in home: HomeModel) -> Bool {
        guard let from = home.space(connector.fromSpaceID), let to = home.space(connector.toSpaceID),
              from.floorID != to.floorID, home.floors.contains(where: { $0.id == from.floorID }),
              home.floors.contains(where: { $0.id == to.floorID }),
              connector.fromPoint.x.isFinite, connector.fromPoint.y.isFinite,
              connector.toPoint.x.isFinite, connector.toPoint.y.isFinite else { return false }
        return Geometry.isSimplePolygon(from.polygon) && Geometry.isSimplePolygon(to.polygon)
            && Geometry.contains(from.polygon, connector.fromPoint) && Geometry.contains(to.polygon, connector.toPoint)
    }

    @discardableResult
    public static func addStairs(in home: inout HomeModel, fromRoomID: String, fromPoint: Vec2,
                                 toRoomID: String, toPoint: Vec2) throws -> FloorConnector {
        guard let from = home.space(fromRoomID), let to = home.space(toRoomID) else { throw CorrectionError.unknownRoom }
        guard from.floorID != to.floorID else { throw CorrectionError.differentFloorsRequired }
        var n = home.connectors.count + 1
        while home.connectors.contains(where: { $0.id == "cn-manual-\(n)" }) { n += 1 }
        let stairs = FloorConnector(id: "cn-manual-\(n)", kind: .stairs, fromSpaceID: fromRoomID, toSpaceID: toRoomID,
                                    fromPoint: fromPoint, toPoint: toPoint, verification: .proposed)
        guard validLandings(stairs, in: home) else { throw CorrectionError.invalidLanding }
        home.edit { $0.connectors.append(stairs) }
        return stairs
    }

    /// Both actual endpoint locations are supplied, in each room's floor coordinates. No vertical-overlap guess.
    public static func correctLandings(in home: inout HomeModel, connectorID: String,
                                      fromRoomID: String, fromPoint: Vec2, toRoomID: String, toPoint: Vec2) throws {
        guard let index = home.connectors.firstIndex(where: { $0.id == connectorID }) else { throw CorrectionError.unknownConnector }
        guard let from = home.space(fromRoomID), let to = home.space(toRoomID) else { throw CorrectionError.unknownRoom }
        guard from.floorID != to.floorID else { throw CorrectionError.differentFloorsRequired }
        var corrected = home.connectors[index]
        corrected.fromSpaceID = fromRoomID; corrected.toSpaceID = toRoomID
        corrected.fromPoint = fromPoint; corrected.toPoint = toPoint; corrected.verification = .proposed
        guard validLandings(corrected, in: home) else { throw CorrectionError.invalidLanding }
        home.edit { $0.connectors[index] = corrected }
    }

    /// Corrects classification without changing captured endpoints or stable identity. A change of
    /// opening type invalidates prior escape suitability: a window cannot inherit a door's exit check.
    public static func reclassifyOpening(in home: inout HomeModel, portalID: String, kind: PortalKind) throws {
        guard let index = home.portals.firstIndex(where: { $0.id == portalID }) else { throw CorrectionError.unknownPortal }
        guard home.portals[index].kind != kind else { return }
        let previousKind = home.portals[index].kind
        home.edit {
            $0.portals[index].kind = kind
            $0.portals[index].emergencyEscapeConfirmed = nil
            $0.portals[index].emergencyEscapePersonIDs = nil
            // An open doorway has no operable leaf. Reclassifying it must not manufacture
            // confirmation that a newly classified door/window can actually be opened.
            if previousKind == .opening || kind == .opening {
                $0.portals[index].operable = .unknown
            }
        }
    }

    /// Repositions an existing opening on an explicitly selected real wall. Clear width/operability are retained;
    /// the new connection is proposed until reviewed. Failure leaves the original home and evidence untouched.
    public static func placeOpening(in home: inout HomeModel, portalID: String, from roomID: String,
                                    to destination: PortalDestination, exteriorSide: ManualLayout.Side? = nil) throws {
        guard let index = home.portals.firstIndex(where: { $0.id == portalID }) else { throw CorrectionError.unknownPortal }
        let original = home.portals[index]
        let width = original.a.distance(to: original.b)
        guard width.isFinite, width > 0 else { throw CorrectionError.invalidDimensions }
        if destination == .space(roomID) { throw CorrectionError.invalidLanding }
        var proposed = home
        let placement = try ManualLayout.addPortal(to: &proposed, kind: original.kind, from: roomID,
            to: destination, exteriorSide: exteriorSide, width: width)
        home.edit {
            $0.portals[index].floorID = placement.floorID
            $0.portals[index].a = placement.a; $0.portals[index].b = placement.b
            $0.portals[index].sideA = placement.sideA; $0.portals[index].sideB = placement.sideB
            $0.portals[index].verification = .proposed
            $0.portals[index].emergencyEscapeConfirmed = nil
            $0.portals[index].emergencyEscapePersonIDs = nil
        }
    }
}
