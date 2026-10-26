import Foundation
import Testing
@testable import DryRunCore

@Suite("Versioned non-device practice anchors") struct PracticeNonDeviceTests {
    func water(_ amount:Double?=1)throws->SimulationSession {
        var h=SampleHouseholds.oak;h.people=Array(h.people.prefix(1));h.equipment=[];h.backupPower=[]
        h.supplies.storedWaterGallons=amount.map{.confirmed($0)} ?? .unknown
        var s=try SimulationSession.initialize(id:"water",initial:SimFixtures.input(h,"water-outage"),library:SimFixtures.library)
        try s.commit(.init(id:"outage",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        return s
    }
    func use(_ source:SimulationSession,_ value:String)throws->SimulationSession {
        var s=source;try s.commit(.init(id:"answer",actor:"user",baseRevision:s.revision,commands:[.init(kind:"useStoredWater",value:value)]),library:SimFixtures.library);return s
    }
    @Test func conservationCreditUsesTwoHostProjectionsWithoutCommittingEither()throws {
        for amount in [1.0,0.01] {
            let source=try water(amount)
            for (policy,credit) in [("essential",1.0),("all",0.0)] {
                let s=try use(source,policy),original=try DryRunJSON.encoder().encode(s)
                #expect(try PracticeEvaluator.evaluate(competencyID:"continuity",actionID:"answer",session:s,library:SimFixtures.library).credit==credit)
                #expect(try DryRunJSON.encoder().encode(s)==original)
                #expect(try s.query(library:SimFixtures.library).snapshot.simMinute==0)
                #expect(try s.query(library:SimFixtures.library).snapshot.resources["res.water.stored"]?.amount==amount)
                #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"continuity",actionID:"answer",session:s,library:SimFixtures.library,evaluatorVersion:PracticeEvaluator.previousVersion)}
            }
        }
        for amount:Double? in [nil,0] {
            let s=try use(water(amount),"essential")
            #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"continuity",actionID:"answer",session:s,library:SimFixtures.library)}
        }
    }
    @Test func firstFireDecisionCreditsIntentNotMobilityAndRejectsUnsafeOptions()throws {
        for (value,credit) in [("get-out",1.0),("grab-belongings",0.0),("find-pet",0.0),("fight-fire",0.0)] {
            var input=SimFixtures.input(SampleHouseholds.oak,"home-fire");input.home=nil
            var s=try SimulationSession.initialize(id:"fire",initial:input,library:SimFixtures.library)
            try s.commit(.init(id:"alarm",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
            try s.commit(.init(id:"answer",actor:"user",baseRevision:1,commands:[.init(kind:"choose",target:"choice.home-fire.first-move",value:value)]),library:SimFixtures.library)
            #expect(try PracticeEvaluator.evaluate(competencyID:"initialResponse",actionID:"answer",session:s,library:SimFixtures.library).credit==credit)
            #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"initialResponse",actionID:"answer",session:s,library:SimFixtures.library,evaluatorVersion:PracticeEvaluator.previousVersion)}
        }
        var premature=try SimulationSession.initialize(id:"premature",initial:SimFixtures.input(SampleHouseholds.oak,"home-fire"),library:SimFixtures.library)
        try premature.commit(.init(id:"answer",actor:"user",baseRevision:0,commands:[.init(kind:"choose",target:"choice.home-fire.first-move",value:"get-out")]),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"initialResponse",actionID:"answer",session:premature,library:SimFixtures.library)}
    }
    func state(budget:Bool=false)throws->IntegratedAIState {
        let old=try PracticePhaseTests().state(),home=try #require(old.sessions[0].initial.home)
        var h=old.sessions[0].initial.household;h.equipment=[];h.backupPower=[];h.supplies.limitedBudget=budget
        var sessions:[SimulationSession]=[]
        for (id,scenario,events) in [("initial","home-fire",["evt.home-fire.alarm"]),("adapt","home-fire",["evt.home-fire.alarm","evt.home-fire.fire-origin"]),("comms","water-outage",["evt.water-outage.well-pump-failure"]),("water","water-outage",["evt.water-outage.well-pump-failure"])] {
            var session=try SimulationSession.initialize(id:id,initial:SimFixtures.input(h,scenario,home:home),library:SimFixtures.library)
            for (n,event) in events.enumerated() {try session.commit(.init(id:"setup-\(id)-\(n)",actor:"director",baseRevision:session.revision,commands:[.init(kind:"schedule",target:event,minute:n),.init(kind:"advance",minute:n)]),library:SimFixtures.library)}
            sessions.append(session)
        }
        return IntegratedAIState(sessions:sessions)
    }
    @Test func fullCheckNeedsNoPoweredEquipmentAndBudgetDoesNotChangeCredit()throws {
        for budget in [false,true] {
            var local=try state(budget:budget)
            try local.beginPracticeCheck(id:"non-device",variantID:"practice-check-a/2",sessionIDs:["initial","adapt","comms","water"],library:SimFixtures.library)
            let competencies=["initialResponse","adaptation","communication","continuity"]
            let commands:[SessionCommand]=[.init(kind:"choose",target:"choice.home-fire.first-move",value:"get-out"),.init(kind:"moveTo",target:local.sessions[0].initial.household.people[0].id,value:"living"),.init(kind:"contact",target:"contact"),.init(kind:"useStoredWater",value:"essential")]
            for index in 0..<4 {
                let active=try #require(try local.activePracticeCheckSession(attemptID:"non-device",library:SimFixtures.library))
                let answer=try local.submitPracticeAction(attemptID:"non-device",competencyID:competencies[index],commit:.init(id:"answer-\(index)",actor:"user",baseRevision:active.revision,commands:[commands[index]]),library:SimFixtures.library)
                #expect(answer.credit==1)
            }
            let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:DryRunJSON.encoder().encode(local))
            #expect(try PracticePhaseTests().score(restored).practice==100)
            #expect(try PracticePhaseTests().score(restored).practiceAssessed==4)
            #expect(try PracticePhaseTests().score(restored).practiceEvaluatorVersion==PracticeEvaluator.version)
            #expect(local.sessions.allSatisfy{$0.initial.household.equipment.isEmpty && $0.initial.household.backupPower.isEmpty})
        }
    }
    @Test func gradingDoesNotConsumeTheConfirmedInventoryLedger()throws {
        var s=try SessionInventoryTests().session()
        try s.commit(.init(id:"outage",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        s=try use(s,"essential");let saved=try DryRunJSON.encoder().encode(s)
        #expect(try PracticeEvaluator.evaluate(competencyID:"continuity",actionID:"answer",session:s,library:SimFixtures.library).credit==1)
        #expect(try DryRunJSON.encoder().encode(s)==saved)
        #expect(try s.query(library:SimFixtures.library).inventory?.items[0].remaining==5)
        #expect(try s.query(library:SimFixtures.library).inventory?.items[0].consumed==0)
    }

}
