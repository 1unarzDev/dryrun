import XCTest
@testable import DryRunCore

/// Milestone 5 card behaviour on a scanned home: every answer the in-place card gives round-trips, Restore and
/// Revert return exactly what the scan saw, and the saved-home routes recompute after each change.
final class OpeningCardCorrectionsTests: XCTestCase {
    private var scanned: HomeModel {
        var home = SampleHomes.ranch
        home.source = .roomPlanScan
        home.isFictional = false
        for i in home.floors.indices { home.floors[i].exteriorGrade = .ground }
        home.scanSnapshot = ScanSnapshot(home)
        return home
    }
    private func request(_ room: String = "sp-bed1") -> RouteRequest { RouteRequest(startSpaceID: room) }

    func testLeadsToOffersOnlyRoomsTouchingTheOpeningAndKeepsTheRecordedSide() throws {
        let home = scanned
        for portal in home.portals {
            for from in ScanCorrections.sideRoomIDs(portal) {
                let offered = ScanCorrections.leadsToRooms(portal.id, from: from, in: home)
                XCTAssertFalse(offered.contains(from), "\(portal.id): never the room itself")
                for other in ScanCorrections.sideRoomIDs(portal) where other != from {
                    XCTAssertTrue(offered.contains(other), "\(portal.id): the recorded other side is always offered")
                }
                for id in offered {
                    XCTAssertEqual(home.space(id)?.floorID, portal.floorID)
                }
            }
        }
        // The kid's bedroom does not touch the front door, so it is never offered for it.
        XCTAssertFalse(ScanCorrections.leadsToRooms("pt-front", from: "sp-living", in: home).contains("sp-bed2"))
        XCTAssertEqual(ScanCorrections.leadsToRooms("missing", from: "sp-living", in: home), [])
    }

    func testEveryCardAnswerSequenceRestoresToTheScanAndRoutesRecompute() throws {
        let original = scanned
        let cache = RouteCache()
        let scanRoute = cache.route(request(), in: original)
        XCTAssertNotNil(scanRoute.primary)
        for portal in original.portals {
            guard let from = ScanCorrections.sideRoomIDs(portal).first else { continue }
            let destinations: [PortalDestination] = [.exterior] + ScanCorrections.leadsToRooms(portal.id, from: from, in: original).map { .space($0) }
            for type in ScanCorrections.OpeningType.allCases where type != .notAnOpening {
                for destination in destinations {
                    var home = original
                    home.edit { try? ScanCorrections.setType(portal.id, to: type, in: &$0) }
                    home.edit { try? ScanCorrections.setLeadsTo(portal.id, from: from, to: destination, in: &$0) }
                    home.edit { try? ScanCorrections.setNotUsable(portal.id, true, in: &$0) }
                    let edited = try XCTUnwrap(home.portal(portal.id))
                    XCTAssertEqual(edited.a, portal.a); XCTAssertEqual(edited.b, portal.b, "captured endpoints never move")
                    XCTAssertTrue(ScanCorrections.isNotUsable(edited))
                    // A changed home never serves the scan's cached route; the cache recomputes for the edit.
                    let editedRoute = cache.route(request(), in: home)
                    XCTAssertEqual(editedRoute, EgressPlanner().plan(request(), in: home))
                    XCTAssertTrue(editedRoute.isCurrent(for: home))
                    XCTAssertFalse(scanRoute.isCurrent(for: home))
                    if let path = editedRoute.primary {
                        XCTAssertFalse(path.portalSequence.contains(portal.id), "a not-usable opening is never on the route")
                    }
                    home.edit { try? ScanCorrections.restore(portal.id, in: &$0) }
                    XCTAssertEqual(home.portals, original.portals, "\(portal.id) \(type) → \(destination): restore is exact")
                    XCTAssertEqual(cache.route(request(), in: home).primary, scanRoute.primary, "restored route matches the scan")
                }
            }
        }
    }

