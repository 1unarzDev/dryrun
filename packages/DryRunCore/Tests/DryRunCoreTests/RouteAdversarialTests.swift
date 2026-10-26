import Foundation
import Testing
@testable import DryRunCore

// Adversarial probes of the spatial lane (written by Agent A, reviewer; see docs/lanes/review-routing.md).
// Probes from Agent A's routing review. All confirmed defects were fixed by Agent B; probes are now regressions.

private let f = "fl-0"
private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] { [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)] }
private func door(_ id: String, _ a: Vec2, _ b: Vec2, _ sa: PortalDestination, _ sb: PortalDestination, kind: PortalKind = .door,
                  width: EvidenceValue<Double> = .confirmed(0.9), operable: EvidenceValue<Bool> = .confirmed(true),
                  stepFree: EvidenceValue<Bool> = .confirmed(true), verification: VerificationState = .verified, floor: String = f) -> Portal {
    Portal(id: id, floorID: floor, kind: kind, a: a, b: b, sideA: sa, sideB: sb, clearWidthMeters: width, operable: operable,
           stepFree: stepFree, verification: verification)
}
private func home(_ spaces: [Space], _ portals: [Portal], walls: [WallSegment] = [], obstacles: [Obstacle] = [],
                  floors: [Floor] = [Floor(id: f, level: 0, label: "G")], connectors: [FloorConnector] = []) -> HomeModel {
    HomeModel(id: "h-probe", label: "probe", source: .manual, floors: floors, spaces: spaces, walls: walls, portals: portals,
              obstacles: obstacles, connectors: connectors, isFictional: true)
}
private let planner = EgressPlanner()

@Suite("Route adversarial probes")
struct RouteAdversarialTests {
    @Test("L-shaped room: path bends around the reflex corner and never crosses a boundary")
    func lShape() {
        // L: (0,0)-(6,0)-(6,2)-(2,2)-(2,6)-(0,6). Start top of the vertical leg, exit at the far end of the horizontal leg.
        let L = Space(id: "sp-L", floorID: f, label: "L", kind: .hallway,
                      polygon: [Vec2(0, 0), Vec2(6, 0), Vec2(6, 2), Vec2(2, 2), Vec2(2, 6), Vec2(0, 6)])
        let top = Space(id: "sp-top", floorID: f, label: "Top", kind: .bedroom, polygon: rect(0, 6, 2, 8))
        let h = home([L, top], [
            door("pt-top", Vec2(0.6, 6), Vec2(1.4, 6), .space("sp-top"), .space("sp-L")),
            door("pt-exit", Vec2(6, 0.6), Vec2(6, 1.4), .space("sp-L"), .exterior),
        ])
        let r = planner.plan(RouteRequest(startSpaceID: "sp-top"), in: h)
        let p = try! #require(r.primary)
        #expect(RouteGeometryAudit.violations(p, in: h) == [])
        // Every segment stays inside the union of the two rooms.
        for leg in p.legs { for (a, b) in zip(leg.points, leg.points.dropFirst()) {
            let mid = Vec2((a.x + b.x) / 2, (a.y + b.y) / 2)
            #expect(Geometry.contains(L.polygon, mid) || Geometry.contains(top.polygon, mid) || mid.x >= 6 || abs(mid.y - 6) < 0.5)
        } }
    }

