import Foundation
import Testing
@testable import DryRunCore

@Suite("Coordinated phone and print home panels")
struct PlanHomePanelTests {
    @Test("Every route floor and exact alternative legs share the same qualified panel contract")
    func exactLegsAndFloors() throws {
        let home = SampleHomes.twoStory
        let household = SampleHouseholds.oak
        var route = EgressPlanner().plan(RouteRequest(personID: household.people[0].id, startSpaceID: "sp-bed1"), in: home)
        let primary = try #require(route.primary)
        // An exact alternate geometry is retained; the render contract does not plan or smooth it anew.
        route.alternative = primary
        route.alternativeStatus = .sharesChokepoint
        let state = SpatialExerciseState(hazard: .homeFire, seed: 42, stageID: "current", affectedSpaceIDs: ["sp-kitchen"], affectedPortalIDs: ["closed-opening"], routes: [route], assumption: "Authored scene")
        var result = PlanBuilderTests.fakeResult("home-fire", household: household, home: home, routes: [route])
        result.snapshots = [SimulationSnapshot(simMinute: 3, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: state)]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let doc = PlanBuilder.build(household: household, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
            let snapshot = try #require(doc.visualSnapshot)
            let panels = snapshot.homePanels.filter { $0.route != nil }
            #expect(Set(panels.map(\.floorID)) == Set(primary.legs.map(\.floorID)))
            #expect(panels.allSatisfy { $0.paths == [primary, primary] && $0.spatialState == state && $0.scenarioID == "home-fire" })
            #expect(panels.allSatisfy { $0.title(in: snapshot).contains(l("common.scenario.home-fire")) })
            #expect(panels.allSatisfy { snapshot.panelDetails?[$0.id] == $0.details(in: snapshot, localizer: l) })
            #expect(snapshot.homePanels.filter { $0.scenarioID == nil }.count == home.floors.count)
            #expect(try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(doc)) == doc)
        }
    }

