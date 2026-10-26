import Testing
@testable import DryRunCore

@Suite("Opening classification corrections")
struct OpeningReclassificationTests {
    @Test func correctionPreservesCaptureButCannotReuseDoorEscapeEvidenceForWindow() throws {
        var home = ManualLayout.newHome(id: "opening-correction", width: 4, depth: 4)
        _ = try ManualLayout.addPortal(to: &home, from: "sp-1", to: .exterior, exteriorSide: .south,
            width: 0.9, widthMeasured: true, verified: true, operable: true, stepFree: true)
        home.portals[0].emergencyEscapeConfirmed = true
        home.portals[0].emergencyEscapePersonIDs = ["person"]
        let original = home
        try HomeGeometryEditor.reclassifyOpening(in: &home, portalID: original.portals[0].id, kind: .window)
        let corrected = home.portals[0], captured = original.portals[0]
        #expect(corrected.id == captured.id && corrected.a == captured.a && corrected.b == captured.b)
        #expect(corrected.sideA == captured.sideA && corrected.sideB == captured.sideB)
        #expect(corrected.clearWidthMeters == captured.clearWidthMeters && corrected.stepFree == captured.stepFree)
        #expect(corrected.emergencyEscapeConfirmed == nil && corrected.emergencyEscapePersonIDs == nil)
        #expect(home.revision == original.revision + 1)
        #expect(HomeGeometryEditor.requiresNewEscapeCheck(previous: original, updated: home))
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "sp-1"), in: home).primary == nil)
        let unchanged = home
        try HomeGeometryEditor.reclassifyOpening(in: &home, portalID: corrected.id, kind: .window)
        #expect(home == unchanged)
        #expect(throws: HomeGeometryEditor.CorrectionError.unknownPortal) {
            try HomeGeometryEditor.reclassifyOpening(in: &home, portalID: "missing", kind: .door)
        }
        #expect(home == unchanged)
    }

    @Test func aNewDoorCannotInheritOpenDoorwayOperability() throws {
        var home = ManualLayout.newHome(id: "doorway-correction", width: 4, depth: 4)
        _ = try ManualLayout.addPortal(to: &home, kind: .opening, from: "sp-1", to: .exterior,
            exteriorSide: .south, width: 0.9, widthMeasured: true, verified: true, operable: true, stepFree: true)
        try HomeGeometryEditor.reclassifyOpening(in: &home, portalID: home.portals[0].id, kind: .door)
        #expect(home.portals[0].operable.value == nil)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "sp-1"), in: home).primary == nil)
    }
}
