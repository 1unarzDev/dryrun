import Foundation
import Testing
@testable import DryRunCore

@Suite("Current exercise assistance transport") struct ExerciseAssistanceContextTests {
    struct Context:Decodable {let assistance:[ExerciseAssistanceContext]?}
    struct Row:Decodable {
        let session:SimulationSession
        let appliedSession:SimulationSession
        let context:Context
        let name:String
        let recordedHelperID:String
    }
    struct Fixture:Decodable {let cases:[Row]}
    @Test func actualGatewayProjectionMatchesCurrentHostWhileRecordedHouseholdStaysFrozen()throws {
        let data=try Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/current-assistance-context.json"))
        let fixture=try DryRunJSON.decoder().decode(Fixture.self,from:data)
        #expect(fixture.cases.count==6)
        for row in fixture.cases {
            let receipt=try row.session.query(library:SimFixtures.library)
            #expect(receipt.assistanceContext==row.context.assistance)
            #expect(row.session.initial.household.people.first{$0.id=="p-oak-3"}?.helperPersonID==row.recordedHelperID)
            let encoded=String(decoding:try DryRunJSON.encoder().encode(receipt.assistanceContext),as:UTF8.self)
            #expect(!encoded.contains("spaceSequence"));#expect(!encoded.contains("route"))
            if row.name=="reassigned-supported-escape" {
                let current=try #require(receipt.assistanceContext?.first{$0.personID=="p-oak-3"})
                #expect(current.helperID=="p-oak-2");#expect(current.helperID != row.recordedHelperID)
                let applied=try row.appliedSession.query(library:SimFixtures.library)
                #expect(applied.experience?.escapeHelperByPersonID?["p-oak-3"]=="p-oak-2")
                #expect(applied.experience?.outsidePersonIDs.contains("p-oak-2")==true)
                #expect(applied.experience?.outsidePersonIDs.contains(row.recordedHelperID)==false)
                #expect(row.appliedSession.initial==row.session.initial)
            }
        }
    }
    @Test func unassessedAndAssessedEmptySummariesRemainDistinct()throws {
        var receipt=try SixHazardExperienceTests().session("tornado").query(library:SimFixtures.library)
        #expect(receipt.assistanceContext==nil)
        receipt.assistance=[]
        #expect(receipt.assistanceContext==[])
    }
}
