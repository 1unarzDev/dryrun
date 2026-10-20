import Foundation
import Testing
@testable import DryRunCore

@Suite("Computed fire accompaniment") struct FireAccompanimentTests {
    func input() -> RehearsalInput {
        var input=SimFixtures.input(SampleHouseholds.oak,"home-fire")
        input.household.people=Array(input.household.people.prefix(3))
        for i in input.household.people.indices {input.household.people[i].sleepingSpaceID="sp-bed1";input.household.people[i].helperPersonID=nil}
        input.household.people[2].helperPersonID=input.household.people[0].id
        input.household.people[2].needs.append(.needsHelperToEvacuate)
        return input
    }
    func act(_ session:inout SimulationSession,_ commands:[SessionCommand])throws->SessionReceipt {
        try session.commit(.init(id:"action-\(session.revision)",actor:"user",baseRevision:session.revision,commands:commands),library:SimFixtures.library)
    }
    @Test func accompanimentMovesBothPeopleThroughTheExactExitWithoutAutomaticAccounting()throws {
        let input=input(),person=input.household.people[2].id,helper=input.household.people[0].id
        var session=try SimulationSession.initialize(id:"paired-escape",initial:input,library:SimFixtures.library)
        let before=try session.query(library:SimFixtures.library)
        let command=try #require(before.experience?.feasibleCommands?.first{$0.kind=="accompanyEscape" && $0.target==person})
        #expect(before.experience?.feasibleCommands?.contains{$0.kind=="escape" && $0.target==person}==false)
        #expect(throws:SessionError.invalidCommand){try act(&session,[.init(kind:"escape",target:person,value:command.value)])}
        let after=try act(&session,[command])
        #expect(Set(after.experience?.outsidePersonIDs ?? [])==Set([person,helper]))
        #expect(after.experience?.accountedPersonIDs.isEmpty==true)
        #expect(after.experience?.escapeHelperByPersonID==[person:helper])
        #expect(after.experience?.occupantRoomIDs[person]=="exterior")
        #expect(after.routes.filter{[person,helper].contains($0.request.personID)}.allSatisfy{$0.primary?.exitPortalID==command.value})
        #expect(after.experience?.debrief.contains{$0.kind=="recordedAssistedEscape" && Set($0.subjectIDs)==Set([person,helper])}==true)
        let replay=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(session))
        #expect(try replay.query(library:SimFixtures.library)==after)
        #expect(throws:SessionError.invalidCommand){try act(&session,[command])}
    }
    @Test func leavingAloneRemovesTheHelpersAbilityToReenterForAnotherPerson()throws {
        let input=input(),person=input.household.people[2].id,helper=input.household.people[0].id
        var session=try SimulationSession.initialize(id:"helper-left",initial:input,library:SimFixtures.library)
        let before=try session.query(library:SimFixtures.library)
        let command=try #require(before.experience?.feasibleCommands?.first{$0.kind=="escape" && $0.target==helper})
        let after=try act(&session,[command])
        #expect(after.experience?.openGapIDs.contains("escapeAssistance."+person)==true)
        #expect(after.experience?.feasibleCommands?.contains{$0.kind=="accompanyEscape" && $0.target==person}==false)
        #expect(after.assistance?.first{$0.personID==person}?.reachStatus == .unreachable)
        #expect(after.experience?.escapeHelperByPersonID?.isEmpty==true)
        #expect(throws:SessionError.invalidCommand){try act(&session,[.init(kind:"accompanyEscape",target:person,value:command.value)])}
        #expect(try session.query(library:SimFixtures.library)==after)
    }
    @Test func missingApproachAndFailedPersistenceCannotPartiallyMoveAnyone()throws {
        var input=input();let person=input.household.people[2].id
        input.household.people[0].sleepingSpaceID="unrecorded-room"
        var blocked=try SimulationSession.initialize(id:"missing-helper-approach",initial:input,library:SimFixtures.library)
        let before=try blocked.query(library:SimFixtures.library)
        #expect(before.experience?.openGapIDs.contains("escapeAssistance."+person)==true)
        #expect(throws:SessionError.invalidCommand){try act(&blocked,[.init(kind:"accompanyEscape",target:person,value:"pt-front")])}
        #expect(try blocked.query(library:SimFixtures.library)==before)
        var session=try SimulationSession.initialize(id:"failed-write",initial:self.input(),library:SimFixtures.library)
        let valid=try session.query(library:SimFixtures.library)
        let command=try #require(valid.experience?.feasibleCommands?.first{$0.kind=="accompanyEscape"})
        #expect(throws:SessionError.persistence){try session.commit(.init(id:"write-failed",actor:"user",baseRevision:session.revision,commands:[command]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try session.query(library:SimFixtures.library)==valid)
    }
    @Test func historicalMechanicsFourNeverReinterpretsSoloEscape()throws {
        let input=input(),person=input.household.people[2].id
        var old=SimulationSession(id:"historical-four",initial:input,directorPolicy:.reviewed(SimFixtures.library.scenario("home-fire")!),mechanicsVersion:"dryrun.hazard-mechanics/4")
        let before=try old.query(library:SimFixtures.library)
        #expect(before.experience?.escapeHelperByPersonID==nil)
        #expect(before.experience?.feasibleCommands?.contains{$0.kind=="accompanyEscape"}==false)
        let escape=try #require(before.experience?.feasibleCommands?.first{$0.kind=="escape" && $0.target==person})
        #expect(throws:SessionError.invalidCommand){try act(&old,[.init(kind:"accompanyEscape",target:person,value:escape.value)])}
        #expect(try act(&old,[escape]).experience?.outsidePersonIDs==[person])
    }
}

