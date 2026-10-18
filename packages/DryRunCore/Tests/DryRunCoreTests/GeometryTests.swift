import Foundation
import Testing
@testable import DryRunCore

@Suite("Geometry and scan import")
struct GeometryTests {
    @Test func primitivesUseNamedTolerancesWithoutSnapping() {
        #expect(Geometry.intersection(Vec2(0, 0), Vec2(2, 2), Vec2(0, 2), Vec2(2, 0)) == Vec2(1, 1))
        #expect(Geometry.intersection(Vec2(0, 0), Vec2(1, 0), Vec2(0, 1), Vec2(1, 1)) == nil)
        #expect(Geometry.collinearOverlap(Vec2(0, 0), Vec2(2, 0), Vec2(1, 0), Vec2(3, 0)))
        #expect(!Geometry.collinearOverlap(Vec2(0, 0), Vec2(1, 0), Vec2(1.5, 0), Vec2(3, 0)))
        let sq = SampleHomes.rect(0, 0, 2, 2)
        #expect(Geometry.contains(sq, Vec2(1, 1)))
        #expect(!Geometry.contains(sq, Vec2(2, 1)), "boundary points are not inside")
        #expect(!Geometry.contains(sq, Vec2(3, 1)))
        #expect(abs(Geometry.signedArea(sq) - 4) < 1e-12)
        // A 1 mm gap is still a gap: tolerances are explicit per question, never applied globally.
        #expect(Geometry.distanceSegmentSegment(Vec2(0, 0), Vec2(1, 0), Vec2(0, 0.001), Vec2(1, 0.001)) > 0)
        let t = Transform2D(rotationRadians: .pi / 2, translation: Vec2(1, 0))
        let p = t.apply(Vec2(1, 0))
        #expect(abs(p.x - 1) < 1e-12 && abs(p.y - 1) < 1e-12)
    }

