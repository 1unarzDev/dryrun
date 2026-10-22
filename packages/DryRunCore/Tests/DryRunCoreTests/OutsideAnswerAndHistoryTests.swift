import XCTest
@testable import DryRunCore

/// HOME-01 wave 2: "Outside" is offered only for an opening in an outside wall; an outside answer the geometry
/// contradicts stays a proposal and never becomes a usable exit. Saved-version history persists in the sidecar.
/// F4: an example family's home carries no other family's medical-equipment marker.
final class OutsideAnswerAndHistoryTests: XCTestCase {
    private var scanned: HomeModel {
        var home = SampleHomes.ranch
        home.source = .roomPlanScan
        home.isFictional = false
        for i in home.floors.indices { home.floors[i].exteriorGrade = .ground }
        home.scanSnapshot = ScanSnapshot(home)
        return home
    }

    func testOutsideOfferedExactlyForOutsideWallOpeningsOfEverySampleHome() {
        for home in SampleHomes.all + [SampleHomes.scannedRanch] {
            for portal in home.portals {
                let rooms = ScanCorrections.sideRoomIDs(portal)
                if rooms.count == 2 {
                    XCTAssertFalse(ScanCorrections.canLeadOutside(portal.id, in: home), "\(home.id)/\(portal.id): interior opening")
                }
                if portal.leadsToExterior {
                    XCTAssertTrue(ScanCorrections.canLeadOutside(portal.id, in: home), "\(home.id)/\(portal.id): outside-wall opening")
                    XCTAssertFalse(PortalAttachment.exteriorClaimContradictsGeometry(portal, in: home), "\(home.id)/\(portal.id)")
                }
            }
        }
        XCTAssertFalse(ScanCorrections.canLeadOutside("missing", in: SampleHomes.ranch))
    }

    func testInteriorDoorAnsweredOutsideStaysUnverifiedAndOffEveryRoute() throws {
        let original = scanned
        var home = original
        XCTAssertFalse(ScanCorrections.canLeadOutside("pt-living-hall", in: home))
        let confirmed = try ScanCorrections.setLeadsTo("pt-living-hall", from: "sp-living", to: .exterior, in: &home)
        XCTAssertFalse(confirmed)
        let portal = try XCTUnwrap(home.portal("pt-living-hall"))
        XCTAssertTrue(portal.leadsToExterior, "the family's answer is kept")
        XCTAssertEqual(portal.verification, .proposed, "but it needs checking")
        XCTAssertTrue(ScanCorrections.outsideNeedsCheck(portal, in: home))
        XCTAssertEqual(HomeScenePresentation.openingStatus(portal, in: home), .unconfirmed)
        XCTAssertTrue(HomeValidator.validate(home).contains { $0.kind == .portalUnverified && $0.elementID == "pt-living-hall" })
        // "That's right" in Check your scan cannot verify it either.
        XCTAssertFalse(try ScanCorrections.confirm("pt-living-hall", in: &home))
        XCTAssertEqual(home.portal("pt-living-hall")?.verification, .proposed)
        for room in home.spaces.map(\.id) {
            let route = EgressPlanner().plan(RouteRequest(startSpaceID: room), in: home)
            XCTAssertNotEqual(route.primary?.exitPortalID, "pt-living-hall", room)
            XCTAssertNotEqual(route.alternative?.exitPortalID, "pt-living-hall", room)
        }
        // Answering a room again confirms the connection as before.
        XCTAssertTrue(try ScanCorrections.setLeadsTo("pt-living-hall", from: "sp-living", to: .space("sp-hall"), in: &home))
        XCTAssertEqual(home.portal("pt-living-hall")?.verification, .verified)
    }

    func testPreviouslySavedVerifiedOutsideAnswerOnInteriorDoorIsNotAnExit() throws {
        // A home saved by the earlier editor: interior door verified as leading outside.
        var home = scanned
        let index = try XCTUnwrap(home.portals.firstIndex { $0.id == "pt-living-hall" })
        home.portals[index].sideB = .exterior
        home.portals[index].verification = .verified
        let portal = home.portals[index]
        XCTAssertEqual(HomeScenePresentation.openingStatus(portal, in: home), .unconfirmed, "never drawn as a usable exit")
        XCTAssertTrue(HomeValidator.validate(home).contains { $0.kind == .portalUnverified && $0.elementID == portal.id })
        let route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-living"), in: home)
        XCTAssertNotEqual(route.primary?.exitPortalID, portal.id)
        XCTAssertTrue(route.exclusions.contains { $0.elementID == portal.id && $0.reason.hasPrefix("portalNotVerified") })
        XCTAssertEqual(route.algorithmVersion, "egress-portal-graph/3")
    }