    @Test("Failed current paths preserve exclusions and explanations without reviving route history")
    func failedCurrentScene() throws {
        let home = SampleHomes.ranch, household = SampleHouseholds.oak
        let earlier = EgressPlanner().plan(RouteRequest(personID: household.people[0].id, startSpaceID: "sp-bed1"), in: home)
        #expect(earlier.primary != nil)
        var current = earlier
        current.primary = nil; current.alternative = nil; current.alternativeStatus = .none; current.noRouteReason = .blockedByScenario
        let state = SpatialExerciseState(hazard: .homeFire, seed: 7, stageID: "blocked", affectedSpaceIDs: ["sp-hall"], routes: [current], assumption: "Authored blockage")
        var result = PlanBuilderTests.fakeResult("home-fire", household: household, home: home, routes: [earlier, current])
        result.snapshots = [SimulationSnapshot(simMinute: 3, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: state)]
        let l = try PlanBuilderTests.localizer("en")
        let doc = PlanBuilder.build(household: household, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        let snapshot = try #require(doc.visualSnapshot)
        let panel = try #require(snapshot.homePanels.first { $0.route != nil })
        #expect(panel.paths.isEmpty)
        #expect(panel.spatialState?.affectedSpaceIDs == ["sp-hall"])
        #expect(snapshot.panelDetails?[panel.id]?.contains { $0.contains(l("plan.route.reason.blockedByScenario")) } == true)
        #expect(!snapshot.homePanels.contains { !$0.paths.isEmpty })
        // A deliberately empty canonical stage still has a diagram, never the earlier path.
        result.snapshots[0].spatialState?.routes = []
        let empty = PlanBuilder.build(household: household, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        #expect(empty.visualSnapshot?.homePanels.contains { $0.id.hasPrefix("scene|") && $0.spatialState?.stageID == "blocked" } == true)
    }

    @Test("An upstairs-only path retains lower affected, exposed, opening and destination floors")
    func sceneFloorsOutsidePath() throws {
        var home = SampleHomes.twoStory
        let refuge = try #require(home.spaces.firstIndex { $0.id == "sp-bed2" })
        home.spaces[refuge].higherRefugeConfirmed = .confirmed(true)
        let upper = try #require(home.floors.firstIndex { $0.id == "fl-upper" })
        home.floors[upper].exteriorGrade = .aboveGround
        let route = EgressPlanner().plan(RouteRequest(personID: "resident", startSpaceID: "sp-bed1", purpose: .higherRefuge, destinationSpaceID: "sp-bed2"), in: home)
        let path = try #require(route.primary)
        #expect(Set(path.legs.map(\.floorID)) == ["fl-upper"])
        let scenes = [
            SpatialExerciseState(hazard: .flashFlood, seed: 7, stageID: "lower-water", affectedSpaceIDs: ["sp-kitchen"], routes: [route], assumption: "Lower room affected"),
            SpatialExerciseState(hazard: .tornado, seed: 7, stageID: "lower-exposure", routes: [route], assumption: "Lower room exposed", exposedSpaceIDs: ["sp-living"]),
            SpatialExerciseState(hazard: .flashFlood, seed: 7, stageID: "destination", destinationSpaceID: "sp-living", routes: [route], assumption: "Recorded destination candidate"),
            SpatialExerciseState(hazard: .homeFire, seed: 7, stageID: "opening-blocked", affectedPortalIDs: ["pt-back"], routes: [route], assumption: "Lower opening affected")
        ]
        for state in scenes {
            let snapshot = PlanVisualSnapshot(home: home, routes: [route], savedPlaces: [], homeCoordinate: nil, fictional: true,
                routeScenarioIDs: ["exercise"], exerciseStates: [PlanExerciseSnapshot(scenarioID: "exercise", state: state)])
            let qualified = snapshot.homePanels.filter { $0.scenarioID == "exercise" }
            #expect(Set(qualified.map(\.floorID)) == ["fl-ground", "fl-upper"], "\(state.stageID)")
            #expect(qualified.allSatisfy { $0.paths == [path] && $0.spatialState == state })
        }
    }

    @Test("Legacy snapshots recover the same localized qualifications after panelDetails is absent")
    func legacyQualificationFallback() throws {
        let home = SampleHomes.ranch, household = SampleHouseholds.oak
        var route = EgressPlanner().plan(RouteRequest(personID: household.people[0].id, startSpaceID: "sp-bed1"), in: home)
        // Retain the recorded starting room even when this stage has no supported path.
        route.primary = nil; route.alternative = nil; route.alternativeStatus = .none; route.noRouteReason = .blockedByScenario
        let state = SpatialExerciseState(hazard: .homeFire, seed: 7, stageID: "blocked", affectedSpaceIDs: ["sp-bed1"], routes: [route], assumption: "Authored blockage", assumptionKey: "spatial.assumption.fire-blocked")
        var result = PlanBuilderTests.fakeResult("home-fire", household: household, home: home, routes: [route])
        result.snapshots = [SimulationSnapshot(simMinute: 3, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: state)]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let doc = PlanBuilder.build(household: household, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
            let expected = try #require(doc.visualSnapshot?.panelDetails)
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
            var visual = try #require(json["visualSnapshot"] as? [String: Any])
            visual.removeValue(forKey: "panelDetails"); json["visualSnapshot"] = visual
            let legacy = try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: json))
            let snapshot = try #require(legacy.visualSnapshot)
            #expect(snapshot.panelDetails == nil)
            for panel in snapshot.homePanels {
                #expect(panel.details(in: snapshot, localizer: l) == expected[panel.id])
                if panel.scenarioID != nil {
                    #expect(panel.details(in: snapshot, localizer: l).contains(l("spatial.recorded-start-room", ["room": home.space("sp-bed1")!.label])))
                    #expect(panel.details(in: snapshot, localizer: l).contains(l("plan.route.caveat")))
                }
            }
        }
    }

    @Test("Missing content uses readable qualifications rather than raw localization keys")
    func absentContentFallback() throws {
        let home = SampleHomes.ranch
        var route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-bed1"), in: home)
        route.primary = nil; route.alternative = nil; route.noRouteReason = .blockedByScenario
        let snapshot = PlanVisualSnapshot(home: home, routes: [route], savedPlaces: [], homeCoordinate: nil, fictional: true, routeScenarioIDs: ["home-fire"])
        let panel = try #require(snapshot.homePanels.first { $0.route != nil })
        let details = panel.details(in: snapshot, localizer: Localizer(locale: "vi", tables: [:], manifest: nil))
        #expect(details.contains { $0.contains("blocked in this exercise") })
        #expect(details.last?.hasPrefix("English fallback:") == true)
        #expect(!details.contains { $0.hasPrefix("plan.") || $0.hasPrefix("spatial.") || $0.hasPrefix("common.") })
    }
}
