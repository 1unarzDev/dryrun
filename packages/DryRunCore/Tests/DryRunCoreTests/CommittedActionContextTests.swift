import Foundation
import Testing
@testable import DryRunCore

@Suite("Director context follows actual user commits") struct CommittedActionContextTests {
    @Test func followupSupersedesOriginalAndDirectorCommitsCannotReplaceIt()throws {
        var session=try SimulationSession.initialize(id:"actions",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),library:SimFixtures.library)
        #expect(try session.userActionContexts(library:SimFixtures.library).isEmpty)
        try session.commit(.init(id:"original",actor:"user",baseRevision:0,commands:[.init(kind:"useStoredWater",value:"all")]),library:SimFixtures.library)
        try session.commit(.init(id:"pause",actor:"director",baseRevision:1,commands:[.init(kind:"requestDecision")]),library:SimFixtures.library)
        try session.commit(.init(id:"followup",actor:"user",baseRevision:2,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)
        let actions=try session.userActionContexts(library:SimFixtures.library)
        #expect(actions.map(\.id)==["original","followup"])
        #expect(actions.last?.value=="essential");#expect(actions.last?.commitRevision==3)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(session))
        #expect(try restored.userActionContexts(library:SimFixtures.library)==actions)
    }
    @Test func batchOrderBoundAndMinimizationComeFromValidatedLog()throws {
        var session=try SimulationSession.initialize(id:"bounded",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),library:SimFixtures.library)
        try session.commit(.init(id:"batch",actor:"user",baseRevision:0,commands:[.init(kind:"useStoredWater",value:"all"),.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)
        #expect(try session.userActionContexts(library:SimFixtures.library).map(\.commandIndex)==[0,1])
        for n in 0..<8 {
            try session.commit(.init(id:"unsupported-\(n)",actor:"user",baseRevision:session.revision,commands:[.init(kind:"unsupported",target:"private-street-address",value:"private-contact-note")]),library:SimFixtures.library)
        }
        let actions=try session.userActionContexts(library:SimFixtures.library)
        #expect(actions.count==8);#expect(actions.allSatisfy{$0.target==nil && $0.value==nil})
        #expect(!String(decoding:try DryRunJSON.encoder().encode(actions),as:UTF8.self).contains("private-"))
        #expect(throws:SessionError.invalidCommand){try session.userActionContexts(library:SimFixtures.library,limit:9)}
        // A corrupted decoded log cannot be presented as a committed-action summary.
        var json=try #require(JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(session)) as? [String:Any])
        var commits=try #require(json["commits"] as? [[String:Any]])
        var commands=try #require(commits[0]["commands"] as? [[String:Any]])
        commands[0]["value"]="unvalidated-policy";commits[0]["commands"]=commands;json["commits"]=commits
        let corrupted=try DryRunJSON.decoder().decode(SimulationSession.self,from:JSONSerialization.data(withJSONObject:json))
        #expect(throws:SessionError.invalidCommand){try corrupted.userActionContexts(library:SimFixtures.library)}
    }
}
