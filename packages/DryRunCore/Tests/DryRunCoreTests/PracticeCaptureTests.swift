import Foundation
import Testing
@testable import DryRunCore

@Suite("Host-owned pre-feedback practice capture") struct PracticeCaptureTests {
    func state()throws->IntegratedAIState {
        var session=try SimulationSession.initialize(id:"practice",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),library:SimFixtures.library)
        try session.commit(.init(id:"outage",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        return IntegratedAIState(sessions:[session])
    }
    func begin(_ local:inout IntegratedAIState)throws {
        try local.beginPractice(id:"check",variantID:"practice-check-a/0",sessionID:"practice",library:SimFixtures.library)
    }
    func answer(_ local:inout IntegratedAIState,competency:String="initialResponse",id:String="answer",value:String="all")throws->PracticeObservation {
        try local.submitPracticeAction(attemptID:"check",competencyID:competency,
            commit:.init(id:id,actor:"user",baseRevision:local.sessions[0].revision,commands:[.init(kind:"useStoredWater",value:value)]),library:SimFixtures.library)
    }
    @Test func capturesBeforeFeedbackAndCannotRerollUnsafeAnswer()throws {
        var local=try state();try begin(&local)
        let captured=try answer(&local)
        #expect(captured.credit==0);#expect(!captured.feedbackRevealed)
        #expect(local.sessions[0].revision==2)
        #expect(local.practiceAttempts[0].answers[0].credit==0)
        try local.revealPracticeFeedback(attemptID:"check",actionID:"answer")
        let resumed=try local.beginPractice(id:"reroll",variantID:"practice-check-b/0",sessionID:"another",library:SimFixtures.library)
        #expect(resumed.id=="check");#expect(resumed.variantID=="practice-check-a/0")
        #expect(throws:SessionError.invalidCommand){try answer(&local,id:"changed",value:"essential")}
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(local))
        let eligible=try restored.eligiblePracticeAttempts(library:SimFixtures.library)
        #expect(eligible[0].answers[0].credit==0)
        #expect(restored.practiceAttempts[0].observations![0].feedbackRevealed)
    }
    @Test func atomicCapturePersistsNeitherActionNorGradeOnFailure()throws {
        var local=try state();try begin(&local)
        let before=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.persistence){
            try local.submitPracticeAction(attemptID:"check",competencyID:"initialResponse",commit:.init(id:"a",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})
        }
        #expect(try DryRunJSON.encoder().encode(local)==before)
        _=try answer(&local,value:"essential")
        let captured=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.persistence){try local.revealPracticeFeedback(attemptID:"check",actionID:"answer",persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(local)==captured)
    }
    @Test func unknownAnchorsRemainUnknownAndCoachingCannotEarnPoints()throws {
        var local=try state();try begin(&local)
        _=try answer(&local,value:"essential")
        // This submitted water action does not demonstrate adaptation. It is retained as unassessed.
        let unknown=try answer(&local,competency:"adaptation",id:"unassessed",value:"essential")
        #expect(unknown.credit==nil);#expect(local.practiceAttempts[0].observations?.count==2)
        #expect(local.practiceAttempts[0].answers.count==1)
        try local.revealPracticeFeedback(attemptID:"check",actionID:"answer",coached:true)
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let score=try local.compileScorecard(rubric:rubric,assessments:[],library:SimFixtures.library)
        #expect(score.practice==0);#expect(score.practiceAssessed==0)
    }
    @Test func alteredCreditSourceOrReceiptCannotPassRevalidation()throws {
        var local=try state();try begin(&local);_=try answer(&local,value:"essential")
        var changed=local;changed.practiceAttempts[0].observations![0].credit=0
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local;changed.practiceAttempts[0].observations![0].receiptDigest="other"
        #expect(throws:SessionError.stale){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local;changed.practiceAttempts[0].source!.initialDigest="other"
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local;changed.practiceAttempts[0].answers[0].credit=0
        // The scalar answer is ignored and reconstructed from the actual captured action.
        #expect(try changed.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers[0].credit==1)
    }
    @Test func oldCallerFlagsHaveNoEligibilityAndFreshCheckNeedsFreshSession()throws {
        var trained=try state()
        try trained.sessions[0].commit(.init(id:"training",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try trained.beginPractice(id:"relabel",variantID:"practice-check-a/0",sessionID:"practice",library:SimFixtures.library)}
        let legacy=PracticeAttempt(id:"old",sequence:1,variantID:"practice-check-a/0",answers:[.init(competencyID:"initialResponse",credit:1,committedActionID:"pretend",beforeFeedback:true)])
        let local=IntegratedAIState(practiceAttempts:[legacy])
        #expect(try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers.isEmpty)
        var migrating=try state();migrating.practiceAttempts=[legacy]
        try migrating.archiveUnverifiedPractice(attemptID:"old")
        let fresh=try migrating.beginPractice(id:"migrated",variantID:"practice-check-b/0",sessionID:"practice",library:SimFixtures.library)
        #expect(fresh.sequence==2);#expect(migrating.practiceAttempts[0].answers.count==1)
        #expect(throws:SessionError.invalidCommand){try migrating.archiveUnverifiedPractice(attemptID:"migrated")}
        var current=try state();try begin(&current)
        _=try answer(&current,value:"essential")
        for competency in ["adaptation","communication","continuity"] {_=try answer(&current,competency:competency,id:competency)}
        #expect(throws:SessionError.invalidCommand){try current.beginPractice(id:"repeat",variantID:"practice-check-b/0",sessionID:"practice",library:SimFixtures.library)}
        var newSession=current.sessions[0].initial
        newSession.seed=9
        current.sessions.append(try SimulationSession.initialize(id:"retest",initial:newSession,library:SimFixtures.library))
        let retest=try current.beginPractice(id:"repeat",variantID:"practice-check-b/0",sessionID:"retest",library:SimFixtures.library)
        #expect(retest.sequence==2)
        #expect(try current.eligiblePracticeAttempts(library:SimFixtures.library).last?.answers.isEmpty==true)
    }
    @Test func genericSessionActionsCannotBeHiddenBeforeScoredAnswers()throws {
        var local=try state();try begin(&local)
        try local.sessions[0].commit(.init(id:"unscored-first-response",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"all")]),library:SimFixtures.library)
        let original=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.invalidCommand){try answer(&local,id:"improved",value:"essential")}
        #expect(try DryRunJSON.encoder().encode(local)==original)
        #expect(throws:SessionError.invalidCommand){try local.eligiblePracticeAttempts(library:SimFixtures.library)}
        // Moving the declared start past the hidden action must not make it eligible either.
        local.practiceAttempts[0].source!.startingRevision=2
        #expect(throws:SessionError.invalidCommand){try local.eligiblePracticeAttempts(library:SimFixtures.library)}
    }
    @Test func completedCheckAllowsLaterTrainingWithoutRewritingAnswers()throws {
        var local=try state();try begin(&local)
        _=try answer(&local,value:"all")
        for competency in ["adaptation","communication","continuity"] {_=try answer(&local,competency:competency,id:competency)}
        let before=try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers
        try local.sessions[0].commit(.init(id:"later-training",actor:"user",baseRevision:local.sessions[0].revision,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)
        let after=try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers
        #expect(before.map(\.credit)==after.map(\.credit));#expect(after.first?.credit==0)
    }

    @Test func concernHypothesesCannotBecomeApprovedPracticeVariants()throws {
        let fixtures=ConcernIntegrationTests()
        var local=IntegratedAIState()
        try fixtures.review(&local,decision:.uncertain)
        let portal=try #require(SimFixtures.home.portals.first{$0.sideA == .space("sp-living") && $0.sideB == .exterior || $0.sideB == .space("sp-living") && $0.sideA == .exterior})
        let seed=try local.concernExerciseSeed(concernID:"concern",scenarioID:"home-fire",selectedPortalIDs:[portal.id],allowHypothetical:true,home:SimFixtures.home)
        local.sessions=[try SimulationSession.initialize(id:"hypothesis",initial:SimFixtures.input(SampleHouseholds.oak,"home-fire"),library:SimFixtures.library,concernSeed:seed)]
        let before=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.invalidCommand){try local.beginPractice(id:"not-equivalent",variantID:"practice-check-a/0",sessionID:"hypothesis",library:SimFixtures.library)}
        #expect(try DryRunJSON.encoder().encode(local)==before)
        // The educational exercise remains runnable and retains its explicit assumption.
        #expect(try local.sessions[0].query(library:SimFixtures.library).revision==0)
        #expect(local.sessions[0].concernSeed?.hypotheticalPermission==true)
    }

}
