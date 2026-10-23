import Foundation
import Testing
@testable import DryRunCore

@Suite("Committed spatial choice causality")
struct SpatialChoiceCausalityTests {
    func authoredSession(id: String, input: RehearsalInput) -> SimulationSession {
        SimulationSession(id: id, initial: input, directorPolicy: .reviewed(SimFixtures.library.scenario(input.scenarioID)!))
    }
    func household() -> HouseholdProfile {
        var h = SampleHouseholds.oak
        h.people = Array(h.people.prefix(1)); h.equipment = []; h.backupPower = []; h.pets = []
        return h
    }
    func occupant(_ result: RehearsalResult, at minute: Int, personID: String) -> ExerciseOccupantState? {
        result.snapshots.last { $0.simMinute <= minute }?.spatialState?.occupants?.first { $0.personID == personID }
    }
    @Test func authoredFireDepartureAndOutsideAccountingAreSeparateConsequences() throws {
        let h = household(), person = h.people[0]
        let initial = SimFixtures.input(h, "home-fire")
        let departed = try SimFixtures.engine.run(initial)
        var delayedInput = initial
        delayedInput.choices["choice.home-fire.first-move"] = "grab-belongings"
        let delayed = try SimFixtures.engine.run(delayedInput)
        #expect(departed.input == initial)
        #expect(occupant(departed, at: 0, personID: person.id)?.exteriorExitPortalID != nil)
        #expect(occupant(departed, at: 0, personID: person.id)?.accountedOutside == false)
        #expect(occupant(departed, at: 3, personID: person.id)?.accountedOutside == true)
        #expect(occupant(delayed, at: 3, personID: person.id)?.exteriorExitPortalID == nil)
        #expect(occupant(delayed, at: 3, personID: person.id)?.accountedOutside == false)
        // Later authored smoke cannot put an already-departed person back inside.
        #expect(departed.snapshots.last?.spatialState?.occupants?.first?.exteriorExitPortalID != nil)
        #expect(!departed.snapshots.last!.unmetRequirements.contains("req.egress.\(person.id)"))
        let beforeDecision = try #require(departed.snapshots.first { $0.spatialState != nil }?.spatialState)
        #expect(beforeDecision.occupants?.first?.exteriorExitPortalID == nil)
    }

    @Test func authoredTornadoChoiceMovesOnlySupportedPeopleAndPreservesSnapshotHistory() throws {
        let h = household(), person = h.people[0]
        let accepted = try SimFixtures.run(h, "tornado")
        let declined = try SimFixtures.run(h, "tornado", choices: ["choice.tornado.warning": "stay-in-bedroom"])
        let target = try #require(ShelterSuitability.confirmedRoom(in: SampleHomes.ranch)?.id)
        #expect(occupant(accepted, at: 60, personID: person.id)?.currentSpaceID == person.sleepingSpaceID)
        #expect(occupant(accepted, at: 61, personID: person.id)?.currentSpaceID == target)
        #expect(occupant(accepted, at: 61, personID: person.id)?.shelteredSpaceID == target)
        #expect(occupant(declined, at: 61, personID: person.id)?.shelteredSpaceID == nil)
        #expect(accepted.routes.first?.request.startSpaceID == target)
        #expect(accepted.input.household == h)
        var isolated = SampleHomes.ranch
        isolated.portals.removeAll { $0.id == "pt-closet-hall" }
        let blocked = try SimFixtures.run(h, "tornado", home: isolated)
        #expect(occupant(blocked, at: 61, personID: person.id)?.currentSpaceID == person.sleepingSpaceID)
        #expect(occupant(blocked, at: 61, personID: person.id)?.shelteredSpaceID == nil)
    }

