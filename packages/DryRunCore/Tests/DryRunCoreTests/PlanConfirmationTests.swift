import Foundation
import Testing
@testable import DryRunCore

@Suite("Guided home confirmation")
struct PlanConfirmationTests {
    /// Two rooms from a "scan": everything proposed, front opening leads somewhere unknown.
    static func scanned() -> HomeModel {
        HomeModel(
            id: "home-scan", label: "Scan", source: .roomPlanScan,
            floors: [Floor(id: "f0", level: 0, label: "Ground", exteriorGrade: .ground)],
            spaces: [
                Space(id: "s1", floorID: "f0", label: "Room 1", kind: .other,
                      polygon: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 3), Vec2(0, 3)], labelConfirmed: false),
                Space(id: "s2", floorID: "f0", label: "Room 2", kind: .other,
                      polygon: [Vec2(4, 0), Vec2(8, 0), Vec2(8, 3), Vec2(4, 3)], labelConfirmed: false),
            ],
            portals: [
                Portal(id: "p-int", floorID: "f0", kind: .door, a: Vec2(4, 1), b: Vec2(4, 2), sideA: .space("s1"), sideB: .space("s2"),
                       clearWidthMeters: .scanned(0.9, unit: "m"), operable: .scanned(true), verification: .proposed),
                Portal(id: "p-out", floorID: "f0", kind: .door, a: Vec2(8, 1), b: Vec2(8, 2), sideA: .space("s2"), sideB: .unknown,
                       verification: .proposed),
                Portal(id: "p-win", floorID: "f0", kind: .window, a: Vec2(1, 0), b: Vec2(2, 0), sideA: .space("s1"), sideB: .unknown,
                       verification: .proposed),
            ],
            completeness: .incomplete)
    }

    @Test("A scanned home has no verified route until the household answers the confirmation steps")
    func scanNeedsConfirmation() {
        var home = Self.scanned()
        let planner = EgressPlanner()
        #expect(planner.plan(RouteRequest(startSpaceID: "s1"), in: home).primary == nil)
        let steps = HomeConfirmation.steps(for: home)
        #expect(steps.filter { $0.kind == .labelSpace }.count == 2)
        #expect(steps.filter { $0.kind == .confirmPortal }.map(\.elementID) == ["p-int", "p-out", "p-win"])
        #expect(steps.contains { $0.kind == .meetingPoint })

        let rev0 = home.revision
        home = HomeConfirmation.apply(.confirmPortal(portalID: "p-int", operable: true, stepFree: true, clearWidthMeters: 0.9), to: home)
        home = HomeConfirmation.apply(.markPortalExterior(portalID: "p-out", operable: true, stepFree: true), to: home)
        #expect(home.revision > rev0, "every confirmation bumps the revision so cached routes/plans invalidate")
        let route = planner.plan(RouteRequest(startSpaceID: "s1"), in: home)
        #expect(route.primary?.exitPortalID == "p-out")
        #expect(route.homeRevision == home.revision)
    }

    @Test("An unresolved interior side can be assigned without claiming operability, and measured exterior width is retained")
    func assignInteriorAndMeasureExterior() {
        var home = Self.scanned()
        home = HomeConfirmation.apply(.assignPortalInterior(portalID: "p-out", spaceID: "s1"), to: home)
        #expect(home.portal("p-out")?.sideB == .space("s1"))
        #expect(home.portal("p-out")?.verification == .proposed)
        #expect(home.portal("p-out")?.operable.value == nil)

        // Recreate an unresolved exit; the measured constructor uses the same call shape as the UI.
        home.portals[1].sideB = .unknown
        home = HomeConfirmation.apply(.markPortalExteriorMeasured(portalID: "p-out", operable: true, stepFree: true,
                                                                   clearWidthMeters: 0.86), to: home)
        #expect(home.portal("p-out")?.clearWidthMeters.value == 0.86)
        #expect(home.portal("p-out")?.verification == .verified)

        var evidence = Self.scanned()
        evidence = HomeConfirmation.apply(.confirmPortalEvidence(portalID: "p-int", operable: nil, stepFree: nil,
                                                                  clearWidthMeters: 0.91), to: evidence)
        #expect(evidence.portal("p-int")?.operable.value == nil)
        #expect(evidence.portal("p-int")?.stepFree.value == nil)
        #expect(evidence.portal("p-int")?.clearWidthMeters.value == 0.91)
        evidence = HomeConfirmation.apply(.markPortalExteriorEvidence(portalID: "p-out", operable: nil, stepFree: nil,
                                                                       clearWidthMeters: 0.86), to: evidence)
        #expect(evidence.portal("p-out")?.operable.value == nil)
        #expect(evidence.portal("p-out")?.clearWidthMeters.value == 0.86)

        var unresolved = home
        unresolved.portals[1].sideA = .unknown
        unresolved.portals[1].sideB = .unknown
        let unchanged = HomeConfirmation.apply(.markPortalExteriorMeasured(portalID: "p-out", operable: true,
                                                                            stepFree: true, clearWidthMeters: 0.86), to: unresolved)
        #expect(unchanged == unresolved, "outside confirmation still needs the room side")
    }

    @Test("Skipping leaves an opening unknown and out of every route; windows are never made walking exits by a door answer")
    func skipAndWindows() {
        var home = Self.scanned()
        home = HomeConfirmation.apply(.skip(elementID: "p-out"), to: home)
        #expect(home == Self.scanned(), "skip changes nothing")
        // confirmPortal requires both sides known; it cannot turn an unknown-destination window into an exit.
        home = HomeConfirmation.apply(.confirmPortal(portalID: "p-win", operable: true, stepFree: nil, clearWidthMeters: nil), to: home)
        #expect(home.portal("p-win")?.verification == .proposed)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "s1"), in: home).primary == nil)
    }

    @Test("Rejected doors never route; upper-floor openings cannot be marked as exits")
    func rejectAndUpperFloor() {
        var home = Self.scanned()
        home = HomeConfirmation.apply(.confirmPortal(portalID: "p-int", operable: true, stepFree: true, clearWidthMeters: 0.9), to: home)
        home = HomeConfirmation.apply(.markPortalExterior(portalID: "p-out", operable: true, stepFree: true), to: home)
        home = HomeConfirmation.apply(.rejectPortal(portalID: "p-out"), to: home)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "s1"), in: home).primary == nil)

        var upper = Self.scanned()
        upper.floors = [Floor(id: "f0", level: 0, label: "Ground"), Floor(id: "f1", level: 1, label: "Upstairs", elevationMeters: 2.7)]
        upper.portals[1].floorID = "f1"
        let after = HomeConfirmation.apply(.markPortalExterior(portalID: "p-out", operable: true, stepFree: true), to: upper)
        #expect(after == upper, "an upper-floor opening is never a walking exit")
    }

    @Test("Meeting point and shelter spot become verified only through explicit answers; shelter carries the not-engineered note")
    func meetingAndShelter() {
        var home = Self.scanned()
        home = HomeConfirmation.apply(.meetingPoint(label: "   "), to: home)
        #expect(home.meetingPoint == nil)
        home = HomeConfirmation.apply(.meetingPoint(label: "Neighbor's oak tree (fictional)"), to: home)
        #expect(home.meetingPoint?.verification == .verified)
        #expect(HomeConfirmation.apply(.shelterSpot(spaceID: "s1", interiorNoWindows: true), to: home) == home,
            "The recorded window contradicts a no-window shelter answer")
        home = HomeConfirmation.apply(.shelterSpot(spaceID: "s2", interiorNoWindows: true), to: home)
        let shelter = home.annotations.first { $0.kind == .tornadoShelterCandidate }
        #expect(shelter?.note?.contains("not an engineered safe room") == true)
        #expect(!HomeConfirmation.steps(for: home).contains { $0.kind == .meetingPoint || $0.kind == .shelterSpot })
    }
}
