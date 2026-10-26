import Foundation
import Testing
@testable import DryRunCore

@Suite("Concentrated preparation and home presentation")
struct ConcentratedFlowTests {
    private func recommendation(_ id: String, subject: String? = nil) -> Recommendation {
        Recommendation(actionID: id, tier: .general, titleKey: "title", whyKey: "why", matchedFactIDs: [], causeEventIDs: [], scenarioIDs: [], tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: [], verificationStatus: .needsVerification, subjectID: subject)
    }
    @Test func debriefOpensRecordedFactWithCanonicalIdentityAndExactSubject() {
        for (exercise, prep) in [("act.comms.weather-radio", "prep.radio"), ("act.alerts.enroll-local", "prep.alerts"), ("act.fire.practice-drill", "prep.fireDrill"), ("act.flood.higher-ground-plan", "prep.floodPlan"), ("act.water.well-test-after-flood", "prep.wellFloodPlan"), ("act.water.save-utility-contact", "prep.waterUtility")] {
            let task = NextStep(recommendation: recommendation(prep), sourceScenarioID: "", scenarioIDs: [])
            let summary = NextStepsSummary(toDo: [], completed: [], recorded: [task], unknownFacts: [], scenarioIDs: [])
            #expect(NextSteps.matchingPreparation(for: recommendation(exercise), in: summary) == task)
            #expect(NextSteps.matchingPreparation(for: recommendation(exercise, subject: "different-person"), in: summary) == nil)
            #expect(PreparationPresentation.symbol(actionID: exercise) == PreparationPresentation.symbol(actionID: prep))
        }
        let a = NextStep(recommendation: recommendation("prep.medicalBackup", subject: "equipment.a"), sourceScenarioID: "", scenarioIDs: [])
        let b = NextStep(recommendation: recommendation("prep.medicalBackup", subject: "equipment.b"), sourceScenarioID: "", scenarioIDs: [])
        let summary = NextStepsSummary(toDo: [a], completed: [], recorded: [b], unknownFacts: [], scenarioIDs: [])
        #expect(NextSteps.matchingPreparation(for: recommendation("act.medical.document-runtime", subject: "equipment.b"), in: summary) == b)
        #expect(NextSteps.matchingPreparation(for: recommendation("act.medical.document-runtime", subject: "equipment.deleted"), in: summary) == nil)
    }
    @Test func duplicateRoomNamesStayDistinctAcrossFloors() throws {
        var home = SampleHomes.twoStory
        let lower = try #require(home.spaces.firstIndex { $0.floorID == "fl-ground" })
        let upper = try #require(home.spaces.firstIndex { $0.floorID == "fl-upper" })
        home.spaces[lower].label = "Hall"; home.spaces[upper].label = "Hall"
        let a = HomeScenePresentation.roomLabel(home.spaces[lower].id, in: home)
        let b = HomeScenePresentation.roomLabel(home.spaces[upper].id, in: home)
        #expect(a != b); #expect(a.contains("Hall")); #expect(b.contains("Hall"))
        #expect(a.contains(home.floors.first { $0.id == "fl-ground" }!.label))
        #expect(b.contains(home.floors.first { $0.id == "fl-upper" }!.label))
        #expect(HomeScenePresentation.roomLabel("sp-living", in: SampleHomes.ranch) == SampleHomes.ranch.space("sp-living")?.label)
    }
    @Test func modelAndVisualRouteStatusRetainSharedStairDependencies() throws {
        let home = SampleHomes.twoStory
        var household = SampleHouseholds.oak
        household.people = [household.people[0]]; household.people[0].sleepingSpaceID = "sp-bed1"
        let route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-bed1"), in: home)
        #expect(route.primary != nil); #expect(route.alternative != nil); #expect(route.alternativeStatus == .sharesChokepoint)
        #expect(HomeScenePresentation.alternativeKey(route) == "common.route.shared")
        #expect(HomeScenePresentation.alternativeSymbol(route) != "checkmark.circle")
        let context = HomeSceneContext(home, household: household)
        let summary = try #require(context.planningRoutes?.first)
        #expect(summary.alternativeStatus == .sharesChokepoint)
        #expect(summary.sharedChokepointIDs?.contains("cn-stairs") == true)
        #expect(summary.alternativeConnectorIDs?.contains("cn-stairs") == true)
        #expect(context.planningNeeds?.contains { $0.id.hasPrefix("stairsSingleDependency") } == true)
        // Historical /2 contexts lacking the additive route fields remain decodable; absence is not independence.
        var json = try #require(JSONSerialization.jsonObject(with: DryRunJSON.encoder().encode(context)) as? [String: Any])
        var routes = try #require(json["planningRoutes"] as? [[String: Any]])
        routes[0].removeValue(forKey: "alternativeStatus"); routes[0].removeValue(forKey: "alternativeConnectorIDs"); routes[0].removeValue(forKey: "sharedChokepointIDs"); json["planningRoutes"] = routes
        let old = try DryRunJSON.decoder().decode(HomeSceneContext.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.planningRoutes?.first?.alternativeStatus == nil)
    }
    @Test func markerSuggestionStaysInsideConcaveGeometryAndNeverConfirmsItsLocation() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.spaces.firstIndex { $0.id == "sp-living" })
        home.spaces[index].polygon = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 1), Vec2(1, 1), Vec2(1, 6), Vec2(0, 6)]
        home.spaces[index].usesOutlineWalls = true; home.walls = []; home.obstacles = []
        #expect(!Geometry.contains(home.spaces[index].polygon, Geometry.centroid(home.spaces[index].polygon)))
        let point = try #require(HomeSafetyMarkers.suggestedPosition(roomID: "sp-living", in: home))
        #expect(Geometry.contains(home.spaces[index].polygon, point))
        let marked = try HomeSafetyMarkers.place(id: "panel", kind: .utilityShutoffElectric, roomID: "sp-living", position: point, verified: false, in: home)
        #expect(marked.annotations.first { $0.id == "panel" }?.verification == .proposed)
        var rejected = home; rejected.spaces[index].geometryNeedsReview = true
        #expect(HomeSafetyMarkers.suggestedPosition(roomID: "sp-living", in: rejected) == nil)
        rejected = home; rejected.spaces[index].polygon = [Vec2(0, 0), Vec2(1e9, 0), Vec2(1e9, 1e9), Vec2(0, 1e9)]
        #expect(HomeSafetyMarkers.suggestedPosition(roomID: "sp-living", in: rejected) == nil)
        rejected.spaces[index].polygon = []
        #expect(HomeSafetyMarkers.suggestedPosition(roomID: "sp-living", in: rejected) == nil)
        rejected.spaces[index].polygon = [Vec2(.nan, 0), Vec2(1, 0), Vec2(1, 1)]
        #expect(HomeSafetyMarkers.suggestedPosition(roomID: "sp-living", in: rejected) == nil)
    }
    @Test func markerRelocationRetainsPrivateContextWithoutCreatingShelterCredit() throws {
        var home = SampleHomes.twoStory
        let room = try #require(home.space("sp-bed1"))
        let point = try #require(HomeSafetyMarkers.suggestedPosition(roomID: room.id, in: home))
        let old = try #require(home.annotations.first)
        let i = try #require(home.annotations.firstIndex { $0.id == old.id })
        home.annotations[i].savedPlaceID = "local-binding"
        let moved = try HomeSafetyMarkers.place(id: old.id, kind: .tornadoShelterCandidate, roomID: room.id, position: point, label: "Private", note: "Private note", verified: true, in: home)
        let marker = try #require(moved.annotations.first { $0.id == old.id })
        #expect(marker.floorID == room.floorID); #expect(marker.savedPlaceID == "local-binding")
        #expect(marker.note == "Private note"); #expect(!ShelterSuitability.isConfirmed(roomID: room.id, in: moved))
        #expect(moved.revision == home.revision + 1); #expect(home.annotations[i].position == old.position)
    }
    @Test func apartmentElevatorsCannotReplaceStairsInHostToolsOrFireSimulation() throws {
        var home = SampleHomes.apartmentComplex
        let original = home.connectors
        home.connectors += original.enumerated().map { index, stair in
            var lift = stair; lift.id = "elevator-\(index)"; lift.kind = .elevator; return lift
        }
        let request = RouteRequest(startSpaceID: "sp-bed1")
        let mixed = EgressPlanner().plan(request, in: home)
        #expect(mixed.primary != nil)
        #expect(mixed.primary?.connectorSequence == ["cn-common-upper-stairs", "cn-common-lower-stairs"])
        #expect(mixed.exclusions.filter { $0.reason == "elevatorNotUsedForEgress" }.count == 2)
        var blocked = request; blocked.exclusions.blockedConnectorIDs = original.map(\.id)
        #expect(EgressPlanner().plan(blocked, in: home).primary == nil)
        home.connectors.removeAll { $0.kind != .elevator }
        var household = SampleHouseholds.oak
        household.people = [household.people[0]]; household.people[0].sleepingSpaceID = "sp-bed1"; household.people[0].needs = []
        household.housing.homeType = .apartment
        var input = SimFixtures.input(household, "home-fire", home: home)
        input.spatialOptions = .init(originSpaceID: "sp-kitchen")
        var session = try SimulationSession.initialize(id: "no-elevator-fire", initial: input, library: SimFixtures.library)
        let incident = try #require(SimFixtures.library.scenario("home-fire")?.events.first { $0.id == "evt.home-fire.fire-origin" })
        let receipt = try session.commit(.init(id: "fire", actor: "director", baseRevision: 0, commands: [.init(kind: "startIncident", target: incident.id, value: "sp-kitchen", minute: 0, hazard: .homeFire), .init(kind: "advance", minute: 1)]), library: SimFixtures.library)
        let route = try #require(receipt.routes.first)
        #expect(route.primary == nil)
        #expect(route.exclusions.contains { $0.reason == "elevatorNotUsedForEgress" })
        #expect(try session.query(library: SimFixtures.library) == receipt)
        #expect(session.initial == input)
    }
}