    @Test("Obstacle on the naive line forces a detour that keeps clear of it")
    func obstacleDetour() {
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .livingRoom, polygon: rect(0, 0, 8, 4))
        let h = home([room], [door("pt-x", Vec2(8, 1.6), Vec2(8, 2.4), .space("sp-r"), .exterior)],
                     obstacles: [Obstacle(id: "ob", floorID: f, label: "sofa", polygon: rect(3, 0.8, 5, 3.2))])
        let p = try! #require(planner.plan(RouteRequest(startSpaceID: "sp-r"), in: h).primary)
        #expect(RouteGeometryAudit.violations(p, in: h) == [])
        for leg in p.legs { for (a, b) in zip(leg.points, leg.points.dropFirst()) {
            #expect(Geometry.distanceSegmentPolygon(a, b, h.obstacles[0].polygon) > 0.3)
        } }
    }

    @Test("Proposed, unknown-destination, common-area, and unconfirmed-window portals never become exits")
    func notExits() {
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .livingRoom, polygon: rect(0, 0, 4, 4))
        let h = home([room], [
            door("pt-prop", Vec2(4, 1), Vec2(4, 1.9), .space("sp-r"), .exterior, verification: .proposed),
            door("pt-unk", Vec2(0, 1), Vec2(0, 1.9), .space("sp-r"), .unknown),
            door("pt-common", Vec2(1, 4), Vec2(1.9, 4), .space("sp-r"), .commonArea("corridor")),
            door("pt-win", Vec2(1, 0), Vec2(2, 0), .space("sp-r"), .exterior, kind: .window, operable: .unknown),
        ])
        let r = planner.plan(RouteRequest(startSpaceID: "sp-r"), in: h)
        #expect(r.primary == nil)
        #expect(r.noRouteReason == .missingBuildingPlan)
    }

    @Test("Verified exterior door on an upper floor is not a walking exit")
    func upperFloor() {
        let up = Floor(id: "fl-1", level: 1, label: "Up", elevationMeters: 3)
        let room = Space(id: "sp-up", floorID: "fl-1", label: "Up", kind: .bedroom, polygon: rect(0, 0, 4, 4))
        let h = home([room], [door("pt-balcony", Vec2(4, 1), Vec2(4, 1.9), .space("sp-up"), .exterior, floor: "fl-1")], floors: [up])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-up"), in: h).primary == nil)
    }

    @Test("Unverified stairs are not used; verified stairs are excluded for step-free routes")
    func stairs() {
        let g = Floor(id: f, level: 0, label: "G"), u = Floor(id: "fl-1", level: 1, label: "U", elevationMeters: 3)
        let down = Space(id: "sp-down", floorID: f, label: "Down", kind: .livingRoom, polygon: rect(0, 0, 4, 4))
        let upS = Space(id: "sp-upS", floorID: "fl-1", label: "Up", kind: .bedroom, polygon: rect(0, 0, 4, 4))
        var cn = FloorConnector(id: "cn", kind: .stairs, fromSpaceID: "sp-upS", toSpaceID: "sp-down", fromPoint: Vec2(2, 2), toPoint: Vec2(2, 2),
                                verification: .proposed)
        var h = home([down, upS], [door("pt-front", Vec2(4, 1), Vec2(4, 1.9), .space("sp-down"), .exterior)], floors: [g, u], connectors: [cn])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-upS"), in: h).primary == nil)
        cn.verification = .verified
        h.connectors = [cn]
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-upS"), in: h).primary != nil)
        let wc = planner.plan(RouteRequest(startSpaceID: "sp-upS", mobility: .wheelchair), in: h)
        #expect(wc.primary == nil && wc.noRouteReason == .incompatibleMobility)
    }

    @Test("Step-free request rejects unknown width and unknown threshold")
    func stepFreeUnknowns() {
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .livingRoom, polygon: rect(0, 0, 4, 4))
        let h1 = home([room], [door("pt", Vec2(4, 1), Vec2(4, 2), .space("sp-r"), .exterior, width: .unknown)])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-r", mobility: .wheelchair), in: h1).primary == nil)
        let h2 = home([room], [door("pt", Vec2(4, 1), Vec2(4, 2), .space("sp-r"), .exterior, stepFree: .unknown)])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-r", mobility: .wheelchair), in: h2).primary == nil)
    }

    @Test("Scan-observed (unconfirmed) operability/step-free values never satisfy hard requirements (was a defect; fixed)")
    func scannedValuesTreatedAsConfirmed() {
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .bedroom, polygon: rect(0, 0, 4, 4))
        // Household verified the portal's existence/destination, but operability is only a scan observation.
        let win = home([room], [door("pt-win", Vec2(1, 0), Vec2(2, 0), .space("sp-r"), .exterior, kind: .window,
                                     operable: .scanned(true))])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-r"), in: win).primary == nil)
        let d = home([room], [door("pt", Vec2(4, 1), Vec2(4, 2), .space("sp-r"), .exterior, stepFree: .scanned(true))])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-r", mobility: .wheelchair), in: d).primary == nil)
    }

    @Test("Near-touching rooms (9 cm gap, no explicit walls) do not become adjacent through a portal in the gap")
    func nearTouching() {
        let a = Space(id: "sp-a", floorID: f, label: "A", kind: .bedroom, polygon: rect(0, 0, 4, 4))
        let b = Space(id: "sp-b", floorID: f, label: "B", kind: .livingRoom, polygon: rect(4.09, 0, 8, 4))
        let h = home([a, b], [
            door("pt-gap", Vec2(4.045, 1), Vec2(4.045, 1.9), .space("sp-a"), .space("sp-b")),
            door("pt-exit", Vec2(8, 1), Vec2(8, 1.9), .space("sp-b"), .exterior),
        ])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-a"), in: h).primary == nil)
    }

    @Test("Scanned home with realistic wall thickness can route once the household verifies its doors")
    func thickWallScan() throws {
        // Two rooms whose floor outlines stop at inner wall faces 0.15 m apart; door centred in the wall.
        let a = Space(id: "sp-a", floorID: f, label: "A", kind: .bedroom, polygon: rect(0, 0, 4, 4))
        let b = Space(id: "sp-b", floorID: f, label: "B", kind: .livingRoom, polygon: rect(4.15, 0, 8, 4))
        let h = home([a, b], [
            door("pt-mid", Vec2(4.075, 1), Vec2(4.075, 1.9), .space("sp-a"), .space("sp-b")),
            door("pt-exit", Vec2(8, 1), Vec2(8, 1.9), .space("sp-b"), .exterior),
        ])
        #expect(planner.plan(RouteRequest(startSpaceID: "sp-a"), in: h).primary != nil)
    }

    @Test("Two routes through the same hallway to different exits are not advertised as independent")
    func sharedHallway() {
        let r = planner.plan(RouteRequest(startSpaceID: "sp-bed2"), in: SampleHomes.ranch)
        #expect(r.primary != nil)
        #expect(r.alternativeStatus != .independent)
        if r.alternativeStatus == .sharesChokepoint { #expect(r.sharedChokepoints.contains("sp-hall")) }
    }

    @Test("Rotated and translated floor coordinates preserve topology and length")
    func rotatedTranslated() {
        let base = SampleHomes.ranch
        let t = Transform2D(rotationRadians: 0.6435, translation: Vec2(-13.7, 42.1))
        var h = base
        h.spaces = base.spaces.map { var s = $0; s.polygon = s.polygon.map(t.apply); return s }
        h.walls = base.walls.map { var w = $0; w.a = t.apply(w.a); w.b = t.apply(w.b); return w }
        h.portals = base.portals.map { var p = $0; p.a = t.apply(p.a); p.b = t.apply(p.b); return p }
        h.obstacles = base.obstacles.map { var o = $0; o.polygon = o.polygon.map(t.apply); return o }
        for start in ["sp-bed1", "sp-bed2", "sp-living"] {
            let r0 = planner.plan(RouteRequest(startSpaceID: start), in: base), r1 = planner.plan(RouteRequest(startSpaceID: start), in: h)
            #expect(r0.primary?.spaceSequence == r1.primary?.spaceSequence)
            #expect(r0.primary?.exitPortalID == r1.primary?.exitPortalID)
            #expect(abs((r0.primary?.lengthMeters ?? 0) - (r1.primary?.lengthMeters ?? 0)) < 1e-6)
            #expect(r1.primary.map { RouteGeometryAudit.violations($0, in: h) } == [])
        }
    }

    @Test("Cache never serves a route after an edit; isCurrent must not trust revision alone")
    func cacheStaleness() {
        let cache = RouteCache()
        var h = SampleHomes.ranch
        let req = RouteRequest(startSpaceID: "sp-bed2")
        let before = cache.route(req, in: h)
        #expect(before.primary?.exitPortalID == "pt-back")
        // Edit WITHOUT bumping revision: the back door is rejected.
        if let i = h.portals.firstIndex(where: { $0.id == "pt-back" }) { h.portals[i].verification = .rejected }
        let after = cache.route(req, in: h)
        #expect(after.primary?.exitPortalID != "pt-back")
        #expect(!before.isCurrent(for: h))
    }

    @Test("Deterministic under ties and input permutation")
    func determinism() {
        // Symmetric room with two equal exits.
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .livingRoom, polygon: rect(0, 0, 4, 4))
        let p1 = door("pt-east", Vec2(4, 1.55), Vec2(4, 2.45), .space("sp-r"), .exterior)
        let p2 = door("pt-west", Vec2(0, 1.55), Vec2(0, 2.45), .space("sp-r"), .exterior)
        let a = planner.plan(RouteRequest(startSpaceID: "sp-r"), in: home([room], [p1, p2]))
        let b = planner.plan(RouteRequest(startSpaceID: "sp-r"), in: home([room], [p2, p1]))
        #expect(a.primary == b.primary)
        #expect(a.alternative == b.alternative)
        var shuffled = SampleHomes.ranch
        shuffled.portals.reverse(); shuffled.spaces.reverse(); shuffled.walls.reverse(); shuffled.obstacles.reverse()
        for s in ["sp-bed1", "sp-bed2"] {
            #expect(planner.plan(RouteRequest(startSpaceID: s), in: SampleHomes.ranch).primary == planner.plan(RouteRequest(startSpaceID: s), in: shuffled).primary)
        }
    }

    @Test("ScanImport never produces verified anything; wall-only L-shaped room is flagged for measurement")
    func scanImportProposalsOnly() throws {
        func wall(_ id: String, _ a: Vec2, _ b: Vec2, _ cat: ScanSurfaceCategory = .wall) -> ScanSurface {
            let c = Vec2((a.x + b.x) / 2, (a.y + b.y) / 2), d = b - a
            return ScanSurface(id: id, category: cat, transform: .yaw(atan2(d.y, d.x), translation: Vec3(c.x, 0, -c.y)),
                               dimensions: Vec3(d.length, 2.4, 0.1), polygonCorners: [], confidence: .high)
        }
        let pts = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 2), Vec2(2, 2), Vec2(2, 6), Vec2(0, 6)]
        var surfaces = pts.indices.map { wall("w\($0)", pts[$0], pts[($0 + 1) % pts.count]) }
        surfaces.append(wall("d1", Vec2(6, 0.6), Vec2(6, 1.4), .doorClosed))
        surfaces.append(wall("win", Vec2(0.5, 6), Vec2(1.5, 6), .window))
        let res = try ScanImport.importCapture(ScanCapture(rooms: [ScanRoom(id: "r1", surfaces: surfaces)], sharedCoordinateFrame: true), homeID: "scan")
        let h = res.home
        #expect(h.portals.allSatisfy { $0.verification == .proposed && !$0.leadsToExterior && $0.operable.value == nil })
        #expect(h.connectors.allSatisfy { $0.verification == .proposed })
        #expect(h.spaces.allSatisfy { !$0.labelConfirmed })
        #expect(h.portals.allSatisfy { !$0.clearWidthMeters.isConfirmed })
        #expect(planner.plan(RouteRequest(startSpaceID: h.spaces[0].id), in: h).primary == nil)
        #expect(h.spaces[0].needsMeasurement)
        #expect(throws: ScanImportError.self) {
            _ = try ScanImport.importCapture(ScanCapture(rooms: [ScanRoom(id: "a", surfaces: surfaces), ScanRoom(id: "b", surfaces: surfaces)],
                                                         sharedCoordinateFrame: false), homeID: "x")
        }
    }

    @Test("Door near a room corner: route still found (functional probe)")
    func doorAtCorner() {
        let room = Space(id: "sp-r", floorID: f, label: "R", kind: .livingRoom, polygon: rect(0, 0, 4, 4))
        let h = home([room], [door("pt", Vec2(4, 0.1), Vec2(4, 0.95), .space("sp-r"), .exterior)])
        let r = planner.plan(RouteRequest(startSpaceID: "sp-r"), in: h)
        #expect(r.primary != nil)   // suspected defect did not reproduce
        #expect(r.primary.map { RouteGeometryAudit.violations($0, in: h) } == [])
    }

    @Test("Fire rehearsal: no practice route enters an authored blocked space except the person's own start room")
    func fireBlocked() throws {
        for h in SampleHouseholds.all {
            for v in [[String](), ["second-exit-blocked"]] {
                let r = try SimFixtures.run(h, "home-fire", variants: v)
                for route in r.routes { guard let p = route.primary else { continue }
                    let blocked = Set(route.request.exclusions.blockedSpaceIDs)
                    #expect(Set(p.spaceSequence.dropFirst()).isDisjoint(with: blocked))
                    #expect(!p.portalSequence.contains { route.request.exclusions.blockedPortalIDs.contains($0) })
                    #expect(RouteGeometryAudit.violations(p, in: SimFixtures.home) == [])
                }
            }
        }
    }
}
