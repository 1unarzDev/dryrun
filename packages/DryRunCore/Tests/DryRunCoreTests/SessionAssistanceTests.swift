import Foundation
import Testing
@testable import DryRunCore

@Suite("Committed helper reach") struct SessionAssistanceTests {
    func session()throws->SimulationSession {
        var input=SimFixtures.input(SampleHouseholds.oak,"home-fire")
        input.variants=["hallway-smoke"]
        input.household.people[1].sleepingSpaceID="sp-bed2"
        var session=try SimulationSession.initialize(id:"helpers",initial:input,library:SimFixtures.library)
        try session.commit(.init(id:"smoke",actor:"director",baseRevision:0,commands:[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:"sp-hall",minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        return session
    }
    func assign(_ session:inout SimulationSession,_ helper:String)throws->SessionReceipt {
        try session.commit(.init(id:"assign-\(session.revision)",actor:"user",baseRevision:session.revision,commands:[.init(kind:"assignHelper",target:"p-oak-3",value:helper)]),library:SimFixtures.library)
    }
    @Test func reassignmentRecomputesActualReachWithoutChangingRealHousehold()throws {
        var s=try session();let initial=s.initial
        let blocked=try assign(&s,"p-oak-1")
        #expect(blocked.assistance?.first{$0.personID=="p-oak-3"}?.reachStatus == .unreachable)
        #expect(blocked.snapshot.unmetRequirements.contains("req.assistance.reach.p-oak-3"))
        let reachable=try assign(&s,"p-oak-2")
        let child=reachable.assistance?.first{$0.personID=="p-oak-3"}
        #expect(child?.helperID=="p-oak-2");#expect(child?.reachStatus == .reachable)
        #expect(!reachable.snapshot.unmetRequirements.contains("req.assistance.reach.p-oak-3"))
        #expect(s.initial==initial)
        let dependencies=try s.dependencyInspection(receipt:reachable,library:SimFixtures.library)
        #expect(dependencies.contains{$0.id=="helperReach|p-oak-3" && $0.subjectIDs==["p-oak-3","p-oak-2"] && $0.status.contains("reachable")})
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try restored.query(library:SimFixtures.library)==reachable)
    }
    @Test func sharingExposesUnknownCapacityAndAssignmentIsUserOwned()throws {
        var s=try session()
        let before=try s.query(library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try s.commit(.init(id:"model-helper",actor:"director",baseRevision:1,commands:[.init(kind:"assignHelper",target:"p-oak-3",value:"p-oak-2")]),library:SimFixtures.library)}
        #expect(try s.query(library:SimFixtures.library)==before)
        let result=try assign(&s,"p-oak-2")
        let child=result.assistance?.first{$0.personID=="p-oak-3"}
        #expect(child?.sharedWithPersonIDs==["p-oak-4"])
        #expect(child?.simultaneousCapacity=="unknown")
        #expect(!result.snapshot.unmetRequirements.contains("req.assistance.capacity.p-oak-2"))
        #expect(throws:SessionError.duplicate){try s.commit(s.commits.last!,library:SimFixtures.library)}
    }
}
