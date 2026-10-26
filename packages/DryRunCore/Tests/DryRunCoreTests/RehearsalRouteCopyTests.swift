import Foundation
import Testing
@testable import DryRunCore

@Suite("Hazard route review copy")
struct RehearsalRouteCopyTests {
    private func localizer(_ locale: String = "en") throws -> Localizer {
        let library = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        return Localizer(locale: locale, tables: library.tables, manifest: library.localeManifest)
    }

    @Test func actualFireAndInteriorObjectivesHaveDifferentEndpoints() throws {
        let home = SimFixtures.home, l = try localizer()
        for id in ["home-fire", "tornado"] {
            let result = try SimFixtures.run(SampleHouseholds.oak, id)
            let routes = try #require(result.snapshots.last?.spatialState?.routes)
            var found = false
            for route in routes where route.primary != nil {
                found = true
                let projected = HomeScenePresentation.routeSteps(route, in: home, localizer: l)
                let text = try #require(projected)
                let path = try #require(route.primary)
                #expect(text.contains(HomeScenePresentation.roomLabel(route.request.startSpaceID, in: home)))
                if id == "home-fire" { #expect(text.hasSuffix(l("plan.route.outside"))) }
                else {
                    let destination = try #require(path.spaceSequence.last)
                    #expect(text.hasSuffix(HomeScenePresentation.roomLabel(destination, in: home)))
                    #expect(!text.hasSuffix(" → " + l("plan.route.outside")))
                    #expect(HomeScenePresentation.routeSteps(route, in: home, localizer: l, alternative: true) == nil)
                }
                for locale in ["es", "vi"] {
                    let translated = try localizer(locale)
                    let localized = try #require(HomeScenePresentation.routeSteps(route, in: home, localizer: translated))
                    #expect(!localized.contains("plan.route."))
                }
            }
            #expect(found, "Expected a real supported path for \(id)")
        }
    }

    @Test func floodDoesNotInventRefugeAndLabelsAnExplicitHigherDestination() throws {
        let l = try localizer()
        let unconfigured = try SimFixtures.run(SampleHouseholds.oak, "flash-flood")
        #expect(unconfigured.snapshots.last?.spatialState?.routes.allSatisfy { $0.primary == nil } == true)
        var home = SampleHomes.twoStory
        for index in home.floors.indices { home.floors[index].exteriorGrade = index == 0 ? .ground : .aboveGround }
        let high = try #require(home.spaces.first { $0.floorID == "fl-upper" })
        home.spaces[home.spaces.firstIndex { $0.id == high.id }!].higherRefugeConfirmed = .confirmed(true)
        var household = SampleHouseholds.oak
        household.people = [Person(id: "synthetic-resident", alias: "Synthetic resident", ageBand: .adult, sleepingSpaceID: high.id)]
        var input = SimFixtures.input(household, "flash-flood", home: home)
        input.spatialOptions = .init(floodAffectedSpaceIDs: ["sp-living"], refugeSpaceID: high.id)
        let result = try SimFixtures.engine.run(input)
        let route = try #require(result.snapshots.last?.spatialState?.routes.first)
        let projected = HomeScenePresentation.routeSteps(route, in: home, localizer: l)
        let steps = try #require(projected)
        #expect(route.request.purpose == .higherRefuge)
        #expect(steps.hasSuffix(HomeScenePresentation.roomLabel(high.id, in: home)))
        #expect(!steps.hasSuffix(" → " + l("plan.route.outside")))
        #expect(HomeScenePresentation.routeSteps(route, in: home, localizer: l, alternative: true) == nil)
    }

    @Test func mismatchedHomeNeverRelabelsOldPathEvenWithoutRevisionBump() throws {
        let home = SimFixtures.home, l = try localizer()
        let route = EgressPlanner().plan(.init(startSpaceID: home.spaces[0].id), in: home)
        #expect(HomeScenePresentation.routeSteps(route, in: home, localizer: l) != nil)
        var edited = home
        edited.spaces[0].label = "Edited after rehearsal"
        #expect(HomeScenePresentation.routeSteps(route, in: edited, localizer: l) == nil)
        var legacy = route; legacy.homeFingerprint = nil
        #expect(HomeScenePresentation.routeSteps(legacy, in: home, localizer: l) == nil)
        var missing = route; missing.primary = nil
        #expect(HomeScenePresentation.routeSteps(missing, in: home, localizer: l) == nil)
    }

    @Test func bottlenecksUseRoomFloorAndConnectionLabelsWithoutLeakingIdentifiers() throws {
        var home = SimFixtures.home
        let room = home.spaces[0]
        home.floors.append(.init(id: "synthetic-floor", level: 1, label: "Upstairs"))
        let l = try localizer()
        let text = HomeScenePresentation.routeElementLabel(room.id, in: home, localizer: l)
        #expect(text.contains(room.label) && text.contains(home.floors[0].label))
        #expect(!text.contains(room.id))
        let portal = try #require(home.portals.first)
        let connection = HomeScenePresentation.routeElementLabel(portal.id, in: home, localizer: l)
        #expect(connection.contains("connection between"))
        #expect(!connection.contains(portal.id))
        #expect(HomeScenePresentation.routeElementLabel("deleted-private-id", in: home, localizer: l) == l("plan.route.unknownRoom"))
        #expect(!connection.contains("experience.route."))
    }
}
