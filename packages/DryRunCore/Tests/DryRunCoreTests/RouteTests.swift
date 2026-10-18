import Foundation
import Testing
@testable import DryRunCore

@Suite("Egress routes")
struct RouteTests {
    let planner = EgressPlanner()

    func plan(_ home: HomeModel, from start: String, mobility: MobilityProfile = .walking,
              blockSpaces: [String] = [], blockPortals: [String] = []) -> RouteResult {
        planner.plan(RouteRequest(personID: "test-resident", startSpaceID: start, mobility: mobility,
                                  exclusions: ScenarioExclusions(blockedSpaceIDs: blockSpaces, blockedPortalIDs: blockPortals)), in: home)
    }

    func assertClean(_ r: RouteResult, _ home: HomeModel) {
        for path in [r.primary, r.alternative].compactMap({ $0 }) {
            #expect(RouteGeometryAudit.violations(path, in: home).isEmpty, "\(RouteGeometryAudit.violations(path, in: home))")
        }
    }

    @Test func twoExitHomeHasPrimaryAndIndependentAlternative() {
        let home = SampleHomes.ranch
        let r = plan(home, from: "sp-living")
        #expect(r.noRouteReason == nil)
        #expect(r.primary?.exitPortalID == "pt-front")
        #expect(r.alternative?.exitPortalID == "pt-back")
        #expect(r.alternativeStatus == .independent)
        #expect(r.sharedChokepoints.isEmpty)
        #expect(r.homeID == home.id && r.homeRevision == home.revision && r.algorithmVersion == RouteResult.algorithmVersion)
        assertClean(r, home)
    }

    @Test func blockingOneExitFindsTheOtherAndBlockingBothYieldsNoRoute() {
        let home = SampleHomes.ranch
        let one = plan(home, from: "sp-living", blockPortals: ["pt-front"])
        #expect(one.primary?.exitPortalID == "pt-back")
        #expect(one.exclusions.contains { $0.elementID == "pt-front" && $0.reason == "blockedByScenario" })
        assertClean(one, home)

        let both = plan(home, from: "sp-living", blockPortals: ["pt-front", "pt-back"])
        #expect(both.primary == nil && both.alternative == nil)
        #expect(both.noRouteReason == .blockedByScenario)

        // Fire-style exercise: kitchen blocked; a bedroom still reaches the front door through the hall.
        let fire = plan(home, from: "sp-bed2", blockSpaces: ["sp-kitchen"])
        #expect(fire.primary?.exitPortalID == "pt-front")
        #expect(fire.primary?.spaceSequence.contains("sp-kitchen") == false)
        #expect(fire.alternativeStatus == .none)
        let hall = plan(home, from: "sp-bed2", blockSpaces: ["sp-hall"])
        #expect(hall.noRouteReason == .blockedByScenario)
    }

    @Test func pathsSharingAHallwayAreNotAdvertisedAsIndependent() {
        let home = SampleHomes.ranch
        let r = plan(home, from: "sp-bed2")
        #expect(r.primary != nil)
        #expect(r.alternative != nil)
        #expect(r.alternative?.exitPortalID != r.primary?.exitPortalID)
        #expect(r.alternativeStatus == .sharesChokepoint)
        #expect(r.sharedChokepoints.contains("sp-hall"))
        #expect(r.sharedChokepoints.contains("pt-bed2-hall"))
        assertClean(r, home)
    }

    @Test func windowsAndUnknownPortalsAreNotExits() {
        var home = SampleHomes.ranch
        // Proposed windows never count.
        let r = plan(home, from: "sp-bed1", blockPortals: ["pt-front", "pt-back"])
        #expect(r.primary == nil)
        #expect(r.exclusions.contains { $0.elementID == "pt-win-bed1" && $0.reason == "portalNotVerified" })

        // Verified window whose operability is unknown: still not an exit.
        home.edit { h in
            let i = h.portals.firstIndex { $0.id == "pt-win-bed1" }!
            h.portals[i].verification = .verified
        }
        let r2 = plan(home, from: "sp-bed1", blockPortals: ["pt-front", "pt-back"])
        #expect(r2.primary == nil)
        #expect(r2.exclusions.contains { $0.elementID == "pt-win-bed1" && $0.reason == "windowOperabilityUnconfirmed" })

        // Opening it is still insufficient. Explicit escape suitability is a separate household check.
        home.edit { h in
            let i = h.portals.firstIndex { $0.id == "pt-win-bed1" }!
            h.portals[i].operable = .confirmed(true)
        }
        let openingOnly = plan(home, from: "sp-bed1", blockPortals: ["pt-front", "pt-back"])
        #expect(openingOnly.primary == nil)
        home.portals[home.portals.firstIndex { $0.id == "pt-win-bed1" }!].emergencyEscapePersonIDs = ["test-resident"]
        let r3 = plan(home, from: "sp-bed1", blockPortals: ["pt-front", "pt-back"])
        #expect(r3.primary?.exitPortalID == "pt-win-bed1")
        #expect(r3.primary?.verificationNeeded.contains("pt-win-bed1.windowEscapeEveryPerson") == true)
        let chair = plan(home, from: "sp-bed1", mobility: .wheelchair, blockPortals: ["pt-front", "pt-back"])
        #expect(chair.primary == nil)

        // Back door whose outside is unknown is not an exit.
        var unknown = SampleHomes.ranch
        unknown.edit { h in
            let i = h.portals.firstIndex { $0.id == "pt-back" }!
            h.portals[i].sideB = .unknown
        }
        let r4 = plan(unknown, from: "sp-kitchen", blockPortals: ["pt-front"])
        #expect(r4.primary == nil)
        #expect(r4.exclusions.contains { $0.elementID == "pt-back" && $0.reason == "unknownDestination" })
    }

