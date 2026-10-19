import Foundation
import Testing
@testable import DryRunCore

@Suite("Four frozen situations in one provisional practice check") struct PracticePhaseTests {
    func state()throws->IntegratedAIState {
        let geometry=try PracticeAdaptationTests().session().initial.home!
        var h=SampleHouseholds.oak
        h.people=Array(h.people.prefix(1));h.people[0].sleepingSpaceID="start"
        h.equipment=[.init(id:"device",purpose:.communicationDevice,label:"Synthetic device",personID:h.people[0].id,compatibleBackupIDs:["battery"],documentedBackupRuntimeHours:.confirmed(4),powerWatts:.confirmed(10))]
        h.backupPower=[.init(id:"battery",kind:.portableBatteryStation,label:"Synthetic battery",usableEnergyWh:.confirmed(100),continuousOutputW:.confirmed(100),setupConfirmed:.confirmed(true))]
        h.contacts=[.init(id:"contact",role:.outOfAreaContact,alias:"Synthetic contact",phone:"555-0100")]
        var sessions:[SimulationSession]=[]
        for (id,scenario,events) in [("initial","water-outage",["evt.water-outage.well-pump-failure"]),("adapt","home-fire",["evt.home-fire.alarm","evt.home-fire.fire-origin"]),("comms","water-outage",["evt.water-outage.well-pump-failure"]),("power","freeze-power-loss",["evt.freeze-power-loss.grid-loss"])] {
            var session=try SimulationSession.initialize(id:id,initial:SimFixtures.input(h,scenario,home:geometry),library:SimFixtures.library)
            for (n,event) in events.enumerated() {
                try session.commit(.init(id:"setup-\(id)-\(n)",actor:"director",baseRevision:session.revision,commands:[.init(kind:"schedule",target:event,minute:n),.init(kind:"advance",minute:n)]),library:SimFixtures.library)
            }
            sessions.append(session)
        }
        return IntegratedAIState(sessions:sessions)
    }
    func begin(_ state:inout IntegratedAIState)throws {
        try state.beginPracticeCheck(id:"check",variantID:"practice-check-a/1",sessionIDs:["initial","adapt","comms","power"],library:SimFixtures.library)
    }
    func answer(_ state:inout IntegratedAIState,_ index:Int,wrong:Bool=false)throws {
        let kinds=["initialResponse","adaptation","communication","continuity"]
        let commands:[SessionCommand]=[.init(kind:"useStoredWater",value:wrong ? "all":"essential"),.init(kind:"moveTo",target:state.sessions[1].initial.household.people[0].id,value:"living"),.init(kind:"contact",target:"contact"),.init(kind:"allocatePower",target:"device",value:"battery")]
        try state.submitPracticeAction(attemptID:"check",competencyID:kinds[index],commit:.init(id:"answer-\(index)",actor:"user",baseRevision:state.sessions[index].revision,commands:[commands[index]]),library:SimFixtures.library)
    }
    func score(_ state:IntegratedAIState)throws->PreparednessScorecard {
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        return try state.compileScorecard(rubric:rubric,assessments:[],library:SimFixtures.library)
    }
    @Test func allFourCompetenciesAreActuallyExecutableAndReplayBeforeFeedback()throws {
        var local=try state();let original=local.sessions.map(\.initial);try begin(&local)
        for index in 0..<4 {
            #expect(try local.activePracticeCheckSession(attemptID:"check",library:SimFixtures.library)?.id==local.sessions[index].id)
            try answer(&local,index)
            #expect(local.practiceAttempts[0].observations?.last?.credit==1)
            #expect(local.practiceAttempts[0].observations?.last?.feedbackRevealed==false)
            let card=try score(local)
            #expect(card.practice==Double(index+1)*25);#expect(card.practiceAssessed==index+1);#expect(card.provisional)
            local=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(local))
            #expect(try score(local).practice==Double(index+1)*25)
        }
        #expect(try local.activePracticeCheckSession(attemptID:"check",library:SimFixtures.library)==nil)
        #expect(local.sessions.map(\.initial)==original)
        #expect(try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers.count==4)
    }
    @Test func interruptionsCannotRerollWrongFirstAnswerOrFutureSituations()throws {
        var local=try state();try begin(&local);try answer(&local,0,wrong:true)
        let resumed=try local.beginPracticeCheck(id:"reroll",variantID:"practice-check-b/1",sessionIDs:[],library:SimFixtures.library)
        #expect(resumed.id=="check");#expect(resumed.variantID=="practice-check-a/1")
        #expect(try score(local).practice==0);#expect(try score(local).practiceAssessed==1)
        try answer(&local,1);try answer(&local,2);try answer(&local,3)
        #expect(try score(local).practice==75);#expect(try score(local).practiceAssessed==4)
        #expect(local.practiceAttempts[0].observations?[0].credit==0)
        #expect(throws:SessionError.invalidCommand){try local.submitPracticeAction(attemptID:"check",competencyID:"initialResponse",commit:.init(id:"retry",actor:"user",baseRevision:local.sessions[0].revision,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)}
    }
    @Test func tamperedSourcesCreditsAndUncapturedActionsFailRevalidation()throws {
        var local=try state();try begin(&local);try answer(&local,0)
        var changed=local;changed.practiceAttempts[0].observations![0].credit=0
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local;changed.practiceAttempts[0].phaseSources![1].initialDigest="changed"
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local
        try changed.sessions[2].commit(.init(id:"uncaptured",actor:"user",baseRevision:changed.sessions[2].revision,commands:[.init(kind:"contact",target:"contact")]),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local
        try changed.sessions[1].commit(.init(id:"difficulty-reroll",actor:"director",baseRevision:changed.sessions[1].revision,commands:[.init(kind:"advance",minute:2)]),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try changed.eligiblePracticeAttempts(library:SimFixtures.library)}
        changed=local;changed.practiceAttempts[0].variantID="invented"
        #expect(throws:SessionError.invalidCommand){try answer(&changed,1)}
    }
    @Test func saveFailureAndOutOfOrderSubmissionsPublishNothing()throws {
        var local=try state();try begin(&local);let original=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.invalidCommand){try local.submitPracticeAction(attemptID:"check",competencyID:"communication",commit:.init(id:"skip",actor:"user",baseRevision:local.sessions[2].revision,commands:[.init(kind:"contact",target:"contact")]),library:SimFixtures.library)}
        #expect(throws:SessionError.persistence){try local.submitPracticeAction(attemptID:"check",competencyID:"initialResponse",commit:.init(id:"save",actor:"user",baseRevision:local.sessions[0].revision,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(local)==original)
        var fresh=try state();let freshOriginal=try DryRunJSON.encoder().encode(fresh)
        #expect(throws:SessionError.persistence){try fresh.beginPracticeCheck(id:"check",variantID:"practice-check-a/1",sessionIDs:["initial","adapt","comms","power"],library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(fresh)==freshOriginal)
    }
    @Test func newerIncompleteEquivalentVariantSupersedesCompletedHistory()throws {
        var local=try state();try begin(&local)
        for index in 0..<4 {try answer(&local,index)}
        #expect(try score(local).practice==100)
        var fresh=try state()
        fresh.sessions=try fresh.sessions.map{session in
            var renamed=SimulationSession(id:session.id+"-new",initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed,dependencyPolicy:session.dependencyPolicy)
            for commit in session.commits {try renamed.commit(commit,library:SimFixtures.library)}
            return renamed
        }
        local.sessions += fresh.sessions
        try local.beginPracticeCheck(id:"later",variantID:"practice-check-b/1",sessionIDs:["power-new","comms-new","adapt-new","initial-new"],library:SimFixtures.library)
        #expect(try score(local).practice==0);#expect(try score(local).practiceAssessed==0)
        let power=try #require(local.sessions.first{$0.id=="power-new"})
        try local.submitPracticeAction(attemptID:"later",competencyID:"continuity",commit:.init(id:"later-none",actor:"user",baseRevision:power.revision,commands:[.init(kind:"allocatePower",target:"device",value:"none")]),library:SimFixtures.library)
        #expect(try score(local).practice==0);#expect(try score(local).practiceAssessed==1)
        #expect(try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers.count==4)
    }
    @Test func missingPhaseMetadataReusedSourcesAndUnknownActionsCannotManufactureCredit()throws {
        var local=try state();try begin(&local);try answer(&local,0)
        var stripped=local;stripped.practiceAttempts[0].phaseSources=nil
        #expect(throws:SessionError.invalidCommand){try stripped.eligiblePracticeAttempts(library:SimFixtures.library)}
        try local.submitPracticeAction(attemptID:"check",competencyID:"adaptation",commit:.init(id:"unsupported",actor:"user",baseRevision:local.sessions[1].revision,commands:[.init(kind:"unsupported")]),library:SimFixtures.library)
        #expect(local.practiceAttempts[0].observations?.last?.credit==nil)
        try answer(&local,2);try answer(&local,3)
        #expect(try score(local).practice==75);#expect(try score(local).practiceAssessed==3)
        #expect(throws:SessionError.invalidCommand){try local.beginPracticeCheck(id:"reuse",variantID:"practice-check-a/1",sessionIDs:["initial","adapt","comms","power"],library:SimFixtures.library)}
    }

}
