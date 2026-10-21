import Foundation
import Testing
@testable import DryRunCore

@Suite("Independent competency evidence preservation")
struct PracticeEvidencePreservationTests {
    private func attempt(_ id:String,_ sequence:Int,_ credits:[String:Double],coached:Bool=false,beforeFeedback:Bool=true)->PracticeAttempt {
        .init(id:id,sequence:sequence,variantID:"practice-check-a/2",answers:credits.keys.sorted().map {
            .init(competencyID:$0,credit:credits[$0]!,committedActionID:"\(id)-\($0)",beforeFeedback:beforeFeedback)
        },coached:coached)
    }
    private func score(_ attempts:[PracticeAttempt]) throws -> PreparednessScorecard {
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        return try ScoreCompiler.compile(rubric:rubric,assessments:[],attempts:attempts)
    }
    private var prior:PracticeAttempt {attempt("prior",1,["initialResponse":1,"adaptation":1,"communication":1,"continuity":0])}

    @Test("A short continuity check preserves route and communication evidence")
    func shortContinuity() throws {
        let latest=attempt("continuity",2,["continuity":1])
        let result=try score([prior,latest])
        #expect(result.practice==100)
        #expect(result.practiceAssessed==4)
        #expect(try score([latest,prior]).practice==result.practice)
    }

    @Test("New independent failure replaces only its competency")
    func contraryEvidence() throws {
        let result=try score([prior,attempt("failure",2,["communication":0])])
        #expect(result.practice==50)
        #expect(result.practiceAssessed==4)
    }

    @Test("Unanswered, coached, archived and feedback-exposed attempts cannot erase or farm evidence")
    func ineligible() throws {
        var archived=attempt("archived",5,["continuity":1]);archived.archivedUnverified=true
        let result=try score([prior,attempt("empty",2,[:]),attempt("coached",3,["communication":0,"continuity":1],coached:true),attempt("feedback",4,["continuity":1],beforeFeedback:false),archived])
        #expect(result.practice==75)
        #expect(result.practiceAssessed==4)
        #expect(try score([attempt("coached-only",1,["continuity":1],coached:true)]).practiceAssessed==0)
    }

    @Test("Repeated valid checks remain within the fixed competency budget")
    func fixedBudget() throws {
        let repeats=(2...12).map{attempt("repeat-\($0)",$0,["adaptation":1])}
        #expect(try score([prior]+repeats).practice==75)
        #expect(try score([prior]+repeats).practiceAssessed==4)
        #expect(throws:SessionError.invalidCommand){try score([prior,prior])}
        #expect(throws:SessionError.invalidCommand){try score([prior,attempt("duplicate-sequence",1,[:])])}
    }

    @Test("Invalid historical evidence cannot hide behind a later valid check")
    func invalidHistory() throws {
        #expect(throws:SessionError.invalidCommand){try score([attempt("invalid",0,["continuity":2]),prior])}
        var duplicate=attempt("duplicate",0,["continuity":1]);duplicate.answers.append(duplicate.answers[0])
        #expect(throws:SessionError.invalidCommand){try score([duplicate,prior])}
    }

    @Test("A hazard anchor preserves other competencies and cannot enlarge their budgets")
    func hazardAnchorPreservesOtherCompetencies() throws {
        let baseline = attempt("full", 1, ["initialResponse":1,"adaptation":1,"communication":1,"continuity":1])
        var anchor = PracticeAttempt(id:"water-gap",sequence:2,variantID:"hazard-check/1",answers:[
            .init(competencyID:"continuity",credit:0,committedActionID:"water-gap-command",beforeFeedback:true)])
        anchor.checkID = "water.gap/1"
        let failed = try score([baseline,anchor])
        #expect(failed.practice == 75)
        #expect(failed.practiceAssessed == 4)
        anchor.answers[0].credit = 1
        let denominator = Double(HazardPracticeCheck.bank.filter{$0.competencyID=="continuity"}.count)
        let improved = try score([baseline,anchor])
        #expect(improved.practice == 75 + 25/denominator)
        #expect(improved.practiceHazardsAssessed == ["water-outage"])
        #expect(abs((improved.practiceAnchorCoverage ?? 0) - 100/Double(HazardPracticeCheck.bank.count)) < 1e-10)
        #expect(try score([baseline,anchor,attempt("later-continuity",3,["continuity":1])]).practice == 100)
    }
}
