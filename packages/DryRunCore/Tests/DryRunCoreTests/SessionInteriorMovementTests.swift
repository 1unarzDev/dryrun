import Foundation
import Testing
@testable import DryRunCore

@Suite("Movement preserves hazard route purpose") struct SessionInteriorMovementTests {
    @Test func tornadoMovementNeverReplacesShelterWithExteriorRoute()throws {
        let input=SimFixtures.input(SampleHouseholds.oak,"tornado")
        var session=try SimulationSession.initialize(id:"shelter-move",initial:input,library:SimFixtures.library)
        let warning=SimFixtures.library.scenario("tornado")!.events.first{$0.rule==RuleID.tornadoWarning}!
        let before=try session.commit(.init(id:"warning",actor:"director",baseRevision:0,commands:[.init(kind:"startIncident",target:warning.id,minute:0,hazard:.tornado),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        let person=input.household.people[0]
        let target=try #require(before.routes.first{$0.request.personID==person.id}?.request.destinationSpaceID)
        let after=try session.commit(.init(id:"move",actor:"user",baseRevision:1,commands:[.init(kind:"moveTo",target:person.id,value:target)]),library:SimFixtures.library)
        let route=try #require(after.routes.first{$0.request.personID==person.id})
        #expect(route.request.startSpaceID==target)
        #expect(route.request.purpose == .interiorShelter)
        #expect(route.request.destinationSpaceID==target)
        #expect(after.snapshot.spatialState?.routes==after.routes)
        #expect(throws:SessionError.invalidCommand){try session.commit(.init(id:"failed-move",actor:"user",baseRevision:2,commands:[.init(kind:"moveTo",target:person.id,value:"missing-room")]),library:SimFixtures.library)}
        let failed=try session.query(library:SimFixtures.library)
        #expect(failed==after)
        #expect(session.initial==input)
        #expect(try session.query(library:SimFixtures.library)==failed)
    }
}
