import Foundation
import Testing
@testable import DryRunCore

@Suite("Manual home layout")
struct SpatialManualLayoutTests {
    @Test func manualHomeBuildsAVerifiedRouteOnlyAfterConfirmation() throws {
        var home = ManualLayout.newHome(id: "home-manual-test")
        let r0 = home.revision
        let bed = try ManualLayout.addRoom(to: &home, label: "Bedroom", kind: .bedroom, width: 3.5, depth: 3.5, attachedTo: "sp-1", side: .north)
        let kitchen = try ManualLayout.addRoom(to: &home, label: "Kitchen", kind: .kitchen, width: 3, depth: 4, attachedTo: "sp-1", side: .east)
        #expect(home.revision == r0 + 2)
        #expect(throws: ManualLayout.LayoutError.overlapsExistingRoom("sp-1")) {
            try ManualLayout.addRoom(to: &home, label: "Bad", kind: .other, width: 2, depth: 2, attachedTo: bed.id, side: .south)
        }
        // Doors land on real shared walls; an exterior door must be on a wall no other room shares.
        try ManualLayout.addPortal(to: &home, from: bed.id, to: .space("sp-1"), width: 0.8, widthMeasured: true, verified: true, operable: true, stepFree: true)
        try ManualLayout.addPortal(to: &home, kind: .opening, from: "sp-1", to: .space(kitchen.id), width: 1.0, widthMeasured: true, verified: true, operable: true, stepFree: true)
        #expect(throws: ManualLayout.LayoutError.sideNotExterior) {
            try ManualLayout.addPortal(to: &home, from: "sp-1", to: .exterior, exteriorSide: .north)
        }
        let front = try ManualLayout.addPortal(to: &home, from: "sp-1", to: .exterior, exteriorSide: .south, width: 0.9)
        #expect(front.verification == .proposed)

        let planner = EgressPlanner()
        #expect(planner.plan(RouteRequest(startSpaceID: bed.id), in: home).noRouteReason == .noVerifiedExteriorExit)

        home.edit { h in
            let i = h.portals.firstIndex { $0.id == front.id }!
            h.portals[i].verification = .verified
            h.portals[i].operable = .confirmed(true)
        }
        let r = planner.plan(RouteRequest(startSpaceID: bed.id), in: home)
        #expect(r.primary?.exitPortalID == front.id)
        #expect(r.primary?.verificationNeeded.contains("\(front.id).clearWidth") == true)
        if let p = r.primary { #expect(RouteGeometryAudit.violations(p, in: home).isEmpty) }
        #expect(!HomeValidator.validate(home).contains { $0.kind == .portalNotOnSharedBoundary })
        #expect(home.source == .manual && !home.isFictional)
    }

    @Test func roomsThatOnlyNearTouchHaveNoSharedWall() {
        let a = Space(id: "a", floorID: "f", label: "A", kind: .other, polygon: SampleHomes.rect(0, 0, 3, 3))
        let b = Space(id: "b", floorID: "f", label: "B", kind: .other, polygon: SampleHomes.rect(3.2, 0, 6, 3))
        let c = Space(id: "c", floorID: "f", label: "C", kind: .other, polygon: SampleHomes.rect(3, 1, 6, 4))
        #expect(ManualLayout.sharedWall(a, b) == nil)
        let s = ManualLayout.sharedWall(a, c)
        #expect(s != nil)
        if let s { #expect(abs(s.0.distance(to: s.1) - 2) < 1e-9) }
        // Corner-only contact is not a shared wall.
        let d = Space(id: "d", floorID: "f", label: "D", kind: .other, polygon: SampleHomes.rect(3, 3, 5, 5))
        #expect(ManualLayout.sharedWall(a, d) == nil)
    }
}