extension FireAccompanimentTests {
    @Test func composedEscapeRetiresTheExistingAnchorWithOnePersistedCredit()throws {
        let session=try SimulationSession.initialize(id:"scored-pair",initial:input(),library:SimFixtures.library)
        let receipt=try session.query(library:SimFixtures.library)
        let action=try #require(receipt.experience?.feasibleCommands?.first{$0.kind=="accompanyEscape"})
        var state=IntegratedAIState(sessions:[session])
        let attempt=try state.beginHazardCheck(id:"assisted-response",checkID:"fire.escape/1",sessionID:session.id,library:SimFixtures.library)
        #expect(attempt.source?.evaluatorVersion=="dryrun.hazard-checks/2")
        let commit=SessionCommit(id:"pair-answer",actor:"user",baseRevision:0,commands:[action])
        let rubric=try HazardPracticeChecksTests().rubric()
        let observation=try state.submitHazardCheck(attemptID:attempt.id,commit:commit,library:SimFixtures.library,rubric:rubric,assessments:[])
        #expect(observation.credit==1)
        #expect(state.pendingHazardChecks.contains{$0.id=="fire.escape/1"}==false)
        #expect(state.scorecards.last?.practice==25.0/3.0)
        #expect(HazardPracticeCheck.bank.count==12)
        let decoded=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(state))
        #expect(try decoded.compileScorecard(rubric:rubric,assessments:[],library:SimFixtures.library).practice==state.scorecards.last?.practice)
        #expect(throws:SessionError.invalidCommand){try state.submitHazardCheck(attemptID:attempt.id,commit:commit,library:SimFixtures.library,rubric:rubric,assessments:[])}
        state.practiceAttempts[0].source?.evaluatorVersion="dryrun.hazard-checks/1"
        #expect(throws:SessionError.invalidCommand){try state.compileScorecard(rubric:rubric,assessments:[],library:SimFixtures.library)}
    }
}

extension FireAccompanimentTests {
    @Test func completedShelterAndThermalActionsLeaveCurrentAffordances()throws {
        for (hazard,kind) in [("tornado","reachShelter"),("freeze-power-loss","warmLayers"),("heat-grid-strain","reduceSolarGain")] {
            var session=try SixHazardExperienceTests().session(hazard)
            let before=try session.query(library:SimFixtures.library)
            let action=try #require(before.experience?.feasibleCommands?.first{$0.kind==kind})
            let after=try act(&session,[action])
            #expect(after.experience?.feasibleCommands?.contains(action)==false)
            #expect(throws:SessionError.invalidCommand){try act(&session,[action])}
            #expect(try session.query(library:SimFixtures.library)==after)
        }
    }
    @Test func compoundChoicesUseIndependentProspectiveCopiesBeforeAnyPersistence()throws {
        let input=input(),person=input.household.people[2].id,helper=input.household.people[0].id
        var session=try SimulationSession.initialize(id:"compound-preview",initial:input,library:SimFixtures.library)
        let before=try session.query(library:SimFixtures.library)
        let accompany=try #require(before.experience?.feasibleCommands?.first{$0.kind=="accompanyEscape" && $0.target==person})
        let bad=SuggestedRehearsalAction(id:"bad-order",label:"Accompany the household",fact:"A helper is assigned.",implication:"The helper must approach before exiting.",commands:[.init(kind:"escape",target:helper,value:accompany.value),accompany])
        let good=SuggestedRehearsalAction(id:"paired",label:"Accompany the recorded member",fact:bad.fact,implication:bad.implication,commands:[accompany])
        var independent=good;independent.id="independent"
        let request=SessionToolRequest(kind:.validateSuggestedActions,baseRevision:session.revision,commands:[.init(kind:"requestDecision")],suggestedActions:[bad,good,independent])
        let checked=try session.executeTool(request,library:SimFixtures.library)
        #expect(checked.receipt==before)
        #expect(checked.suggestedActions?.map(\.feasible)==[false,true,true])
        #expect(checked.suggestedActions?.first?.rejection=="invalidCommand")
        #expect(checked.suggestedActions?[1].receipt?.experience?.outsidePersonIDs.sorted()==[person,helper].sorted())
        #expect(try session.query(library:SimFixtures.library)==before)
        var proposal=DirectorProposal(suggestedActions:[bad],id:"compound",actor:"director",baseRevision:0,commands:[.init(kind:"requestDecision")],purpose:"Ask for a computed action",evidenceIDs:[])
        let binding=AgentContextBinding(receipt:before,householdRevision:input.household.revision,homeRevision:input.home!.revision)
        var persisted=false
        #expect(throws:SessionError.invalidCommand){try proposal.commit(to:&session,binding:binding,library:SimFixtures.library,persist:{_ in persisted=true})}
        #expect(!persisted)
        #expect(try session.query(library:SimFixtures.library)==before)
        proposal.suggestedActions=[good]
        _=try proposal.commit(to:&session,binding:binding,library:SimFixtures.library,persist:{_ in persisted=true})
        #expect(persisted)
        #expect(try session.query(library:SimFixtures.library).experience?.outsidePersonIDs.isEmpty==true)
        #expect(session.revision==1) // only the director boundary, never the suggested movement
    }
}