    @Test func mobilityIncompatibleStepsAndUnknownClearanceCannotMasquerade() {
        let home = SampleHomes.ranch
        // Front door is step-free; back door has a step.
        let ok = plan(home, from: "sp-living", mobility: .wheelchair)
        #expect(ok.primary?.exitPortalID == "pt-front")
        #expect(ok.alternative == nil || ok.alternative?.portalSequence.contains("pt-back") == false)
        let blocked = plan(home, from: "sp-living", mobility: .wheelchair, blockPortals: ["pt-front"])
        #expect(blocked.primary == nil)
        #expect(blocked.noRouteReason == .incompatibleMobility)
        #expect(blocked.exclusions.contains { $0.elementID == "pt-back" && $0.reason.hasPrefix("incompatibleMobility") })

        // Main bedroom door width is unknown: a wheelchair route is refused; a walking route flags verification.
        let chair = plan(home, from: "sp-bed1", mobility: .wheelchair)
        #expect(chair.primary == nil)
        #expect(chair.noRouteReason == .incompatibleMobility)
        let walk = plan(home, from: "sp-bed1")
        #expect(walk.primary?.verificationNeeded.contains("pt-bed1-hall.clearWidth") == true)

        // Known narrow width below the envelope.
        let closet = plan(home, from: "sp-closet", mobility: .wheelchair)
        #expect(closet.noRouteReason == .incompatibleMobility)

        // Stairs are excluded for a step-free profile.
        let two = SampleHomes.twoStory
        let up = plan(two, from: "sp-bed1", mobility: .wheelchair)
        #expect(up.primary == nil)
        #expect(up.noRouteReason == .incompatibleMobility)
        let walker = plan(two, from: "sp-bed1")
        #expect(walker.primary?.connectorSequence == ["cn-stairs"])
        #expect(walker.primary?.legs.map(\.floorID) == ["fl-upper", "fl-ground"])
        assertClean(walker, two)
    }

    @Test func upperFloorWindowsAndBalconiesAreNotGroundExits() {
        let two = SampleHomes.twoStory
        let r = plan(two, from: "sp-bed1", blockPortals: ["pt-front", "pt-back"])
        #expect(r.primary == nil)
        #expect(r.exclusions.contains { $0.elementID == "pt-win-up-bed1" && $0.reason == "notGroundLevelExit" })

        let apt = SampleHomes.apartment
        let a = plan(apt, from: "sp-bed1")
        #expect(a.primary == nil)
        #expect(a.noRouteReason == .missingBuildingPlan)
        #expect(a.exclusions.contains { $0.elementID == "pt-balcony" && $0.reason == "notGroundLevelExit" })
        #expect(a.exclusions.contains { $0.elementID == "pt-entry" && $0.reason.hasPrefix("commonAreaOutsideModel") })
    }

    @Test func rotatedAndTranslatedHomePreservesTopologyAndLength() {
        let base = SampleHomes.ranch
        let t = Transform2D(rotationRadians: 0.7, translation: Vec2(103.25, -41.5))
        var moved = base
        moved.spaces = base.spaces.map { var s = $0; s.polygon = s.polygon.map(t.apply); return s }
        moved.walls = base.walls.map { var w = $0; w.a = t.apply(w.a); w.b = t.apply(w.b); return w }
        moved.portals = base.portals.map { var p = $0; p.a = t.apply(p.a); p.b = t.apply(p.b); return p }
        moved.obstacles = base.obstacles.map { var o = $0; o.polygon = o.polygon.map(t.apply); return o }
        for start in ["sp-living", "sp-bed2", "sp-bed1"] {
            let a = plan(base, from: start), b = plan(moved, from: start)
            #expect(a.primary?.spaceSequence == b.primary?.spaceSequence)
            #expect(a.primary?.portalSequence == b.primary?.portalSequence)
            #expect(a.alternativeStatus == b.alternativeStatus)
            #expect(abs((a.primary?.lengthMeters ?? 0) - (b.primary?.lengthMeters ?? 1)) < 1e-6)
            assertClean(b, moved)
        }
        // Areas preserved exactly up to floating point (no scaling, no snapping).
        for (s0, s1) in zip(base.spaces, moved.spaces) {
            #expect(abs(abs(Geometry.signedArea(s0.polygon)) - abs(Geometry.signedArea(s1.polygon))) < 1e-9)
        }
    }

