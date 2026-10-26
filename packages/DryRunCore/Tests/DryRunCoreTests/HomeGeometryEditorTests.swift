import Foundation
import Testing
@testable import DryRunCore

@Suite("Household geometry corrections")
struct HomeGeometryEditorTests {
    private func home() throws -> HomeModel {
        var h = ManualLayout.newHome(id: "correction-home", width: 4, depth: 4)
        _ = try ManualLayout.addPortal(to: &h, from: "sp-1", to: .exterior, exteriorSide: .south,
            width: 0.9, widthMeasured: true, verified: true, operable: true, stepFree: true)
        return h
    }

    @Test func outlineCorrectionRetainsCaptureAndRequiresReviewSeparateFromConnections() throws {
        var h = try home()
        h.source = .roomPlanScan; h.floors[0].exteriorGrade = .ground
        h.walls = ManualLayout.derivedWalls(h)
        h.spaces[0].interiorNoWindowsConfirmed = .confirmed(true)
        h.spaces[0].higherRefugeConfirmed = .confirmed(true)
        let original = h, request = RouteRequest(startSpaceID: "sp-1")
        #expect(EgressPlanner().plan(request, in: h).primary != nil)
        try HomeGeometryEditor.correctRoom(in: &h, roomID: "sp-1", width: 5, depth: 4)
        #expect(h.id == original.id && h.revision == original.revision + 1)
        #expect(h.spaces[0].originalCapturedPolygon == original.spaces[0].polygon)
        #expect(h.originalCapturedWalls == original.walls)
        #expect(h.spaces[0].geometryNeedsReview == true)
        #expect(h.spaces[0].interiorNoWindowsConfirmed.confirmedValue == nil)
        #expect(h.spaces[0].higherRefugeConfirmed == nil)
        #expect(h.portals[0].verification == .proposed)
        #expect(h.portals[0].clearWidthMeters == original.portals[0].clearWidthMeters)
        #expect(h.portals[0].a == original.portals[0].a && h.portals[0].b == original.portals[0].b)
        #expect(ManualLayout.derivedWalls(h).contains { $0.a.x == 5 || $0.b.x == 5 })
        #expect(EgressPlanner().plan(request, in: h).primary == nil)
        // Even reconfirming an opening cannot bypass the corrected-outline review.
        h.portals[0].verification = .verified
        #expect(EgressPlanner().plan(request, in: h).noRouteReason == .invalidGeometry)
        try HomeGeometryEditor.reviewRoom(in: &h, roomID: "sp-1")
        #expect(EgressPlanner().plan(request, in: h).primary != nil)
        try HomeGeometryEditor.correctRoom(in: &h, roomID: "sp-1", width: 6, depth: 4)
        #expect(h.spaces[0].originalCapturedPolygon == original.spaces[0].polygon)
        #expect(h.originalCapturedWalls == original.walls)
        let decoded = try DryRunJSON.decoder().decode(HomeModel.self, from: DryRunJSON.encoder().encode(h))
        #expect(decoded == h)
    }

