import Foundation
import Testing
@testable import DryRunCore

@Suite("Canonical home scene presentation")
struct HomeScenePresentationTests {
    @Test("Exit style follows routing evidence and grade rather than a verified label alone")
    func exitEvidence() throws {
        let original = SampleHomes.ranch
        let front = try #require(original.portal("pt-front"))
        #expect(HomeScenePresentation.openingStatus(front, in: original) == .availableExit)
        var home = original
        home.source = .roomPlanScan; home.floors[0].exteriorGrade = nil
        #expect(HomeScenePresentation.openingStatus(front, in: home) == .unavailable)
        home.floors[0].exteriorGrade = .ground
        #expect(HomeScenePresentation.openingStatus(front, in: home) == .availableExit)
        home.spaces[home.spaces.firstIndex { $0.id == "sp-living" }!].geometryNeedsReview = true
        #expect(HomeScenePresentation.openingStatus(front, in: home) == .unconfirmed)
        var stuck = front; stuck.operable = .confirmed(false)
        #expect(HomeScenePresentation.openingStatus(stuck, in: original) == .unavailable)
        let apartment = SampleHomes.apartment
        #expect(HomeScenePresentation.openingStatus(try #require(apartment.portal("pt-balcony")), in: apartment) == .unavailable)
        #expect(HomeScenePresentation.openingStatus(try #require(apartment.portal("pt-entry")), in: apartment) == .unconfirmed)
    }

    @Test("Authored stage exclusions remove exit styling and retain an exposed resident's recorded room")
    func blockedStage() throws {
        let home = SampleHomes.ranch
        let request = RouteRequest(personID: "resident", startSpaceID: "sp-living", exclusions: .init(blockedSpaceIDs: ["sp-living"], blockedPortalIDs: ["pt-back"]))
        let route = EgressPlanner().plan(request, in: home)
        #expect(route.primary == nil)
        #expect(route.noRouteReason == .blockedByScenario)
        let state = SpatialExerciseState(hazard: .homeFire, seed: 7, stageID: "blocked", affectedSpaceIDs: ["sp-living"], affectedPortalIDs: ["pt-back"], routes: [route], assumption: "Exercise")
        for id in ["pt-front", "pt-back"] {
            #expect(HomeScenePresentation.openingStatus(try #require(home.portal(id)), in: home, state: state) == .unavailable)
        }
        #expect(HomeScenePresentation.startingRoom(in: home, route: route)?.id == "sp-living")
        #expect(HomeScenePresentation.startingRoomPosition(in: home, route: route) != nil)
        #expect(state.affectedSpaceIDs.contains("sp-living"), "Presentation never erases a blocked start to draw a route")
        let unknown = EgressPlanner().plan(RouteRequest(startSpaceID: ""), in: home)
        #expect(HomeScenePresentation.startingRoom(in: home, route: unknown) == nil)
    }

    @Test("Floor selection follows the selected resident, permits explicit review and rejects stale floor IDs")
    func selectedFloor() throws {
        let home = SampleHomes.twoStory
        let route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-bed1"), in: home)
        let upstairs = try #require(home.space("sp-bed1")?.floorID)
        let ground = try #require(home.space("sp-living")?.floorID)
        #expect(HomeScenePresentation.sceneFloorID(in: home, selected: nil, route: route, destinationID: nil) == upstairs)
        #expect(HomeScenePresentation.sceneFloorID(in: home, selected: ground, route: route, destinationID: nil) == ground)
        #expect(HomeScenePresentation.sceneFloorID(in: home, selected: "deleted-floor", route: route, destinationID: nil) == upstairs)
        #expect(HomeScenePresentation.sceneFloorID(in: home, selected: nil, route: nil, destinationID: "sp-bed1") == upstairs)
    }

    @Test("Focused highlights resolve either stair landing, annotations and shelter room without floor-order guesses")
    func focusedFloor() throws {
        var home = SampleHomes.twoStory
        var stair = try #require(home.connectors.first)
        swap(&stair.fromSpaceID, &stair.toSpaceID); swap(&stair.fromPoint, &stair.toPoint)
        home.connectors = [stair]
        #expect(HomeScenePresentation.floorID(for: stair.id, in: home) == home.space(stair.fromSpaceID)?.floorID)
        #expect(HomeScenePresentation.floorID(for: stair.id, in: home, connectorDestination: true) == home.space(stair.toSpaceID)?.floorID)
        for annotation in home.annotations {
            #expect(HomeScenePresentation.floorID(for: annotation.id, in: home) == annotation.floorID)
        }
        #expect(HomeScenePresentation.floorID(for: "sp-bed1", in: home) == home.space("sp-bed1")?.floorID)
    }

    @Test("Clearing a measured threshold restores unknown and invalidates wheelchair use without losing invalid drafts")
    func clearedWidth() throws {
        var home = SampleHomes.ranch
        home.portals.removeAll { $0.leadsToExterior && $0.id != "pt-front" }
        let request = RouteRequest(startSpaceID: "sp-living", mobility: .wheelchair)
        #expect(EgressPlanner().plan(request, in: home).primary != nil)
        let i = try #require(home.portals.firstIndex { $0.id == "pt-front" })
        let recorded = home.portals[i].clearWidthMeters
        #expect(HomeScenePresentation.editedWidth("oops", previous: recorded) == recorded)
        #expect(HomeScenePresentation.editedWidth("0,95", previous: recorded).confirmedValue == 0.95)
        home.portals[i].clearWidthMeters = HomeScenePresentation.editedWidth("  ", previous: recorded)
        #expect(!home.portals[i].clearWidthMeters.isKnown)
        #expect(EgressPlanner().plan(request, in: home).primary == nil)
        #expect(HomeScenePresentation.openingStatus(home.portals[i], in: home, request: request) == .unconfirmed)
        #expect(HomeScenePresentation.openingStatus(home.portals[i], in: home) == .availableExit, "Generic drawing and subject-specific access are distinct")
    }

    @Test("Windows never receive ordinary exit styling and detached openings stay unconfirmed")
    func inventory() throws {
        var home = SampleHomes.ranch
        var window = try #require(home.portals.first { $0.kind == .window })
        window.verification = .verified; window.operable = .confirmed(true); window.emergencyEscapeConfirmed = true
        #expect(HomeScenePresentation.openingStatus(window, in: home) == .window)
        var door = try #require(home.portal("pt-front")); door.a = Vec2(100, 100); door.b = Vec2(101, 100)
        home.portals.append(door)
        #expect(HomeScenePresentation.openingStatus(door, in: home) == .unconfirmed)
    }
    @Test("Room markers stay inside a concave outline and do not fabricate coordinates for absent geometry")
    func concaveMarker() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.spaces.firstIndex { $0.id == "sp-living" })
        home.spaces[index].polygon = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 1), Vec2(1, 1), Vec2(1, 6), Vec2(0, 6)]
        home.spaces[index].usesOutlineWalls = true
        home.walls = []; home.obstacles = []
        let route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-living"), in: home)
        let point = try #require(HomeScenePresentation.startingRoomPosition(in: home, route: route))
        #expect(Geometry.contains(home.spaces[index].polygon, point))
        home.spaces[index].polygon = []
        #expect(HomeScenePresentation.startingRoomPosition(in: home, route: route) == nil)
    }

}
