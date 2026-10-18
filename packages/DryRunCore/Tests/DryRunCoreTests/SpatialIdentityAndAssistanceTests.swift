import Foundation
import Testing
@testable import DryRunCore

@Suite("Spatial identity and assistance")
struct SpatialIdentityAndAssistanceTests {
    @Test("Window suitability is person-specific and a legacy generic answer cannot authorize anyone")
    func windows() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.portals.firstIndex { $0.id == "pt-win-bed1" })
        home.portals[index].verification = .verified
        home.portals[index].operable = .confirmed(true)
        home.portals[index].emergencyEscapeConfirmed = true
        let exclusions = ScenarioExclusions(blockedPortalIDs: ["pt-front", "pt-back"])
        func route(_ personID: String?) -> RouteResult {
            EgressPlanner().plan(.init(personID: personID, startSpaceID: "sp-bed1", exclusions: exclusions), in: home)
        }
        #expect(route("adult").primary == nil)
        let legacy = try JSONDecoder().decode(HomeModel.self, from: JSONEncoder().encode(home))
        #expect(legacy.portals[index].emergencyEscapeConfirmed == true)
        #expect(legacy.portals[index].emergencyEscapePersonIDs == nil)
        home.portals[index].emergencyEscapePersonIDs = ["adult"]
        #expect(route("adult").primary?.exitPortalID == "pt-win-bed1")
        #expect(route("child").primary == nil && route(nil).primary == nil)
        let roundTrip = try JSONDecoder().decode(HomeModel.self, from: JSONEncoder().encode(home))
        #expect(roundTrip.portals[index].emergencyEscapePersonIDs == ["adult"])
        try HomeGeometryEditor.placeOpening(in: &home, portalID: "pt-win-bed1", from: "sp-bed1", to: .exterior, exteriorSide: .north)
        #expect(home.portals[index].emergencyEscapePersonIDs == nil)
    }

    @Test("Helper routes obey attachment, width, corrected geometry and helper mobility")
    func helpers() throws {
        var base = SampleHomes.ranch
        base.obstacles = []
        let index = try #require(base.portals.firstIndex { $0.id == "pt-bed1-hall" })
        let planner = EgressPlanner()
        let request = RouteRequest(personID: "helper", startSpaceID: "sp-bed1", purpose: .helperReach, destinationSpaceID: "sp-bed2")
        #expect(planner.plan(request, in: base).primary?.spaceSequence.last == "sp-bed2")
        var detached = base
        detached.portals[index].a = Vec2(100, 100); detached.portals[index].b = Vec2(101, 100)
        #expect(planner.plan(request, in: detached).primary == nil)
        var narrow = base; narrow.portals[index].clearWidthMeters = .confirmed(0.3)
        #expect(planner.plan(request, in: narrow).primary == nil)
        var corrected = base
        corrected.spaces[corrected.spaces.firstIndex { $0.id == "sp-hall" }!].geometryNeedsReview = true
        #expect(planner.plan(request, in: corrected).primary == nil)

        let twoStory = SampleHomes.twoStory
        let connector = try #require(twoStory.connectors.first)
        var stairRequest = RouteRequest(startSpaceID: connector.fromSpaceID, purpose: .helperReach, destinationSpaceID: connector.toSpaceID)
        #expect(planner.plan(stairRequest, in: twoStory).primary != nil)
        stairRequest.mobility = .wheelchair
        #expect(planner.plan(stairRequest, in: twoStory).primary == nil)
        var offset = twoStory; offset.connectors[0].toPoint = Vec2(999, 999)
        stairRequest.mobility = .walking
        #expect(planner.plan(stairRequest, in: offset).primary == nil)
    }

    @Test("A detached portal cannot suppress the rehearsal's blocked-helper preparation")
    func helperRehearsal() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.portals.firstIndex { $0.id == "pt-bed1-hall" })
        home.portals[index].a = Vec2(100, 100); home.portals[index].b = Vec2(101, 100)
        let result = try SimFixtures.run(SampleHouseholds.oak, "home-fire", home: home)
        #expect(result.events.contains { $0.id == "evt.home-fire.assist.helper-blocked.p-oak-3" })
        #expect(result.snapshots.contains { $0.unmetRequirements.contains("req.assistance.reach.p-oak-3") })
    }

    @Test("Room ordinal collisions do not preserve occupant assignments across unrelated captures")
    func scanAssociations() throws {
        var previous = SampleHomes.ranch
        previous.source = .roomPlanScan
        previous.sourceCaptureFrameID = "frame-one"
        for index in previous.spaces.indices { previous.spaces[index].sourceScanRoomID = "source-\(index)" }
        let oldID = previous.spaces[0].id
        var reordered = previous
        reordered.spaces[0].id = "reordered-room"
        reordered.spaces.reverse()
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: previous, to: reordered) == "reordered-room")
        var unrelated = previous
        unrelated.sourceCaptureFrameID = "different-frame"
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: previous, to: unrelated) == nil)
        var duplicate = previous; duplicate.spaces[1].sourceScanRoomID = previous.spaces[0].sourceScanRoomID
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: previous, to: duplicate) == nil)
        var legacy = previous; legacy.sourceCaptureFrameID = nil
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: legacy, to: legacy) == oldID)
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: legacy, to: unrelated) == nil)
        var swappedLegacy = legacy; swappedLegacy.spaces[0].polygon = legacy.spaces[1].polygon
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: legacy, to: swappedLegacy) == nil)
        #expect(HomeRoomAssociations.remappedRoomID(oldID, from: nil, to: previous) == nil)
    }

    @Test("Scan import retains originating frame and room evidence when capture order changes")
    func importedLineage() throws {
        var capture = GeometryTests.capture
        capture.coordinateFrameID = "shared-capture-frame"
        let original = try ScanImport.importCapture(capture, homeID: "stable-home").home
        capture.rooms.reverse()
        let reordered = try ScanImport.importCapture(capture, homeID: "stable-home").home
        #expect(original.sourceCaptureFrameID == "shared-capture-frame")
        #expect(original.spaces[0].sourceScanRoomID == "A")
        let remappedID = HomeRoomAssociations.remappedRoomID("sp-scan-1", from: original, to: reordered)
        #expect(remappedID == "sp-scan-2")
        let remapped = try #require(remappedID.flatMap(reordered.space))
        #expect(remapped.sourceScanRoomID == "A" && remapped.polygon == original.spaces[0].polygon)
        #expect(reordered.space("sp-scan-1")?.sourceScanRoomID == "B")
        capture.coordinateFrameID = "unrelated-capture-frame"
        let unrelated = try ScanImport.importCapture(capture, homeID: "stable-home").home
        #expect(HomeRoomAssociations.remappedRoomID("sp-scan-1", from: original, to: unrelated) == nil)
        let decoded = try JSONDecoder().decode(HomeModel.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("A local leak has its own choices and never borrows regional road, utility, well or evacuation effects")
    func householdLeak() throws {
        var input = SimFixtures.input(SampleHouseholds.oak, "flash-flood", variants: ["home-flooded"])
        input.spatialOptions = .init(floodAffectedSpaceIDs: ["sp-kitchen"], floodIsHouseholdLeak: true, refugeSpaceID: "sp-bed1")
        let leak = try SimFixtures.engine.run(input)
        #expect(leak == (try SimFixtures.engine.run(input)))
        #expect(leak.decisions.count == 2)
        #expect(leak.decisions.allSatisfy { $0.id.hasPrefix("choice.household-leak.") })
        #expect(!leak.events.contains { $0.id.hasPrefix("evt.flash-flood.") })
        #expect(leak.snapshots.allSatisfy { $0.services[Svc.grid] == .operational && $0.services[Svc.roads] == .operational })
        #expect(leak.routes.isEmpty)
        let scene = try #require(leak.snapshots.last?.spatialState)
        #expect(scene.affectedSpaceIDs == ["sp-kitchen"] && scene.destinationSpaceID == nil)
        #expect(!leak.recommendations.contains { $0.actionID == "act.water.well-test-after-flood" })
        #expect(leak.decisions.flatMap(\.options).filter { ["enter-water", "touch-electrics"].contains($0.id) }.allSatisfy { !$0.isRecommended })
        var variantInput = input; variantInput.spatialOptions = nil
        variantInput.variants = ["householdLeak", "waterEntry:sp-kitchen"]
        let variantResult = try SimFixtures.engine.run(variantInput)
        #expect(variantResult.events == leak.events && variantResult.decisions == leak.decisions)
        let regional = try SimFixtures.run(SampleHouseholds.oak, "flash-flood")
        #expect(regional.events.contains { $0.id == "evt.flash-flood.no-crossing" })
        #expect(regional.events.contains { $0.id == "evt.flash-flood.well-quality-unknown" })
        #expect(regional.snapshots.contains { $0.services[Svc.grid] == .unavailable })
    }
}