    @Test func rejectedEditsAreTransactionalAndConcaveOutlineIsPreserved() throws {
        var h = try home()
        let room = try ManualLayout.addRoom(to: &h, label: "Neighbor", kind: .other, width: 3, depth: 4,
            attachedTo: "sp-1", side: .east)
        let original = h
        #expect(throws: HomeGeometryEditor.CorrectionError.overlappingRoom) {
            try HomeGeometryEditor.correctRoom(in: &h, roomID: "sp-1", width: 5, depth: 4)
        }
        #expect(h == original)
        #expect(throws: HomeGeometryEditor.CorrectionError.invalidDimensions) {
            try HomeGeometryEditor.correctRoom(in: &h, roomID: room.id, width: .infinity, depth: 4)
        }
        #expect(h == original)
        var concave = h
        concave.spaces = [Space(id: "l", floorID: h.floors[0].id, label: "L", kind: .other,
            polygon: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 1), Vec2(1, 1), Vec2(1, 4), Vec2(0, 4)])]
        concave.portals = []
        try HomeGeometryEditor.correctRoom(in: &concave, roomID: "l", width: 8, depth: 4)
        #expect(concave.spaces[0].polygon.count == 6)
        #expect(!Geometry.contains(concave.spaces[0].polygon, Vec2(5, 3)))
        #expect(abs(Geometry.signedArea(concave.spaces[0].polygon) - 14) < 0.0001)
    }

    @Test func landingCorrectionCannotConfirmOrTeleportAndMobilityStillExcludesStairs() throws {
        var h = try home()
        let floor = Floor(id: "upper", level: 1, label: "Upper", elevationMeters: 3, exteriorGrade: .aboveGround)
        h.floors.append(floor)
        h.spaces.append(Space(id: "up", floorID: floor.id, label: "Up", kind: .bedroom,
            polygon: SampleHomes.rect(8, 0, 12, 4)))
        h.connectors.append(FloorConnector(id: "stairs", kind: .stairs, fromSpaceID: "sp-1", toSpaceID: "up",
            fromPoint: Vec2(1, 1), toPoint: Vec2(1, 1)))
        let original = h
        #expect(HomeConfirmation.apply(.confirmConnector(connectorID: "stairs", usable: true), to: h) == h)
        #expect(HomeValidator.validate(h).contains { $0.kind == .connectorGeometryInvalid })
        #expect(throws: HomeGeometryEditor.CorrectionError.invalidLanding) {
            try HomeGeometryEditor.correctLandings(in: &h, connectorID: "stairs", fromRoomID: "sp-1",
                fromPoint: Vec2(1, 1), toRoomID: "up", toPoint: Vec2(1, 1))
        }
        #expect(h == original)
        try HomeGeometryEditor.correctLandings(in: &h, connectorID: "stairs", fromRoomID: "sp-1",
            fromPoint: Vec2(1, 1), toRoomID: "up", toPoint: Vec2(9, 1))
        #expect(h.connectors[0].verification == .proposed)
        let request = RouteRequest(startSpaceID: "up")
        #expect(EgressPlanner().plan(request, in: h).primary == nil)
        h = HomeConfirmation.apply(.confirmConnector(connectorID: "stairs", usable: true), to: h)
        let route = try #require(EgressPlanner().plan(request, in: h).primary)
        #expect(route.connectorSequence == ["stairs"])
        #expect(RouteGeometryAudit.violations(route, in: h).isEmpty)
        var mobility = request; mobility.mobility = .wheelchair
        #expect(EgressPlanner().plan(mobility, in: h).primary == nil)
    }

    @Test func placingOpeningPreservesEvidenceButRequiresARealWallAndReview() throws {
        var h = try home()
        let original = h
        try HomeGeometryEditor.placeOpening(in: &h, portalID: h.portals[0].id, from: "sp-1",
            to: .exterior, exteriorSide: .east)
        #expect(h.portals[0].clearWidthMeters == original.portals[0].clearWidthMeters)
        #expect(h.portals[0].operable == original.portals[0].operable)
        #expect(h.portals[0].stepFree == original.portals[0].stepFree)
        #expect(h.portals[0].verification == .proposed)
        #expect(PortalAttachment.check(h.portals[0], in: h).attached)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "sp-1"), in: h).primary == nil)
        let revised = h
        #expect(throws: ManualLayout.LayoutError.noSharedWall) {
            let neighbor = try ManualLayout.addRoom(to: &h, label: "Far room", kind: .other, width: 2, depth: 2,
                attachedTo: "sp-1", side: .north, offset: 8)
            try HomeGeometryEditor.placeOpening(in: &h, portalID: h.portals[0].id, from: "sp-1", to: .space(neighbor.id))
        }
        // The failed placement retains the original portal despite the separately added room.
        #expect(h.portals == revised.portals)
    }

    @Test func correctionRetainsIndependentCapturedBarrierAndDynamicWallsFollowRoomInventory() throws {
        var h = try home()
        let neighbor = try ManualLayout.addRoom(to: &h, label: "Untouched", kind: .other,
            width: 4, depth: 4, attachedTo: "sp-1", side: .east)
        _ = try ManualLayout.addPortal(to: &h, from: neighbor.id, to: .exterior, exteriorSide: .south,
            width: 0.9, widthMeasured: true, verified: true, operable: true, stepFree: true)
        h.source = .roomPlanScan; h.floors[0].exteriorGrade = .ground
        h.walls = ManualLayout.derivedWalls(h)
        let barrier = WallSegment(id: "independent-captured-barrier", floorID: neighbor.floorID,
            a: Vec2(4, 1), b: Vec2(8, 1))
        h.walls.append(barrier)
        let request = RouteRequest(startSpaceID: neighbor.id)
        #expect(EgressPlanner().plan(request, in: h).primary == nil)
        let neighborPortals = h.portals.filter { $0.sideA == .space(neighbor.id) }
        try HomeGeometryEditor.correctRoom(in: &h, roomID: "sp-1", width: 4, depth: 5)
        #expect(h.walls.contains(barrier))
        #expect(h.portals.filter { $0.sideA == .space(neighbor.id) } == neighborPortals)
        #expect(EgressPlanner().plan(request, in: h).primary == nil)
        let added = try ManualLayout.addRoom(to: &h, label: "New", kind: .other,
            width: 4, depth: 3, attachedTo: "sp-1", side: .north)
        #expect(ManualLayout.derivedWalls(h).contains { $0.a.y == 8 && $0.b.y == 8 })
        try HomeGeometryEditor.removeRoom(in: &h, roomID: added.id)
        #expect(!ManualLayout.derivedWalls(h).contains { $0.a.y == 8 && $0.b.y == 8 })
        #expect(h.walls.contains(barrier) && h.completeness == .incomplete)
        try HomeGeometryEditor.removeRoom(in: &h, roomID: "sp-1")
        #expect(!ManualLayout.derivedWalls(h).contains { $0.id.hasPrefix("dw-sp-1-") && $0.a.x == 0 && $0.b.x == 0 })
        #expect(h.walls.contains(barrier))
    }

    @Test func openingPlacementUsesAnActualConcaveBoundaryAndRejectsOversizedOrNonfiniteInputs() throws {
        var h = try home()
        h.spaces[0].polygon = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 1), Vec2(1, 1), Vec2(1, 4), Vec2(0, 4)]
        let opening = try ManualLayout.addPortal(to: &h, from: "sp-1", to: .exterior, exteriorSide: .east, width: 0.8)
        #expect(PortalAttachment.check(opening, in: h).attached)
        #expect(opening.a.y < 1 && opening.b.y < 1, "The bounding-box midpoint lies in the absent concave corner")
        let original = h
        #expect(throws: ManualLayout.LayoutError.wallTooShort(available: 1)) {
            try ManualLayout.addPortal(to: &h, from: "sp-1", to: .exterior, exteriorSide: .east, width: 2)
        }
        #expect(h == original)
        #expect(throws: ManualLayout.LayoutError.invalidSize) {
            try ManualLayout.addRoom(to: &h, label: "Invalid", kind: .other, width: .infinity, depth: 3, attachedTo: "sp-1", side: .north)
        }
        #expect(h == original)
    }

    @Test func oldHomePayloadHasNoInventedCorrectionHistory() throws {
        let h = try home()
        var object = try #require(JSONSerialization.jsonObject(with: DryRunJSON.encoder().encode(h)) as? [String: Any])
        object.removeValue(forKey: "originalCapturedWalls")
        var spaces = try #require(object["spaces"] as? [[String: Any]])
        for i in spaces.indices { spaces[i].removeValue(forKey: "originalCapturedPolygon"); spaces[i].removeValue(forKey: "geometryNeedsReview") }
        object["spaces"] = spaces
        let decoded = try DryRunJSON.decoder().decode(HomeModel.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.originalCapturedWalls == nil && decoded.spaces[0].originalCapturedPolygon == nil)
        #expect(decoded.spaces[0].geometryNeedsReview == nil)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "sp-1"), in: decoded).primary != nil)
    }

    @Test func physicalEscapeReviewTracksOnlyRelevantLayoutChanges() throws {
        let original = try home()
        var renamed = original
        renamed.bumpRevision(); renamed.label = "Renamed home"; renamed.spaces[0].label = "Renamed room"
        renamed.annotations.append(Annotation(id: "alarm", kind: .smokeAlarm, label: "Alarm"))
        #expect(!HomeGeometryEditor.requiresNewEscapeCheck(previous: original, updated: renamed))
        renamed.portals[0].operable = .confirmed(false)
        #expect(HomeGeometryEditor.requiresNewEscapeCheck(previous: original, updated: renamed))
        var corrected = original
        try HomeGeometryEditor.correctRoom(in: &corrected, roomID: "sp-1", width: 5, depth: 4)
        #expect(HomeGeometryEditor.requiresNewEscapeCheck(previous: original, updated: corrected))
    }

    @Test func newLevelAndStairsRequireExplicitRoomsLandingsAndExteriorReview() throws {
        var h = try home()
        let floor = try ManualLayout.addFloor(to: &h, label: "Our upper level", level: 1, elevationMeters: 2.8)
        #expect(floor.exteriorGrade == .unknown && h.connectors.isEmpty)
        let room = try ManualLayout.addFirstRoom(to: &h, label: "Our bedroom", kind: .bedroom,
            width: 4, depth: 3, floorID: floor.id)
        #expect(room.floorID == floor.id && room.id != "sp-1")
        let prior = h
        #expect(throws: HomeGeometryEditor.CorrectionError.differentFloorsRequired) {
            try HomeGeometryEditor.addStairs(in: &h, fromRoomID: "sp-1", fromPoint: Vec2(1, 1), toRoomID: "sp-1", toPoint: Vec2(2, 2))
        }
        #expect(h == prior)
        let stairs = try HomeGeometryEditor.addStairs(in: &h, fromRoomID: "sp-1", fromPoint: Vec2(1, 1), toRoomID: room.id, toPoint: Vec2(2, 1))
        #expect(stairs.verification == .proposed)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: room.id), in: h).primary == nil)
        h = HomeConfirmation.apply(.confirmConnector(connectorID: stairs.id, usable: true), to: h)
        let route = try #require(EgressPlanner().plan(RouteRequest(startSpaceID: room.id), in: h).primary)
        #expect(route.connectorSequence == [stairs.id])
        #expect(h.floors.first { $0.id == floor.id }?.exteriorGrade == .unknown)
    }
}