    func testOutsideWallOpeningAnsweredOutsideIsConfirmed() throws {
        var home = scanned
        XCTAssertTrue(ScanCorrections.canLeadOutside("pt-front", in: home))
        XCTAssertTrue(try ScanCorrections.setLeadsTo("pt-front", from: "sp-living", to: .exterior, in: &home))
        XCTAssertEqual(home.portal("pt-front")?.verification, .verified)
        XCTAssertTrue(try ScanCorrections.confirm("pt-front", in: &home))
    }

    func testOneRoomScanOpeningStillOffersOutside() throws {
        // A scanned opening with one room against it (other side unknown) may be an outside door.
        var home = scanned
        let index = try XCTUnwrap(home.portals.firstIndex { $0.id == "pt-back" })
        home.portals[index].sideB = .unknown
        home.portals[index].verification = .proposed
        XCTAssertTrue(ScanCorrections.canLeadOutside("pt-back", in: home))
        XCTAssertTrue(try ScanCorrections.setLeadsTo("pt-back", from: "sp-kitchen", to: .exterior, in: &home))
    }

    func testHomeEditHistoryRoundTripsThroughTheSidecarAndHistoricalStateDecodes() throws {
        let v1 = SampleHomes.ranch
        var v2 = v1; v2.revision += 1; v2.spaces[0].label = "Front room"
        var v3 = v2; v3.revision += 1; v3.spaces[1].label = "Galley"
        var history = HomeEditHistory(homeID: v1.id)
        history.recordSave(replacing: v1)
        history.recordSave(replacing: v2)
        _ = history.undo(from: v3)
        var state = IntegratedAIState()
        let emptyBytes = try DryRunJSON.encoder().encode(state)
        XCTAssertFalse(String(decoding: emptyBytes, as: UTF8.self).contains("homeEditHistories"), "nil is omitted: existing bytes unchanged")
        state.setHomeEditHistory(history)
        let decoded = try DryRunJSON.decoder().decode(IntegratedAIState.self, from: DryRunJSON.encoder().encode(state))
        let restored = try XCTUnwrap(decoded.homeEditHistory(for: v1.id))
        XCTAssertEqual(restored, history)
        XCTAssertTrue(restored.canUndo); XCTAssertTrue(restored.canRedo)
        XCTAssertNil(decoded.homeEditHistory(for: "other-home"))
        // Historical sidecar without the field still decodes.
        let historical = try DryRunJSON.decoder().decode(IntegratedAIState.self, from: emptyBytes)
        XCTAssertNil(historical.homeEditHistories)
        // An empty history is not stored.
        state.setHomeEditHistory(HomeEditHistory(homeID: v1.id))
        XCTAssertNil(state.homeEditHistories)
    }

    func testHomeEditHistoryIsNeverInProviderContext() throws {
        var history = HomeEditHistory(homeID: SampleHouseholds.oak.stableHomeID)
        var previous = SampleHomes.ranch; previous.id = SampleHouseholds.oak.stableHomeID
        previous.spaces[0].label = "HISTORY-ONLY-LABEL"
        history.recordSave(replacing: previous)
        var state = IntegratedAIState(); state.setHomeEditHistory(history)
        var home = SampleHomes.ranch; home.id = SampleHouseholds.oak.stableHomeID
        let context = try AuthorizedAIContext(household: SampleHouseholds.oak, home: home, state: state, sessionID: "history", cloudPlanningConsent: true)
        let bytes = String(decoding: try DryRunJSON.encoder().encode(context), as: UTF8.self)
        XCTAssertFalse(bytes.contains("HISTORY-ONLY-LABEL"))
        XCTAssertFalse(bytes.contains("homeEditHistories"))
    }

    func testExampleHomeKeepsMedicalMarkerOnlyForTheFamilyWhoseEquipmentItDepicts() {
        let oak = SampleHomes.forExampleHousehold(SampleHomes.ranch, SampleHouseholds.oak)
        XCTAssertTrue(oak.annotations.contains { $0.id == "an-medical" }, "Oak records an oxygen concentrator")
        for family in [SampleHouseholds.lake, SampleHouseholds.pine] {
            let home = SampleHomes.forExampleHousehold(SampleHomes.ranch, family)
            XCTAssertFalse(home.annotations.contains { $0.kind == .medicalEquipment }, family.id)
            XCTAssertEqual(home.annotations.count, SampleHomes.ranch.annotations.count - 1, "other markers unchanged")
            XCTAssertEqual(home.portals, SampleHomes.ranch.portals)
        }
        // Personal homes are never changed.
        var personal = SampleHomes.ranch; personal.isFictional = false
        XCTAssertEqual(SampleHomes.forExampleHousehold(personal, SampleHouseholds.lake), personal)
    }
}