    func testNotAnOpeningRemovesFromRoutesAndRestoreBringsItBackInOrder() throws {
        let original = scanned
        var home = original
        try ScanCorrections.setType("pt-bed1-hall", to: .notAnOpening, in: &home)
        XCTAssertNil(home.portal("pt-bed1-hall"))
        let route = EgressPlanner().plan(request(), in: home)
        XCTAssertFalse(route.primary?.portalSequence.contains("pt-bed1-hall") ?? false)
        XCTAssertEqual(ScanCorrections.removedOpenings(home).map(\.id), ["pt-bed1-hall"])
        try ScanCorrections.restore("pt-bed1-hall", in: &home)
        XCTAssertEqual(home.portals.map(\.id), original.portals.map(\.id), "restored in its scanned position")
        XCTAssertEqual(EgressPlanner().plan(request(), in: home).primary, EgressPlanner().plan(request(), in: original).primary)
    }

    func testNotUsableIsReversibleForManualHomesWithoutAScan() throws {
        var home = SampleHomes.ranch
        XCTAssertNil(home.scanSnapshot)
        let before = home.portal("pt-front")
        try ScanCorrections.setNotUsable("pt-front", true, in: &home)
        XCTAssertTrue(ScanCorrections.isNotUsable(home.portal("pt-front")!))
        try ScanCorrections.setNotUsable("pt-front", false, in: &home)
        XCTAssertFalse(ScanCorrections.isNotUsable(home.portal("pt-front")!))
        XCTAssertEqual(home.portal("pt-front")?.kind, before?.kind)
        XCTAssertThrowsError(try ScanCorrections.restore("pt-front", in: &home), "no scan means nothing to restore")
    }

    func testRevertWholeHomeAfterManyEditsMatchesTheScanAndItsRoutes() throws {
        let original = scanned
        var home = original
        for portal in original.portals { try ScanCorrections.setNotUsable(portal.id, true, in: &home) }
        try ScanCorrections.setType("pt-front", to: .window, in: &home)
        try ScanCorrections.setType("pt-bed2-hall", to: .notAnOpening, in: &home)
        home.spaces[0].label = "Renamed"
        try ScanCorrections.revertToScan(&home)
        XCTAssertEqual(ScanSnapshot(home), original.scanSnapshot)
        XCTAssertEqual(home.id, original.id, "identity unchanged")
        for room in original.spaces.map(\.id) {
            XCTAssertEqual(EgressPlanner().plan(request(room), in: home).primary, EgressPlanner().plan(request(room), in: original).primary)
        }
    }

    func testCommittedRoutesFollowTheSavedHomeAndReportMissingStarts() throws {
        let people = [
            Person(id: "p-a", alias: "A", ageBand: .adult, sleepingSpaceID: "sp-bed1"),
            Person(id: "p-b", alias: "B", ageBand: .child, sleepingSpaceID: "sp-bed1"),
            Person(id: "p-c", alias: "C", ageBand: .olderAdult, needs: [.usesWheelchair], sleepingSpaceID: "sp-bed2"),
            Person(id: "p-d", alias: "D", ageBand: .adult),
            Person(id: "p-e", alias: "E", ageBand: .adult, sleepingSpaceID: "sp-gone"),
        ]
        let home = scanned
        let entries = HomeCommittedRoutes.outdoorEgress(people: people, home: home)
        XCTAssertEqual(entries.map(\.personID), people.map(\.id))
        XCTAssertNotNil(entries[0].path)
        XCTAssertEqual(entries[0].path, entries[1].path)
        XCTAssertEqual(entries[2].result?.request.mobility, .wheelchair)
        XCTAssertEqual(entries[3].noRouteReason, .unknownStartSpace)
        XCTAssertEqual(entries[4].noRouteReason, .unknownStartSpace)
        XCTAssertNil(entries[3].result, "no invented starting room")
        XCTAssertEqual(HomeCommittedRoutes.paths(entries).count, Set(entries.compactMap(\.path)).count)

        var blocked = home
        for exit in home.portals where exit.leadsToExterior { try ScanCorrections.setNotUsable(exit.id, true, in: &blocked) }
        let after = HomeCommittedRoutes.outdoorEgress(people: people, home: blocked)
        XCTAssertNil(after[0].path, "the overlay follows the committed home: no usable exit, no line")
        XCTAssertNotNil(after[0].noRouteReason)
        for exit in home.portals where exit.leadsToExterior { try ScanCorrections.setNotUsable(exit.id, false, in: &blocked) }
        XCTAssertEqual(HomeCommittedRoutes.outdoorEgress(people: people, home: blocked).map(\.path), entries.map(\.path))
    }
}
