import Foundation
import Testing
@testable import DryRunCore

@Suite("Retiring hazard checks and local score refresh") struct HazardPracticeChecksTests {
    func rubric()throws->RubricDefinition {try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))}
    @Test func retirementRelaunchAndIndependentCompetencyRefresh()throws {
        let water=try SixHazardExperienceTests().session("water-outage")
        let fire=try SixHazardExperienceTests().session("tornado")
        var state=IntegratedAIState(sessions:[water,fire])
        try state.beginHazardCheck(id:"water",checkID:"water.activity/1",sessionID:water.id,library:SimFixtures.library)
        let first=try state.submitHazardCheck(attemptID:"water",commit:.init(id:"water-first",actor:"user",baseRevision:water.revision,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        #expect(first.credit==1);#expect(!first.feedbackRevealed)
        #expect(!state.pendingHazardChecks.contains{$0.id=="water.activity/1"})
        #expect(state.scorecards.last?.practice==25.0/3.0)
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(restored.pendingHazardChecks==state.pendingHazardChecks)
        #expect(try restored.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==25.0/3.0)
        try state.beginHazardCheck(id:"account",checkID:"tornado.alert/1",sessionID:fire.id,library:SimFixtures.library)
        // Premature accounting is infeasible; it is captured as an unsuccessful first response.
        let failed=try state.submitHazardCheck(attemptID:"account",commit:.init(id:"premature",actor:"user",baseRevision:0,commands:[.init(kind:"accountOutside",target:fire.initial.household.people[0].id)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        #expect(failed.credit==0);#expect(state.scorecards.last?.practice==25.0/3.0)
        #expect(state.scorecards.last?.practiceAssessed==2)
        #expect(state.sessions[1].commits.last?.commands[0].kind=="unsupported")
        #expect(throws:SessionError.invalidCommand){try state.submitHazardCheck(attemptID:"account",commit:.init(id:"again",actor:"user",baseRevision:1,commands:[.init(kind:"finish")]),library:SimFixtures.library,rubric:rubric(),assessments:[])}
    }
    @Test func failedWriteRetainsQueueBalanceAndScoreAndForgeryIsRejected()throws {
        let session=try SixHazardExperienceTests().session("water-outage")
        var state=IntegratedAIState(sessions:[session])
        try state.beginHazardCheck(id:"check",checkID:"water.activity/1",sessionID:session.id,library:SimFixtures.library)
        let before=try DryRunJSON.encoder().encode(state)
        let action=SessionCommit(id:"consume",actor:"user",baseRevision:0,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:1)])
        #expect(throws:SessionError.persistence){try state.submitHazardCheck(attemptID:"check",commit:action,library:SimFixtures.library,rubric:rubric(),assessments:[],persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(state)==before)
        _=try state.submitHazardCheck(attemptID:"check",commit:action,library:SimFixtures.library,rubric:rubric(),assessments:[])
        state.practiceAttempts[0].observations![0].credit=0
        #expect(throws:SessionError.invalidCommand){try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)}
    }
    @Test func bankCoversAllHazardsWithDifferentExecutableActions() {
        #expect(Set(HazardPracticeCheck.bank.map(\.scenarioID)).count==6)
        #expect(Set(HazardPracticeCheck.bank.map(\.actionKind)).count>=9)
        #expect(HazardPracticeCheck.bank.count==12)
    }
}

extension HazardPracticeChecksTests {
    @Test func completedFirstResponseSurvivesContinuedExerciseAndFinish()throws {
        let session=try SixHazardExperienceTests().session("water-outage")
        var state=IntegratedAIState(sessions:[session])
        try state.beginHazardCheck(id:"first",checkID:"water.activity/1",sessionID:session.id,library:SimFixtures.library)
        let observation=try state.submitHazardCheck(attemptID:"first",commit:.init(id:"first-use",actor:"user",baseRevision:0,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let prior=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)
        let before=try state.sessions[0].query(library:SimFixtures.library)
        _=try state.sessions[0].commit(.init(id:"later-use",actor:"user",baseRevision:1,commands:[.init(kind:"useWater",target:"recordedStored",value:"hygiene",quantityLiters:1)]),library:SimFixtures.library)
        _=try state.sessions[0].commit(.init(id:"later-finish",actor:"director",baseRevision:2,commands:[.init(kind:"finish")]),library:SimFixtures.library)
        let final=try state.sessions[0].query(library:SimFixtures.library)
        #expect(final.finished);#expect(final.snapshot.resources != before.snapshot.resources)
        #expect(try state.validateHazardCheck(state.practiceAttempts[0],library:SimFixtures.library).answers.first?.credit==1)
        #expect(try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==prior.practice)
        #expect(state.practiceAttempts[0].observations?.first==observation)
        #expect(!state.pendingHazardChecks.contains{$0.id=="water.activity/1"})
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(try restored.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==prior.practice)
        var forged=restored
        forged.practiceAttempts[0].observations![0].receiptDigest=final.contextDigest
        #expect(throws:SessionError.invalidCommand){try forged.validateHazardCheck(forged.practiceAttempts[0],library:SimFixtures.library)}
    }
    @Test func laterCorrectActionCannotRewriteAnUnsuccessfulFirstResponse()throws {
        let session=try SixHazardExperienceTests().session("water-outage")
        var state=IntegratedAIState(sessions:[session])
        try state.beginHazardCheck(id:"wrong",checkID:"water.activity/1",sessionID:session.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"wrong",commit:.init(id:"first-wrong",actor:"user",baseRevision:0,commands:[.init(kind:"unsupported")]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        _=try state.sessions[0].commit(.init(id:"coached-correct",actor:"user",baseRevision:1,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library)
        #expect(try state.validateHazardCheck(state.practiceAttempts[0],library:SimFixtures.library).answers.first?.credit==0)
        #expect(try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==0)
    }
    @Test func unansweredAttemptCannotCaptureAfterAnUnobservedRevisionChange()throws {
        let session=try SixHazardExperienceTests().session("water-outage")
        var state=IntegratedAIState(sessions:[session])
        try state.beginHazardCheck(id:"pending",checkID:"water.activity/1",sessionID:session.id,library:SimFixtures.library)
        _=try state.sessions[0].commit(.init(id:"intervening-director",actor:"director",baseRevision:0,commands:[.init(kind:"requestDecision")]),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try state.validateHazardCheck(state.practiceAttempts[0],library:SimFixtures.library)}
    }
    @Test func dependencyFingerprintsIgnoreRenamesAndScopeMedicationStorageToContinuity()throws {
        let h=SampleHouseholds.oak,home=SampleHomes.ranch
        let power=try #require(HazardPracticeCheck.bank.first{$0.id=="freeze.power/1"})
        let escape=try #require(HazardPracticeCheck.bank.first{$0.id=="fire.escape/1"})
        let contact=try #require(HazardPracticeCheck.bank.first{$0.id=="tornado.alert/1"})
        var renamed=h;renamed.people[0].alias="A new display name";renamed.bumpRevision()
        for check in [power,escape,contact] {
            #expect(try IntegratedAIState.practiceDependencyFingerprint(check:check,household:h,home:home)==IntegratedAIState.practiceDependencyFingerprint(check:check,household:renamed,home:home))
        }
        var changed=h;changed.equipment[0].storageInstructions="Changed recorded manufacturer storage instruction"
        #expect(try IntegratedAIState.practiceDependencyFingerprint(check:power,household:h,home:home) != IntegratedAIState.practiceDependencyFingerprint(check:power,household:changed,home:home))
        for check in [escape,contact] {
            #expect(try IntegratedAIState.practiceDependencyFingerprint(check:check,household:h,home:home)==IntegratedAIState.practiceDependencyFingerprint(check:check,household:changed,home:home))
        }
    }
    @Test func intentionalRetestPreservesOtherHazardAnchorAndDoesNotUseBestResult()throws {
        let first=try SixHazardExperienceTests().session("water-outage")
        // A distinct exercise ID is required for each frozen first response.
        let second=try SimulationSession.initialize(id:"water-retest",initial:first.initial,library:SimFixtures.library)
        var state=IntegratedAIState(sessions:[first,second])
        try state.beginHazardCheck(id:"first",checkID:"water.activity/1",sessionID:first.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"first",commit:.init(id:"correct",actor:"user",baseRevision:0,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let previous=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)
        #expect(previous.practice==25.0/3.0)
        try state.beginHazardCheck(id:"retest",checkID:"water.activity/1",sessionID:second.id,library:SimFixtures.library,retest:true)
        #expect(state.practiceAttempts.last?.checkVariant=="b")
        #expect(try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==previous.practice)
        _=try state.submitHazardCheck(attemptID:"retest",commit:.init(id:"wrong",actor:"user",baseRevision:0,commands:[.init(kind:"unsupported")]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        #expect(state.scorecards.last?.practice==0)
        #expect(state.practiceAttempts[0].observations?.first?.credit==1)
        #expect(state.practiceAttempts[1].observations?.first?.credit==0)
        #expect(state.scorecards.last?.practiceHazardsAssessed==["water-outage"])
        #expect(abs((state.scorecards.last?.practiceAnchorCoverage ?? 0)-100.0/12.0)<1e-10)
    }
}

extension HazardPracticeChecksTests {
    @Test func sourceEditReopensOnlyDependentCheckAndRefreshesCurrentScore()throws {
        let water=try SixHazardExperienceTests().session("water-outage")
        let tornado=try SixHazardExperienceTests().session("tornado")
        var state=IntegratedAIState(sessions:[water,tornado])
        try state.beginHazardCheck(id:"water-current",checkID:"water.activity/1",sessionID:water.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"water-current",commit:.init(id:"water-answer",actor:"user",baseRevision:0,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let shelter=try #require(tornado.query(library:SimFixtures.library).experience?.feasibleCommands?.first{$0.kind=="reachShelter"})
        try state.beginHazardCheck(id:"tornado-current",checkID:"tornado.shelter/1",sessionID:tornado.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"tornado-current",commit:.init(id:"shelter-answer",actor:"user",baseRevision:0,commands:[shelter]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let prior=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)
        var changed=water.initial.household
        changed.supplies.storedWaterGallons = .confirmed(0)
        changed.bumpRevision()
        let pending=try state.pendingHazardChecks(household:changed,home:water.initial.home)
        #expect(pending.contains{$0.id=="water.activity/1"})
        #expect(!pending.contains{$0.id=="tornado.shelter/1"})
        let current=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library,currentHousehold:changed,currentHome:water.initial.home)
        #expect(abs(prior.practice-current.practice-25.0/3.0)<1e-10)
        #expect(state.practiceAttempts.count==2)
        #expect(state.practiceAttempts.allSatisfy{$0.observations?.first?.credit==1})
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(try restored.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library,currentHousehold:changed,currentHome:water.initial.home).practice==current.practice)
    }
    @Test func explicitRetestCannotBypassSituationalPrerequisites()throws {
        let session=try SixHazardExperienceTests().session("freeze-power-loss")
        var state=IntegratedAIState(sessions:[session])
        #expect(throws:SessionError.invalidCommand){try state.beginHazardCheck(id:"premature",checkID:"freeze.power/1",sessionID:session.id,library:SimFixtures.library,retest:true)}
        #expect(state.practiceAttempts.isEmpty)
    }
}

extension HazardPracticeChecksTests {
    @Test func supportedMechanicsVersionsRetainIndependentPracticeEvidenceAfterRelaunch()throws {
        let current=try SixHazardExperienceTests().session("water-outage")
        let legacy=SimulationSession(id:"recorded-v1-water",initial:current.initial,directorPolicy:current.directorPolicy,mechanicsVersion:"dryrun.hazard-mechanics/1")
        let tornado=try SixHazardExperienceTests().session("tornado")
        var state=IntegratedAIState(sessions:[legacy,tornado])
        try state.beginHazardCheck(id:"legacy-answer",checkID:"water.activity/1",sessionID:legacy.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"legacy-answer",commit:.init(id:"v1-water-response",actor:"user",baseRevision:0,commands:[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let legacyScore=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)
        #expect(legacyScore.practice==25.0/3.0)
        let shelter=try #require(tornado.query(library:SimFixtures.library).experience?.feasibleCommands?.first{$0.kind=="reachShelter"})
        try state.beginHazardCheck(id:"current-answer",checkID:"tornado.shelter/1",sessionID:tornado.id,library:SimFixtures.library)
        _=try state.submitHazardCheck(attemptID:"current-answer",commit:.init(id:"v2-tornado-response",actor:"user",baseRevision:0,commands:[shelter]),library:SimFixtures.library,rubric:rubric(),assessments:[])
        let prior=try state.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library)
        let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(restored.sessions[0].mechanicsVersion=="dryrun.hazard-mechanics/1")
        #expect(try restored.validateHazardCheck(restored.practiceAttempts[0],library:SimFixtures.library).answers.first?.credit==1)
        #expect(try restored.compileScorecard(rubric:rubric(),assessments:[],library:SimFixtures.library).practice==prior.practice)
        #expect(prior.practice>legacyScore.practice)
        #expect(!restored.pendingHazardChecks.contains{$0.id=="water.activity/1" || $0.id=="tornado.shelter/1"})
    }
}