    /// L-shaped room: the straight line from the far arm to the door cuts across the reflex corner (through the wall).
    @Test func cornerCaseNaiveLineCrossesWallButRouteDetours() {
        let f = "fl-1"
        let lShape = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 2), Vec2(2, 2), Vec2(2, 6), Vec2(0, 6)]
        let home = HomeModel(
            id: "home-test-l", label: "L test", source: .manual,
            floors: [Floor(id: f, level: 0, label: "G")],
            spaces: [Space(id: "sp-l", floorID: f, label: "L", kind: .other, polygon: lShape)],
            walls: Geometry.edges(lShape).enumerated().map { WallSegment(id: "w\($0.offset)", floorID: f, a: $0.element.0, b: $0.element.1) },
            portals: [Portal(id: "pt-exit", floorID: f, kind: .door, a: Vec2(0.6, 6), b: Vec2(1.4, 6), sideA: .space("sp-l"), sideB: .exterior,
                             clearWidthMeters: .confirmed(0.8), operable: .confirmed(true), stepFree: .confirmed(true), verification: .verified)],
            obstacles: [])
        let space = home.spaces[0]
        let from = Vec2(5.2, 1.0), to = Vec2(1.0, 5.55)
        #expect(!RoomPaths.segmentOK(from, to, in: space, home: home, clearance: 0.35), "naive segment must be rejected")
        let path = RoomPaths.path(from: from, to: to, in: space, home: home, clearance: 0.35)
        #expect(path != nil)
        #expect((path?.count ?? 0) >= 3)
        if let path { for (p, q) in zip(path, path.dropFirst()) { #expect(RoomPaths.segmentOK(p, q, in: space, home: home, clearance: 0.35)) } }

        // Kitchen island in the sample home forces a detour on the living→back-door alternative.
        let ranch = SampleHomes.ranch
        let r = plan(ranch, from: "sp-living")
        let kitchenLegPoints = r.alternative?.legs.first?.points ?? []
        #expect(kitchenLegPoints.count > 6)
        assertClean(r, ranch)
    }

    @Test func nearTouchingRoomsDoNotBecomeAdjacent() {
        let f = "fl-1"
        func gapHome(_ bx: Double, door: Double, walls: [WallSegment] = []) -> HomeModel {
            HomeModel(
                id: "home-test-gap", label: "gap", source: .manual,
                floors: [Floor(id: f, level: 0, label: "G")],
                spaces: [Space(id: "sp-a", floorID: f, label: "A", kind: .other, polygon: SampleHomes.rect(0, 0, 4, 4)),
                         Space(id: "sp-b", floorID: f, label: "B", kind: .other, polygon: SampleHomes.rect(bx, 0, 8, 4))],
                walls: walls,
                portals: [
                    Portal(id: "pt-ab", floorID: f, kind: .door, a: Vec2(door, 1), b: Vec2(door, 1.9), sideA: .space("sp-a"), sideB: .space("sp-b"),
                           clearWidthMeters: .confirmed(0.9), operable: .confirmed(true), stepFree: .confirmed(true), verification: .verified),
                    Portal(id: "pt-bx", floorID: f, kind: .door, a: Vec2(8, 1), b: Vec2(8, 1.9), sideA: .space("sp-b"), sideB: .exterior,
                           clearWidthMeters: .confirmed(0.9), operable: .confirmed(true), stepFree: .confirmed(true), verification: .verified),
                ])
        }
        // 6 cm unexplained gap: wider than contact, thinner than any framed wall -> never adjacent.
        let near = gapHome(4.06, door: 4.03)
        #expect(HomeValidator.validate(near).filter { $0.kind == .portalNotOnSharedBoundary && $0.elementID == "pt-ab" }.count == 1)
        let r = plan(near, from: "sp-a")
        #expect(r.primary == nil)
        #expect(r.exclusions.contains { $0.elementID == "pt-ab" && $0.reason.hasPrefix("invalidGeometry") })

        // Explicit 0.12 m wall but outlines 0.25 m apart: farther apart than the wall is thick -> not adjacent.
        let thin = gapHome(4.25, door: 4.125, walls: [WallSegment(id: "w-mid", floorID: f, a: Vec2(4.125, 0), b: Vec2(4.125, 4), thicknessMeters: 0.12)])
        #expect(plan(thin, from: "sp-a").primary == nil)
        // Same outlines with a wall that really is 0.25 m thick -> adjacent, and the drawn path passes the audit.
        let thick = gapHome(4.25, door: 4.125, walls: [WallSegment(id: "w-mid", floorID: f, a: Vec2(4.125, 0), b: Vec2(4.125, 4), thicknessMeters: 0.25)])
        let ok = plan(thick, from: "sp-a", mobility: .wheelchair)
        #expect(ok.primary?.exitPortalID == "pt-bx")
        assertClean(ok, thick)
    }

    @Test func thickScannedWallsRouteWithCleanGeometryOnceConfirmed() {
        // Outlines at inner wall faces 0.15 m apart, no explicit walls (RoomPlan-like); door centred in the wall.
        let f = "fl-1"
        let home = HomeModel(
            id: "home-test-thick", label: "thick", source: .roomPlanScan,
            floors: [Floor(id: f, level: 0, label: "G", exteriorGrade: .ground)],
            spaces: [Space(id: "sp-a", floorID: f, label: "A", kind: .other, polygon: SampleHomes.rect(0, 0, 4, 4)),
                     Space(id: "sp-b", floorID: f, label: "B", kind: .other, polygon: SampleHomes.rect(4.15, 0, 8, 4))],
            portals: [
                Portal(id: "pt-ab", floorID: f, kind: .door, a: Vec2(4.075, 1), b: Vec2(4.075, 1.9), sideA: .space("sp-a"), sideB: .space("sp-b"),
                       clearWidthMeters: .confirmed(0.9), operable: .confirmed(true), stepFree: .confirmed(true), verification: .verified),
                Portal(id: "pt-bx", floorID: f, kind: .door, a: Vec2(8, 1), b: Vec2(8, 1.9), sideA: .space("sp-b"), sideB: .exterior,
                       clearWidthMeters: .confirmed(0.9), operable: .confirmed(true), stepFree: .confirmed(true), verification: .verified),
            ])
        #expect(!HomeValidator.validate(home).contains { $0.kind == .portalNotOnSharedBoundary })
        for mobility in [MobilityProfile.walking, .wheelchair] {
            let r = plan(home, from: "sp-a", mobility: mobility)
            #expect(r.primary?.exitPortalID == "pt-bx")
            assertClean(r, home)
        }
    }

    @Test func fingerprintDistinguishesNaNHomesAndIsCurrentChecksContent() {
        var a = SampleHomes.ranch, b = SampleHomes.ranch
        a.spaces[0].polygon[0] = Vec2(.nan, 0)
        b.spaces[1].polygon[0] = Vec2(.nan, 0)
        #expect(HomeFingerprint.of(a) != HomeFingerprint.of(b))
        #expect(HomeFingerprint.of(a) != HomeFingerprint.of(SampleHomes.ranch))
        #expect(HomeFingerprint.of(SampleHomes.ranch) == HomeFingerprint.of(SampleHomes.ranch))

        let home = SampleHomes.ranch
        let r = plan(home, from: "sp-living")
        #expect(r.isCurrent(for: home))
        var edited = home
        edited.portals[0].note = "changed without a revision bump"
        #expect(!r.isCurrent(for: edited))
        var legacy = r
        legacy.homeFingerprint = nil
        #expect(!legacy.isCurrent(for: home), "results without a fingerprint are never current")
    }

    @Test func editingDoorVerificationInvalidatesCachedRoute() {
        let cache = RouteCache()
        var home = SampleHomes.ranch
        let req = RouteRequest(startSpaceID: "sp-living")
        let before = cache.route(req, in: home)
        #expect(before.primary?.exitPortalID == "pt-front")
        #expect(cache.route(req, in: home) == before)

        home.edit { h in
            let i = h.portals.firstIndex { $0.id == "pt-front" }!
            h.portals[i].verification = .rejected
        }
        #expect(!before.isCurrent(for: home))
        let after = cache.route(req, in: home)
        #expect(after.primary?.exitPortalID == "pt-back")
        #expect(after.isCurrent(for: home))
        #expect(cache.count == 1)

        // Even an edit that forgot to bump the revision misses the cache (content fingerprint).
        var sneaky = home
        let j = sneaky.portals.firstIndex { $0.id == "pt-back" }!
        sneaky.portals[j].verification = .proposed
        #expect(sneaky.revision == home.revision)
        let stale = cache.route(req, in: sneaky)
        #expect(stale.primary == nil)
        #expect(!after.isCurrent(for: sneaky), "isCurrent compares content, not just revision")
    }

    @Test func planningIsDeterministic() {
        let home = SampleHomes.ranch
        for start in home.spaces.map(\.id) {
            #expect(plan(home, from: start) == plan(home, from: start))
        }
        #expect(plan(home, from: "sp-nowhere").noRouteReason == .unknownStartSpace)
    }
}
