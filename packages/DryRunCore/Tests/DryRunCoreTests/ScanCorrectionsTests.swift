import XCTest
@testable import DryRunCore

final class ScanCorrectionsTests: XCTestCase {
    /// The sample ranch treated as if RoomPlan had captured it.
    private var scanned: HomeModel {
        var home = SampleHomes.ranch
        home.source = .roomPlanScan
        home.isFictional = false
        // A scanned floor's relation to the ground must be confirmed before its exits count (EgressPlanner).
        for i in home.floors.indices { home.floors[i].exteriorGrade = .ground }
        home.scanSnapshot = ScanSnapshot(home)
        return home
    }
    private func route(_ home: HomeModel, from room: String = "sp-bed1") -> RouteResult {
        EgressPlanner().plan(RouteRequest(startSpaceID: room), in: home)
    }

    func testEveryReclassificationRoundTripsAndRestoreMatchesTheScan() throws {
        let original = scanned
        for portal in original.portals {
            for first in ScanCorrections.OpeningType.allCases {
                for second in ScanCorrections.OpeningType.allCases {
                    var home = original
                    try? ScanCorrections.setType(portal.id, to: first, in: &home)
                    try? ScanCorrections.setType(portal.id, to: second, in: &home)
                    if let current = home.portal(portal.id) {
                        XCTAssertEqual(ScanCorrections.type(of: current), second == .notAnOpening ? ScanCorrections.type(of: current) : second)
                        XCTAssertEqual(current.a, portal.a); XCTAssertEqual(current.b, portal.b, "endpoints never move")
                        XCTAssertEqual(current.sideA, portal.sideA); XCTAssertEqual(current.sideB, portal.sideB)
                    } else {
                        XCTAssertTrue(first == .notAnOpening || second == .notAnOpening)
                    }
                    try ScanCorrections.restore(portal.id, in: &home)
                    XCTAssertEqual(home.portals, original.portals, "restore returns exactly what the scan saw (\(portal.id) \(first)→\(second))")
                }
            }
        }
    }

    func testWindowNeverBecomesAnExitByReclassificationAndFactsReset() throws {
        var home = scanned
        let door = try XCTUnwrap(home.portals.first { $0.kind == .door && $0.leadsToExterior })
        try ScanCorrections.setType(door.id, to: .window, in: &home)
        let window = try XCTUnwrap(home.portal(door.id))
        XCTAssertEqual(window.kind, .window)
        XCTAssertEqual(window.operable, .unknown)
        XCTAssertNil(window.emergencyEscapeConfirmed)
    }

    func testLeadsToAndNotUsableAreReversibleAndRoutesRecompute() throws {
        var home = scanned
        let before = route(home)
        XCTAssertNotNil(before.primary, "the scanned ranch has a route out: \(String(describing: before.noRouteReason))")
        let exits = home.portals.filter { $0.leadsToExterior && $0.kind != .window }
        for exit in exits { try ScanCorrections.setNotUsable(exit.id, true, in: &home) }
        XCTAssertTrue(exits.allSatisfy { ScanCorrections.isNotUsable(home.portal($0.id)!) })
        XCTAssertNil(route(home).primary, "with every exit marked not usable there is no route")
        for exit in exits { try ScanCorrections.setNotUsable(exit.id, false, in: &home) }
        XCTAssertEqual(home.portals, scanned.portals, "Not usable is fully reversible")
        XCTAssertEqual(route(home).primary, before.primary)

        // Leads to: point an interior door outside, then back.
        let interior = try XCTUnwrap(home.portals.first { !$0.leadsToExterior && $0.kind == .door })
        guard case .space(let room) = interior.sideA, case .space(let other) = interior.sideB else { return XCTFail() }
        try ScanCorrections.setLeadsTo(interior.id, from: room, to: .exterior, in: &home)
        XCTAssertTrue(home.portal(interior.id)!.leadsToExterior)
        XCTAssertEqual(home.portal(interior.id)!.verification, .verified)
        try ScanCorrections.setLeadsTo(interior.id, from: room, to: .space(other), in: &home)
        XCTAssertEqual(home.portal(interior.id)!.sideB, .space(other))
        XCTAssertThrowsError(try ScanCorrections.setLeadsTo(interior.id, from: room, to: .space(room), in: &home))
    }

    func testRevertWholeHomeAndRemovedOpenings() throws {
        var home = scanned
        let removed = home.portals[0].id
        try ScanCorrections.setType(removed, to: .notAnOpening, in: &home)
        try ScanCorrections.setType(home.portals[0].id, to: .openDoorway, in: &home)
        XCTAssertEqual(ScanCorrections.removedOpenings(home).map(\.id), [removed])
        try ScanCorrections.revertToScan(&home)
        XCTAssertEqual(ScanSnapshot(home), scanned.scanSnapshot)
        XCTAssertEqual(home.scanSnapshot, scanned.scanSnapshot, "the snapshot itself never changes")
        var manual = SampleHomes.ranch
        XCTAssertThrowsError(try ScanCorrections.revertToScan(&manual))
        XCTAssertEqual(route(home).primary, route(scanned).primary)
    }

    func testUncertainOpeningsAreTheUnverifiedOnes() {
        var home = scanned
        for i in home.portals.indices where i % 2 == 0 { home.portals[i].verification = .proposed }
        let uncertain = ScanCorrections.uncertainOpenings(home)
        XCTAssertEqual(Set(uncertain.map(\.id)), Set(home.portals.filter { $0.verification != .verified }.map(\.id)))
    }

    func testHistoryKeepsTwentyVersionsAndRedoBranches() {
        var history = HomeEditHistory(homeID: SampleHomes.ranch.id)
        var current = SampleHomes.ranch
        for n in 1...25 {
            let previous = current
            current.label = "v\(n)"
            history.recordSave(replacing: previous)
        }
        XCTAssertEqual(history.undoStack.count, 20)
        let undone = history.undo(from: current)
        XCTAssertEqual(undone?.label, "v24")
        XCTAssertEqual(history.redo(from: undone!)?.label, "v25")
        _ = history.undo(from: current)
        history.recordSave(replacing: current)
        XCTAssertFalse(history.canRedo, "a new save discards the redo branch")
        var other = HomeEditHistory(homeID: "another-home")
        other.recordSave(replacing: current)
        XCTAssertFalse(other.canUndo, "history is per home")
    }

    func testScanImportFreezesTheSnapshot() throws {
        XCTAssertNil(SampleHomes.ranch.scanSnapshot)
        let encoded = try JSONEncoder().encode(SampleHomes.ranch)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("scanSnapshot"), "existing homes encode exactly as before")
    }
}