    @Test func concavePolygonTriangulationPreservesAreaAndRejectsBowties() {
        // An L-shaped floor: the notch must remain empty in the display mesh.
        let concave = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 1), Vec2(1, 1), Vec2(1, 4), Vec2(0, 4)]
        let triangles = try! #require(Geometry.triangulate(concave))
        #expect(triangles.count == concave.count - 2)
        let triangleArea = triangles.reduce(0.0) { total, t in
            total + abs(Geometry.signedArea(t.map { concave[$0] }))
        }
        #expect(abs(triangleArea - abs(Geometry.signedArea(concave))) < 1e-9)

        let bowtie = [Vec2(0, 0), Vec2(2, 2), Vec2(0, 2), Vec2(2, 0)]
        #expect(Geometry.triangulate(bowtie) == nil)
    }

    @Test func roomOverlapDistinguishesAlignedStripsFromSharedWallsAndConcaveNotches() {
        let first = SampleHomes.rect(0, 0, 5, 4)
        #expect(Geometry.polygonsOverlap(first, SampleHomes.rect(4, 0, 7, 4)))
        #expect(!Geometry.polygonsOverlap(first, SampleHomes.rect(5, 0, 7, 4)))
        #expect(!Geometry.polygonsOverlap(first, SampleHomes.rect(5, 4, 7, 6)))
        let l = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 1), Vec2(1, 1), Vec2(1, 4), Vec2(0, 4)]
        #expect(!Geometry.polygonsOverlap(l, SampleHomes.rect(1, 1, 4, 4)))
        #expect(Geometry.polygonsOverlap(l, SampleHomes.rect(0.5, 2, 2, 3)))
        #expect(!Geometry.isSimplePolygon([Vec2(0, 0), Vec2(.infinity, 0), Vec2(0, 1)]))
    }

    // House-local layout (metres, x/z ground plane, y up). Room A: 4×4 at origin; Room B: 4×3 to the east.
    static let worldYaw = 0.5
    static let worldT = Vec3(10, 0, -3)
    static var world: RigidTransform3D { .yaw(worldYaw, translation: worldT) }

    static func surface(_ id: String, _ cat: ScanSurfaceCategory, _ p: Vec3, _ q: Vec3, conf: ScanConfidence = .high) -> ScanSurface {
        let d = Vec3(q.x - p.x, 0, q.z - p.z)
        let len = (d.x * d.x + d.z * d.z).squareRoot()
        let localYaw = atan2(-d.z, d.x)
        let center = world.apply(Vec3((p.x + q.x) / 2, 0, (p.z + q.z) / 2))
        return ScanSurface(id: id, category: cat, transform: .yaw(localYaw + worldYaw, translation: center),
                           dimensions: Vec3(len, 2.4, 0.1), confidence: conf)
    }

    static func floor(_ id: String, _ corners: [Vec3]) -> ScanSurface {
        ScanSurface(id: id, category: .floor, transform: world, dimensions: Vec3(0, 0, 0), polygonCorners: corners, confidence: .high)
    }

    static var capture: ScanCapture {
        // In (x, z): Room A x 0..4, z 0..-4 (z negative = "north" after projection v = -z).
        let a = ScanRoom(id: "A", story: 0, surfaces: [
            floor("fa", [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 0, -4), Vec3(0, 0, -4)]),
            surface("wa1", .wall, Vec3(0, 0, 0), Vec3(4, 0, 0)),
            surface("wa2", .wall, Vec3(4, 0, 0), Vec3(4, 0, -4)),
            surface("wa3", .wall, Vec3(4, 0, -4), Vec3(0, 0, -4)),
            surface("wa4", .wall, Vec3(0, 0, -4), Vec3(0, 0, 0)),
            surface("door-ab", .doorOpen, Vec3(4, 0, -1.5), Vec3(4, 0, -2.4)),
            surface("win-a", .window, Vec3(1, 0, -4), Vec3(2, 0, -4)),
        ], objects: [
            ScanObject(id: "sofa", category: "sofa", transform: .yaw(worldYaw, translation: world.apply(Vec3(1.5, 0, -1))),
                       dimensions: Vec3(1.8, 0.8, 0.8), confidence: .medium),
        ])
        let b = ScanRoom(id: "B", story: 0, surfaces: [
            floor("fb", [Vec3(4, 0, 0), Vec3(8, 0, 0), Vec3(8, 0, -3), Vec3(4, 0, -3)]),
            surface("wb1", .wall, Vec3(4, 0, 0), Vec3(8, 0, 0)),
            surface("wb2", .wall, Vec3(8, 0, 0), Vec3(8, 0, -3)),
            surface("wb3", .wall, Vec3(8, 0, -3), Vec3(4, 0, -3)),
            surface("door-ab-dup", .doorOpen, Vec3(4, 0, -2.4), Vec3(4, 0, -1.5)), // same door seen from B
            surface("door-out", .doorClosed, Vec3(8, 0, -1), Vec3(8, 0, -1.9)),
        ])
        return ScanCapture(rooms: [a, b], sharedCoordinateFrame: true)
    }

    @Test func rotatedTranslatedScanPreservesUnitsAndTopologyAndStaysProposed() throws {
        let result = try ScanImport.importCapture(Self.capture, homeID: "home-scan-test")
        let home = result.home
        #expect(home.source == .roomPlanScan)
        #expect(home.spaces.count == 2)
        #expect(abs(abs(Geometry.signedArea(home.spaces[0].polygon)) - 16) < 1e-9)
        #expect(abs(abs(Geometry.signedArea(home.spaces[1].polygon)) - 12) < 1e-9)

        // Door centre equals the exact rigid transform of its house-local position (no snapping/axis alignment).
        let expected = Transform2D(rotationRadians: Self.worldYaw, translation: Vec2(Self.worldT.x, -Self.worldT.z)).apply(Vec2(4, 1.95))
        let door = try #require(home.portals.first { $0.id == "pt-door-ab" })
        #expect(door.center.distance(to: expected) < 1e-9)
        #expect(home.portals.filter { $0.kind == .door }.count == 2, "duplicate door from room B is merged")

        // Adjacency proposed by geometry, never verified; windows/unknown exterior never assumed.
        #expect(Set([door.sideA, door.sideB]) == Set([.space("sp-scan-1"), .space("sp-scan-2")]))
        #expect(home.portals.allSatisfy { $0.verification == .proposed && $0.operable.value == nil })
        let win = try #require(home.portals.first { $0.kind == .window })
        #expect(win.sideB == .unknown)
        let out = try #require(home.portals.first { $0.id == "pt-door-out" })
        #expect(!out.leadsToExterior, "a scanned door with one room is NOT assumed to lead outside")
        #expect(home.completeness == .incomplete)
        #expect(home.obstacles.count == 1)

        // Unconfirmed scan: no practice route.
        let r = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-scan-1"), in: home)
        #expect(r.primary == nil)
        #expect(r.noRouteReason == .noVerifiedExteriorExit)

        // After the confirmation pass the same geometry routes cleanly.
        var confirmed = home
        #expect(confirmed.floors.allSatisfy { $0.exteriorGrade == .unknown })
        confirmed = HomeConfirmation.apply(.floorGrade(floorID: confirmed.floors[0].id, grade: .ground), to: confirmed)
        confirmed.edit { h in
            for i in h.portals.indices where h.portals[i].kind == .door {
                h.portals[i].verification = .verified
                h.portals[i].operable = .confirmed(true)
                h.portals[i].stepFree = .confirmed(true)
                if h.portals[i].id == "pt-door-out" { h.portals[i].sideB = .exterior }
            }
        }
        let r2 = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-scan-1"), in: confirmed)
        #expect(r2.primary?.exitPortalID == "pt-door-out")
        // Scanned widths are evidence, not confirmation: walkers get a verification item, wheelchair users no route.
        #expect(r2.primary?.verificationNeeded.contains("pt-door-out.clearWidth") == true)
        let chair = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-scan-1", mobility: .wheelchair), in: confirmed)
        #expect(chair.primary == nil)
        #expect(chair.exclusions.contains { $0.reason == "incompatibleMobility: scanned clear width not confirmed" })
        if let p = r2.primary { #expect(RouteGeometryAudit.violations(p, in: confirmed).isEmpty) }
    }

    @Test func recognisedRoomTypeIsOnlyAnUnconfirmedPrefill() throws {
        var capture = Self.capture
        capture.rooms[0].suggestedKind = .bedroom
        let home = try ScanImport.importCapture(capture, homeID: "home-scan-kind").home
        let rooms = home.spaces.sorted { $0.id < $1.id }
        #expect(rooms.map(\.kind) == [.bedroom, .other])
        #expect(rooms.allSatisfy { !$0.labelConfirmed })
        // The suggestion changes no geometry: same rooms, openings and outlines as without it.
        let plain = try ScanImport.importCapture(Self.capture, homeID: "home-scan-kind").home
        #expect(plain.spaces.map(\.polygon) == home.spaces.map(\.polygon))
        #expect(plain.portals == home.portals)
    }

    @Test func independentlyScannedRoomsAreNeverPlacedByGuessing() {
        var c = Self.capture
        c.sharedCoordinateFrame = false
        #expect(throws: ScanImportError.unsharedCoordinateFrames(roomCount: 2)) {
            try ScanImport.importCapture(c, homeID: "x")
        }
        #expect(throws: ScanImportError.empty) { try ScanImport.importCapture(ScanCapture(rooms: [], sharedCoordinateFrame: true), homeID: "x") }
    }

    @Test func interruptedCaptureRemainsIncompleteEvenWithSeveralSavedRooms() throws {
        var capture = Self.capture
        capture.sessionCompleted = false
        let result = try ScanImport.importCapture(capture, homeID: "interrupted")
        #expect(result.home.completeness == .incomplete)
        #expect(result.notes.contains { $0.contains("did not finish") })
    }

    @Test func nearTouchingScannedRoomsWithoutADoorAreNotConnected() throws {
        // Two rooms 0.3 m apart with no door between them.
        var c = Self.capture
        c.rooms[1].surfaces = c.rooms[1].surfaces.filter { $0.id != "door-ab-dup" }
        c.rooms[0].surfaces = c.rooms[0].surfaces.filter { $0.id != "door-ab" }
        c.rooms[1].surfaces[0] = Self.floor("fb", [Vec3(4.3, 0, 0), Vec3(8, 0, 0), Vec3(8, 0, -3), Vec3(4.3, 0, -3)])
        let home = try ScanImport.importCapture(c, homeID: "x").home
        #expect(!home.portals.contains { $0.sideA == .space("sp-scan-2") && $0.sideB == .space("sp-scan-1") })
        #expect(!home.portals.contains { $0.sideA == .space("sp-scan-1") && $0.sideB == .space("sp-scan-2") })
    }

    @Test func stairsWithoutTheOtherFloorAreFlaggedNotInvented() throws {
        var c = Self.capture
        c.rooms[0].objects.append(ScanObject(id: "st", category: "stairs", transform: .yaw(Self.worldYaw, translation: Self.world.apply(Vec3(3, 0, -3))),
                                             dimensions: Vec3(1, 2.5, 3), confidence: .high))
        let r = try ScanImport.importCapture(c, homeID: "x")
        #expect(r.home.connectors.isEmpty)
        #expect(r.home.completeness == .incomplete)
        #expect(r.notes.contains { $0.contains("Stairs detected") })
    }
}
