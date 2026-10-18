import Foundation
import Testing
@testable import DryRunCore

@Suite("October 17 spatial contracts")
struct SpatialRevisionTests {
    @Test("A personal manual draft has no assumed geometry and keeps its identity when the first room is entered")
    func emptyManualDraft() throws {
        var home = ManualLayout.emptyHome(id: "stable-personal-home")
        #expect(home.source == .manual && !home.isFictional)
        #expect(home.spaces.isEmpty && home.portals.isEmpty && home.annotations.isEmpty)
        #expect(home.floors.first?.exteriorGrade == .unknown)
        let decoded = try JSONDecoder().decode(HomeModel.self, from: JSONEncoder().encode(home))
        #expect(decoded == home)
        #expect(HomeConfirmation.steps(for: home).contains { $0.kind == .confirmFloor })
        let room = try ManualLayout.addFirstRoom(to: &home, label: "Our room", kind: .livingRoom, width: 4, depth: 3)
        #expect(home.id == "stable-personal-home" && home.spaces == [room])
        #expect(room.label == "Our room" && room.needsMeasurement)
        #expect(home.floors.first?.exteriorGrade == .unknown)
        #expect(EgressPlanner().plan(.init(startSpaceID: room.id), in: home).primary == nil)
        home = HomeConfirmation.apply(.floorGrade(floorID: home.floors[0].id, grade: .ground), to: home)
        home = HomeConfirmation.apply(.floorGrade(floorID: home.floors[0].id, grade: .unknown), to: home)
        #expect(home.floors.first?.exteriorGrade == .unknown)
        #expect(HomeConfirmation.steps(for: home).contains { $0.kind == .confirmFloor })
        #expect(throws: ManualLayout.LayoutError.self) {
            try ManualLayout.addFirstRoom(to: &home, label: "Duplicate", kind: .other, width: 4, depth: 3)
        }
        var empty = ManualLayout.emptyHome(id: "invalid")
        #expect(throws: ManualLayout.LayoutError.invalidSize) {
            try ManualLayout.addFirstRoom(to: &empty, label: "Invalid", kind: .other, width: .nan, depth: 3)
        }
        #expect(empty.spaces.isEmpty)
    }

    private func oneRoom(grade: ExteriorGrade? = .ground) -> HomeModel {
        HomeModel(id: "studio", label: "Fictional studio", source: .manual,
            floors: [Floor(id: "f", level: 0, label: "Floor", exteriorGrade: grade)],
            spaces: [Space(id: "r", floorID: "f", label: "Studio", kind: .livingRoom,
                           polygon: SampleHomes.rect(0, 0, 5, 5))],
            portals: [Portal(id: "exit", floorID: "f", kind: .door, a: Vec2(1.5, 0), b: Vec2(2.5, 0),
                sideA: .space("r"), sideB: .exterior, clearWidthMeters: .confirmed(1), operable: .confirmed(true),
                stepFree: .confirmed(true), verification: .verified)], isFictional: true)
    }

    @Test("Captured story and unknown grade never establish ground, including a legacy scan")
    func grade() {
        for grade: ExteriorGrade? in [.unknown, .aboveGround, .belowGround, nil] {
            var home = oneRoom(grade: grade); home.source = .roomPlanScan
            #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: home).primary == nil)
            #expect(HomeConfirmation.steps(for: home).contains { $0.kind == .confirmFloor } == (grade == .unknown || grade == nil))
        }
        let walkout = oneRoom(grade: .walkout)
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: walkout).primary != nil)
    }

    @Test("A window inventory and operability confirmation are insufficient escape evidence")
    func window() {
        var home = oneRoom(); home.portals[0].kind = .window
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: home).primary == nil)
        home.portals[0].emergencyEscapeConfirmed = true
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: home).primary != nil)
        #expect(EgressPlanner().plan(.init(startSpaceID: "r", mobility: .wheelchair), in: home).primary == nil)
    }

    @Test("Interior shelter routing ends in the actual confirmed room, never at an exterior exit")
    func destination() throws {
        var home = SampleHomes.ranch
        let shelter = try #require(home.spaces.first { $0.interiorNoWindowsConfirmed.confirmedValue == true })
        let start = try #require(home.spaces.first { $0.id != shelter.id })
        let request = RouteRequest(startSpaceID: start.id, purpose: .interiorShelter, destinationSpaceID: shelter.id)
        let route = EgressPlanner().plan(request, in: home)
        let path = try #require(route.primary)
        #expect(path.spaceSequence.last == shelter.id)
        #expect(path.exitPortalID == "space:\(shelter.id)")
        #expect(RouteGeometryAudit.violations(path, in: home).isEmpty)
        home.annotations.removeAll { $0.kind == .tornadoShelterCandidate }
        #expect(EgressPlanner().plan(request, in: home).primary == nil)
    }

    @Test("Excluded start exposure is retained, and duplicate identities fail without a crash")
    func exclusions() {
        var home = oneRoom()
        let route = EgressPlanner().plan(.init(startSpaceID: "r", exclusions: .init(blockedSpaceIDs: ["r"])), in: home)
        #expect(route.primary == nil && route.noRouteReason == .blockedByScenario)
        home.spaces.append(home.spaces[0])
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: home).noRouteReason == .invalidGeometry)
    }

    @Test("Studio, concave, basement, walkout, split, shared corridor, missing and narrow fixtures remain conservative")
    func configurations() throws {
        var concave = oneRoom()
        concave.spaces[0].polygon = [Vec2(0,0), Vec2(5,0), Vec2(5,2), Vec2(2,2), Vec2(2,5), Vec2(0,5)]
        var basement = oneRoom(grade: .belowGround); basement.floors[0].level = -1
        var walkout = basement; walkout.floors[0].exteriorGrade = .walkout
        var narrow = oneRoom(); narrow.portals[0].clearWidthMeters = .confirmed(0.5)
        var incomplete = oneRoom(); incomplete.portals[0].sideB = .unknown; incomplete.completeness = .incomplete
        var offset = SampleHomes.twoStory
        if !offset.connectors.isEmpty { offset.connectors[0].toPoint = Vec2(999,999) }
        let fixtures = [oneRoom(), concave, basement, walkout, narrow, incomplete, offset, SampleHomes.apartment, SampleHomes.twoStory]
        for home in fixtures {
            for room in home.spaces {
                for mobility in [MobilityProfile.walking, .wheelchair] {
                    let request = RouteRequest(startSpaceID: room.id, mobility: mobility)
                    let a = EgressPlanner().plan(request, in: home), b = EgressPlanner().plan(request, in: home)
                    #expect(a == b)
                    if let path = a.primary { #expect(RouteGeometryAudit.violations(path, in: home).isEmpty) }
                    if mobility.requiresStepFree { #expect(a.primary?.connectorSequence.allSatisfy { id in home.connectors.first { $0.id == id }?.kind != .stairs } ?? true) }
                }
            }
        }
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: basement).primary == nil)
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: walkout).primary != nil)
        #expect(EgressPlanner().plan(.init(startSpaceID: "r"), in: narrow).primary == nil)
    }

    @Test("Fire chooses one room by ID and per-stage routes never retain a superseded path")
    func scenes() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let library = try ScenarioLibrary.load(from: LeadTestSupport.contentRoot.appendingPathComponent("scenarios"))
        let engine = RehearsalEngine(library: library, planner: EgressPlanner())
        var home = SampleHomes.ranch
        let kitchen = try #require(home.spaces.first { $0.kind == .kitchen })
        var duplicate = kitchen; duplicate.id = "second-kitchen"; duplicate.polygon = duplicate.polygon.map { $0 + Vec2(100,100) }
        home.spaces.append(duplicate)
        var household = SampleHouseholds.oak; household.people[0].sleepingSpaceID = kitchen.id
        let scenario = try #require(library.scenario("home-fire"))
        let input = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version,
            contentVersion: content.manifest.contentVersion, seed: 7, spatialOptions: .init(originSpaceID: kitchen.id))
        let result = try engine.run(input)
        #expect(result == (try engine.run(input)))
        let scene = try #require(result.snapshots.compactMap(\.spatialState).first { !$0.affectedSpaceIDs.isEmpty })
        #expect(scene.affectedSpaceIDs == [kitchen.id])
        #expect(scene.routes.first { $0.request.personID == household.people[0].id }?.noRouteReason == .blockedByScenario)
        #expect(result.routes.count == household.people.count)
        var cursor = RehearsalCursor(result: result)
        #expect(cursor.snapshotAtCursor?.spatialState == nil)
        cursor.advance()
        #expect(cursor.snapshotAtCursor?.spatialState?.affectedSpaceIDs.isEmpty == true)
    }

    private func exerciseHomes() -> [HomeModel] {
        var concave = oneRoom(); concave.id = "concave"
        concave.spaces[0].polygon = [Vec2(0,0), Vec2(5,0), Vec2(5,2), Vec2(2,2), Vec2(2,5), Vec2(0,5)]
        var basement = oneRoom(grade: .belowGround); basement.id = "basement"; basement.floors[0].level = -1
        var walkout = basement; walkout.id = "walkout"; walkout.floors[0].exteriorGrade = .walkout
        var split = SampleHomes.twoStory; split.id = "split"
        for index in split.floors.indices { split.floors[index].elevationMeters *= 0.5 }
        var incomplete = SampleHomes.ranch; incomplete.id = "incomplete"; incomplete.source = .roomPlanScan
        incomplete.floors[0].exteriorGrade = .unknown; incomplete.completeness = .incomplete
        incomplete.portals[0].sideB = .unknown
        var ambiguous = oneRoom(); ambiguous.id = "ambiguous"; ambiguous.portals.append(ambiguous.portals[0])
        var narrow = SampleHomes.ranch; narrow.id = "narrow"
        for index in narrow.portals.indices { narrow.portals[index].clearWidthMeters = .confirmed(0.5) }
        var obstacle = oneRoom(); obstacle.id = "obstructed"
        obstacle.obstacles = [Obstacle(id: "block", floorID: "f", label: "Blocked doorway", polygon: SampleHomes.rect(1,0.1,3,1))]
        var offset = SampleHomes.twoStory; offset.id = "offset-landings"
        if !offset.connectors.isEmpty { offset.connectors[0].toPoint = Vec2(999,999) }
        return [oneRoom(), concave, basement, walkout, split, incomplete, ambiguous, narrow, obstacle, offset,
                SampleHomes.apartment, SampleHomes.ranch, SampleHomes.twoStory]
    }

    @Test("Fire room origins and resident starts share exclusions across diverse layouts and blocked exits")
    func fireConfigurationScenes() throws {
        for home in exerciseHomes() {
            for origin in home.spaces {
                let starts = Set([home.spaces.first!.id, home.spaces.last!.id, origin.id]).sorted()
                for start in starts {
                    for blocked in [false, true] {
                        var household = SampleHouseholds.oak
                        household.people = [Person(id: "resident", alias: "Example resident", ageBand: .adult,
                            needs: home.id == "narrow" ? [.usesWheelchair] : [], sleepingSpaceID: start)]
                        household.equipment = []; household.backupPower = []
                        var input = SimFixtures.input(household, "home-fire", home: home,
                            variants: blocked ? ["second-exit-blocked", "hallway-smoke"] : [])
                        input.spatialOptions = .init(originSpaceID: origin.id)
                        let result = try SimFixtures.engine.run(input)
                        let scenes = result.snapshots.compactMap(\.spatialState)
                        let blockedScene = try #require(scenes.first { !$0.affectedSpaceIDs.isEmpty })
                        #expect(blockedScene.originSpaceID == origin.id)
                        #expect(blockedScene.affectedSpaceIDs.contains(origin.id))
                        #expect(result.routes.count == 1)
                        for scene in scenes {
                            #expect(scene.routes.count == 1)
                            for route in scene.routes {
                                #expect(route.request.personID == "resident")
                                #expect(Set(route.request.exclusions.blockedSpaceIDs) == Set(scene.affectedSpaceIDs))
                                if let path = route.primary {
                                    #expect(Set(path.spaceSequence).isDisjoint(with: scene.affectedSpaceIDs))
                                    #expect(Set(path.portalSequence).isDisjoint(with: scene.affectedPortalIDs))
                                    #expect(RouteGeometryAudit.violations(path, in: home).isEmpty)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Flood refuge and tornado shelter scenes preserve subjects, floors and mobility across the same fixtures")
    func floodTornadoConfigurationScenes() throws {
        for fixture in exerciseHomes() {
            var home = fixture
            let sorted = home.spaces.sorted { a,b in
                let ae = home.floors.first { $0.id == a.floorID }?.elevationMeters ?? 0
                let be = home.floors.first { $0.id == b.floorID }?.elevationMeters ?? 0
                return ae == be ? a.id < b.id : ae < be
            }
            let low = sorted.first!, high = sorted.last!
            home.spaces[home.spaces.firstIndex { $0.id == high.id }!].higherRefugeConfirmed = .confirmed(true)
            home.spaces[home.spaces.firstIndex { $0.id == low.id }!].interiorNoWindowsConfirmed = .confirmed(true)
            home.annotations.append(Annotation(id: "exercise-shelter", kind: .tornadoShelterCandidate,
                floorID: low.floorID, spaceID: low.id, label: "Example shelter", verification: .verified))
            for start in Set([low.id, high.id]).sorted() {
                for mobility in [false,true] {
                    var household = SampleHouseholds.oak
                    household.people = [Person(id: "resident", alias: "Example resident", ageBand: .adult,
                        needs: mobility ? [.usesWheelchair] : [], sleepingSpaceID: start)]
                    household.equipment = []; household.backupPower = []
                    for hazard in ["flash-flood", "tornado"] {
                        var input = SimFixtures.input(household, hazard, home: home)
                        input.spatialOptions = .init(floodAffectedSpaceIDs: [low.id], refugeSpaceID: high.id)
                        let result = try SimFixtures.engine.run(input)
                        let scenes = result.snapshots.compactMap(\.spatialState)
                        #expect(!scenes.isEmpty)
                        for scene in scenes {
                            #expect(scene.seed == input.seed)
                            #expect(scene.routes.count == 1)
                            let route = scene.routes[0]
                            #expect(route.request.personID == "resident")
                            #expect(route.request.purpose == (hazard == "tornado" ? .interiorShelter : .higherRefuge))
                            if let path = route.primary {
                                #expect(path.exitPortalID.hasPrefix("space:"))
                                #expect(path.spaceSequence.last == route.request.destinationSpaceID)
                                #expect(Set(path.spaceSequence).isDisjoint(with: scene.affectedSpaceIDs))
                                #expect(RouteGeometryAudit.violations(path, in: home).isEmpty)
                                if mobility { #expect(path.connectorSequence.allSatisfy { id in home.connectors.first { $0.id == id }?.kind != .stairs }) }
                                if hazard == "flash-flood" {
                                    let targetFloor = home.floors.first { $0.id == home.space(route.request.destinationSpaceID!)?.floorID }!
                                    #expect(scene.affectedSpaceIDs.allSatisfy { id in
                                        guard let space = home.space(id), let floor = home.floors.first(where: { $0.id == space.floorID }) else { return false }
                                        return floor.elevationMeters < targetFloor.elevationMeters
                                    })
                                }
                            }
                        }
                        #expect(result == (try SimFixtures.engine.run(input)))
                    }
                }
            }
        }
    }

    @Test("Higher refuge needs an explicit not-closed-attic and way-out confirmation")
    func closedAtticRefuge() {
        var home = oneRoom(grade: .aboveGround)
        home.spaces[0].label = "Attic" // The label never establishes suitability.
        let request = RouteRequest(startSpaceID: "r", purpose: .higherRefuge, destinationSpaceID: "r")
        #expect(EgressPlanner().plan(request, in: home).primary == nil)
        home.spaces[0].higherRefugeConfirmed = .confirmed(false)
        #expect(EgressPlanner().plan(request, in: home).primary == nil)
        home.spaces[0].higherRefugeConfirmed = .confirmed(true)
        #expect(EgressPlanner().plan(request, in: home).primary != nil)
    }

    @Test("Capture cancellation, retry, repeated Finish and late callbacks use originating tokens")
    func callbacks() {
        var gate = CaptureCallbackGate()
        let cancelled = gate.begin()
        let firstFinish = gate.expectFinish(from: cancelled)
        #expect(firstFinish)
        gate.invalidate()
        let retry = gate.begin()
        let retryFinish = gate.expectFinish(from: retry)
        let repeatedFinish = gate.expectFinish(from: retry)
        let stale = gate.accept(from: cancelled)
        let current = gate.accept(from: retry)
        let repeatedCallback = gate.accept(from: retry)
        #expect(retryFinish && !repeatedFinish && !stale && current && !repeatedCallback)
        let interrupted = gate.begin()
        let interruptedFinish = gate.expectFinish(from: interrupted)
        #expect(interruptedFinish)
        gate.invalidate()
        let lateInterrupted = gate.accept(from: interrupted)
        #expect(!lateInterrupted)
    }

    @Test("Rendered wall segments omit the same portal span")
    func wallGaps() {
        let home = oneRoom()
        let segments = HomeRenderGeometry.wallSegments(home)
        #expect(!segments.contains { Geometry.distancePointSegment(Vec2(2,0), $0.a, $0.b) < 0.01 })
        #expect(segments.contains { Geometry.distancePointSegment(Vec2(1,0), $0.a, $0.b) < 0.01 })
    }
}
