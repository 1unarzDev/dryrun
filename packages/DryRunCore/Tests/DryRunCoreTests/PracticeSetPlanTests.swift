import Foundation
import Testing
@testable import DryRunCore

@Suite("practice-phases/3: whole set planned up front, fresh per attempt") struct PracticeSetPlanTests {
    func fixture()throws->(HouseholdProfile,HomeModel) {
        let s=try PracticePhaseTests().state()
        var h=s.sessions[0].initial.household
        h.contacts.append(.init(id:"contact2",role:.outOfAreaContact,alias:"Second synthetic contact",phone:"555-0101"))
        h.supplies.storedWaterGallons = .confirmed(3)
        return (h,try #require(s.sessions[1].initial.home))
    }
    @Test func candidatesCoverEveryCompetencyWithCoreConsequences()throws {
        let (h,home)=try fixture()
        let pool=PracticeSetPlanner.candidates(household:h,home:home,contentVersion:"test",library:SimFixtures.library)
        for c in ScoreCompiler.competencies {#expect(pool.contains{$0.competency==c},"missing \(c): \(pool.map(\.id))")}
        #expect(pool.allSatisfy{$0.options.count>=2 && $0.options.contains{$0.credit==1}})
        #expect(Set(pool.map(\.scenarioID)).count>=3)
        #expect(PracticeSetPlanner.candidates(household:h,home:nil,contentVersion:"test",library:SimFixtures.library).isEmpty)
    }
    @Test func deterministicPlansVaryPerAttemptAndVerifyAndScore()throws {
        let (h,home)=try fixture()
        let pool=PracticeSetPlanner.candidates(household:h,home:home,contentVersion:"test",library:SimFixtures.library)
        let plans=try (0..<6).map{try #require(PracticeSetPlanner.deterministicPlan(attemptIndex:$0,household:h,home:home,contentVersion:"test",library:SimFixtures.library,candidates:pool))}
        #expect(Set(plans.map{$0.situations.map(\.candidateID)+$0.situations.flatMap{$0.options.map(\.id)}}).count>1)
        for plan in plans {try PracticeSetPlanner.verify(plan,household:h,home:home,contentVersion:"test",library:SimFixtures.library)}
        var changed=h;changed.contacts.removeLast()
        #expect(throws:SessionError.stale){try PracticeSetPlanner.verify(plans[0],household:changed,home:home,contentVersion:"test",library:SimFixtures.library)}
        // Begin and answer the plan with each situation's credited option; Core grades as precomputed.
        let plan=plans[0]
        var state=IntegratedAIState()
        let sources=try PracticeSetPlanner.prepare(plan,attemptID:"p3",household:h,home:home,contentVersion:"test",library:SimFixtures.library)
        state.sessions=sources
        #expect(throws:SessionError.invalidCommand){var copy=state;try copy.beginPracticeCheck(id:"p3",variantID:plan.variantID,sessionIDs:sources.map(\.id),library:SimFixtures.library)}
        try state.beginPracticeCheck(id:"p3",variantID:plan.variantID,sessionIDs:sources.map(\.id),library:SimFixtures.library,plan:plan)
        for (i,s) in plan.situations.enumerated() {
            let option=try #require(s.options.first{$0.credit==1})
            let active=try #require(try state.activePracticeCheckSession(attemptID:"p3",library:SimFixtures.library))
            let o=try state.submitPracticeAction(attemptID:"p3",competencyID:s.competency,commit:.init(id:"a\(i)",actor:"user",baseRevision:active.revision,commands:[option.command]),library:SimFixtures.library)
            #expect(o.credit==option.credit)
        }
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(restored.practiceAttempts[0].plan==plan)
        #expect(try PracticePhaseTests().score(restored).practiceAssessed==4)
    }
    @Test func proposalsAreAdoptedOnlyFromCoreCandidates()throws {
        let (h,home)=try fixture()
        let pool=PracticeSetPlanner.candidates(household:h,home:home,contentVersion:"test",library:SimFixtures.library)
        let base=try #require(PracticeSetPlanner.deterministicPlan(attemptIndex:1,household:h,home:home,contentVersion:"test",library:SimFixtures.library,candidates:pool))
        func proposal(_ edit:(inout [PracticePlanProposal.Situation])->Void={_ in})->PracticePlanProposal {
            var s=base.situations.map{PracticePlanProposal.Situation(competency:$0.competency,candidateID:$0.candidateID,prompt:"What do you do first?",options:$0.options.prefix(3).map{.init(id:$0.id,label:"Option",feedback:"Plain feedback.")})}
            for i in s.indices {
                let ids=Set(s[i].options.map(\.id))
                if let right=base.situations[i].options.first(where:{$0.credit==1}),!ids.contains(right.id) { s[i].options[0] = .init(id:right.id,label:"Option",feedback:"Plain feedback.")}
            }
            edit(&s);return .init(situations:s)
        }
        let adopted=try PracticeSetPlanner.adopt(proposal(),attemptIndex:1,servedBy:"codex",household:h,home:home,contentVersion:"test",library:SimFixtures.library,candidates:pool)
        try PracticeSetPlanner.verify(adopted,household:h,home:home,contentVersion:"test",library:SimFixtures.library)
        #expect(adopted.situations.allSatisfy{$0.prompt != nil && $0.options.allSatisfy{$0.label != nil}})
        let bad:[(inout [PracticePlanProposal.Situation])->Void]=[
            {$0[0].candidateID="invented.hazard"},
            {$0[0].options[0].id="move.someone.roof"},
            {$0.swapAt(0,1)},
            {$0[0].options=[$0[0].options[0]]},
            {$0[0].prompt=String(repeating:"x",count:500)},
            {$0[0].options[0].label="Use eq-123 now"},
            {$0[1].options.append($0[1].options[0])},
        ]
        for edit in bad {#expect(throws:SessionError.invalidCommand){try PracticeSetPlanner.adopt(proposal(edit),attemptIndex:1,servedBy:"codex",household:h,home:home,contentVersion:"test",library:SimFixtures.library,candidates:pool)}}
    }
}