    @Test func incrementalChoicePersistsArrivalRejectsReentryAndCannotAccountIndoorPeople() throws {
        let h = household(), person = h.people[0]
        var s = authoredSession(id: "departure", input: SimFixtures.input(h, "home-fire"))
        try s.commit(.init(id: "alarm", actor: "director", baseRevision: 0,
            commands: [.init(kind: "schedule", target: "evt.home-fire.alarm", minute: 0), .init(kind: "advance", minute: 0)]), library: SimFixtures.library)
        let departure = SessionCommit(id: "depart", actor: "user", baseRevision: 1,
            commands: [.init(kind: "choose", target: "choice.home-fire.first-move", value: "get-out")])
        let preview = try s.preview(departure, library: SimFixtures.library)
        #expect(try s.query(library: SimFixtures.library).snapshot.spatialState?.occupants?.first?.exteriorExitPortalID == nil)
        #expect(try s.commit(departure, library: SimFixtures.library) == preview)
        #expect(preview.snapshot.spatialState?.occupants?.first?.exteriorExitPortalID != nil)
        #expect(throws: SessionError.invalidCommand) {
            try s.commit(.init(id: "reenter", actor: "user", baseRevision: 2,
                commands: [.init(kind: "moveTo", target: person.id, value: person.sleepingSpaceID)]), library: SimFixtures.library)
        }
        let accounted = try s.commit(.init(id: "account", actor: "user", baseRevision: 2,
            commands: [.init(kind: "choose", target: "choice.home-fire.outside", value: "call-from-outside")]), library: SimFixtures.library)
        #expect(accounted.snapshot.spatialState?.occupants?.first?.accountedOutside == true)
        let restored = try DryRunJSON.decoder().decode(SimulationSession.self, from: DryRunJSON.encoder().encode(s))
        #expect(try restored.query(library: SimFixtures.library) == accounted)
    }

    @Test func noExitUnknownWindowAndMissingHelperNeverCreateArrival() throws {
        var home = SampleHomes.ranch
        home.portals.removeAll { $0.kind != .window && ($0.sideA == .exterior || $0.sideB == .exterior) }
        let h = household()
        let noExit = try SimFixtures.run(h, "home-fire", home: home)
        #expect(noExit.snapshots.last?.spatialState?.occupants?.first?.exteriorExitPortalID == nil)
        #expect(noExit.snapshots.last?.spatialState?.occupants?.first?.accountedOutside == false)
        var dependent = h
        dependent.people[0].needs.append(.needsHelperToEvacuate)
        let unassisted = try SimFixtures.run(dependent, "home-fire")
        #expect(unassisted.snapshots.last?.spatialState?.occupants?.first?.exteriorExitPortalID == nil)
        #expect(unassisted.snapshots.last?.spatialState?.occupants?.first?.accountedOutside == false)
    }

    @Test func affectedOriginAndUnreachableHelperDoNotMoveOccupants() throws {
        var h = household()
        h.people[0].sleepingSpaceID = "sp-kitchen"
        let helperID = h.people[0].id
        h.people.append(Person(id: "dependent", alias: "Synthetic child", ageBand: .child,
            sleepingSpaceID: "sp-bed2", helperPersonID: helperID))
        var session = authoredSession(id: "origin-blocked", input: SimFixtures.input(h, "home-fire"))
        try session.commit(.init(id: "origin", actor: "director", baseRevision: 0, commands: [
            .init(kind: "startIncident", target: "evt.home-fire.fire-origin", value: "sp-kitchen", minute: 0, hazard: .homeFire),
            .init(kind: "advance", minute: 0)]), library: SimFixtures.library)
        let result = try session.commit(.init(id: "attempt", actor: "user", baseRevision: 1,
            commands: [.init(kind: "choose", target: "choice.home-fire.first-move", value: "get-out")]), library: SimFixtures.library)
        let people = try #require(result.snapshot.spatialState?.occupants)
        #expect(people.count == 2)
        #expect(people.allSatisfy { $0.exteriorExitPortalID == nil })
        #expect(people.first { $0.personID == helperID }?.currentSpaceID == "sp-kitchen")
        #expect(people.first { $0.personID == "dependent" }?.currentSpaceID == "sp-bed2")
    }

    @Test func incrementalShelterArrivalUsesSameRoomAndRouteAsAuthoredPlayback() throws {
        let h = household()
        var session = authoredSession(id: "shelter", input: SimFixtures.input(h, "tornado"))
        let warning = try #require(SimFixtures.library.scenario("tornado")?.events.first { $0.rule == RuleID.tornadoWarning })
        try session.commit(.init(id: "warning", actor: "director", baseRevision: 0, commands: [
            .init(kind: "startIncident", target: warning.id, minute: 0, hazard: .tornado), .init(kind: "advance", minute: 0)]), library: SimFixtures.library)
        let arrival = try session.commit(.init(id: "arrive", actor: "user", baseRevision: 1,
            commands: [.init(kind: "choose", target: "choice.tornado.warning", value: "go-to-shelter")]), library: SimFixtures.library)
        let authored = try SimFixtures.run(h, "tornado")
        #expect(arrival.snapshot.spatialState?.occupants == authored.snapshots.last?.spatialState?.occupants)
        #expect(arrival.routes.first?.request.purpose == .interiorShelter)
        #expect(arrival.routes.first?.request.startSpaceID == arrival.snapshot.spatialState?.occupants?.first?.shelteredSpaceID)
        #expect(session.initial.household == h)
    }
}
