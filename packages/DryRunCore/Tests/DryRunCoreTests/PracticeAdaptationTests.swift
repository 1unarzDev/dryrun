import Foundation
import Testing
@testable import DryRunCore

@Suite("Versioned committed-route adaptation anchors") struct PracticeAdaptationTests {
    func session(block:Bool=true)throws->SimulationSession {
        func door(_ id:String,_ x:Double,_ a:PortalDestination,_ b:PortalDestination)->Portal {
            Portal(id:id,floorID:"f",kind:.door,a:Vec2(x,1),b:Vec2(x,2),sideA:a,sideB:b,
                   clearWidthMeters:.confirmed(1),operable:.confirmed(true),stepFree:.confirmed(true),verification:.verified)
        }
        let home=HomeModel(id:"two-branches",label:"Synthetic practice home",source:.manual,
            floors:[Floor(id:"f",level:0,label:"Floor",exteriorGrade:.ground)],spaces:[
                Space(id:"start",floorID:"f",label:"Bedroom",kind:.bedroom,polygon:SampleHomes.rect(4,0,8,4)),
                Space(id:"kitchen",floorID:"f",label:"Kitchen",kind:.kitchen,polygon:SampleHomes.rect(8,0,10,4)),
                Space(id:"living",floorID:"f",label:"Living",kind:.livingRoom,polygon:SampleHomes.rect(0,0,4,4)),
                Space(id:"isolated",floorID:"f",label:"Unconnected room",kind:.other,polygon:SampleHomes.rect(0,6,4,10))],
            portals:[door("to-kitchen",8,.space("start"),.space("kitchen")),door("kitchen-exit",10,.space("kitchen"),.exterior),
                     door("to-living",4,.space("start"),.space("living")),door("living-exit",0,.space("living"),.exterior)],isFictional:true)
        var household=SampleHouseholds.oak
        household.people=Array(household.people.prefix(1));household.people[0].sleepingSpaceID="start"
        var s=SimulationSession(id:"adaptation",initial:SimFixtures.input(household,"home-fire",home:home))
        try s.commit(.init(id:"alarm",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        #expect(try s.query(library:SimFixtures.library).routes.first?.primary?.exitPortalID=="kitchen-exit")
        if block {
            try s.commit(.init(id:"block",actor:"director",baseRevision:1,commands:[.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1),.init(kind:"advance",minute:1)]),library:SimFixtures.library)
            #expect(try s.query(library:SimFixtures.library).routes.first?.primary?.exitPortalID=="living-exit")
        }
        return s
    }
    func move(_ original:SimulationSession,to:String)throws->SimulationSession {
        var s=original
        try s.commit(.init(id:"move",actor:"user",baseRevision:s.revision,commands:[.init(kind:"moveTo",target:s.initial.household.people[0].id,value:to)]),library:SimFixtures.library)
        return s
    }
    @Test func computedAlternativeCanEarnCreditWithoutMakingRouteDisappear()throws {
        let initial=try session(),s=try move(initial,to:"living")
        let answer=try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:s,library:SimFixtures.library)
        #expect(answer.credit==1)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:restored,library:SimFixtures.library).credit==1)
        #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:s,library:SimFixtures.library,evaluatorVersion:PracticeEvaluator.legacyVersion)}
        #expect(initial.initial==s.initial)
    }
    @Test func unsafeMovementEarnsZeroAndUnchangedRouteProvesNoAdaptation()throws {
        let blocked=try move(session(),to:"kitchen")
        #expect(try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:blocked,library:SimFixtures.library).credit==0)
        let unchanged=try move(session(block:false),to:"living")
        #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:unchanged,library:SimFixtures.library)}
        let unknown=try move(session(),to:"isolated")
        #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:unknown,library:SimFixtures.library)}
        let stayed=try move(session(),to:"start")
        #expect(throws:SessionError.invalidCommand){try PracticeEvaluator.evaluate(competencyID:"adaptation",actionID:"move",session:stayed,library:SimFixtures.library)}
    }
    @Test func captureRecordsVersionAndLegacySourceKeepsOriginalAnchors()throws {
        var local=IntegratedAIState(sessions:[try session()])
        try local.beginPractice(id:"check",variantID:"practice-check-a/0",sessionID:"adaptation",library:SimFixtures.library)
        #expect(local.practiceAttempts[0].source?.evaluatorVersion==PracticeEvaluator.version)
        // Retain an unsupported first response, then capture the actual adaptation before feedback.
        try local.submitPracticeAction(attemptID:"check",competencyID:"initialResponse",commit:.init(id:"first",actor:"user",baseRevision:2,commands:[.init(kind:"unsupported")]),library:SimFixtures.library)
        let observed=try local.submitPracticeAction(attemptID:"check",competencyID:"adaptation",commit:.init(id:"move",actor:"user",baseRevision:3,commands:[.init(kind:"moveTo",target:local.sessions[0].initial.household.people[0].id,value:"living")]),library:SimFixtures.library)
        #expect(observed.credit==1)
        #expect(try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers.first?.credit==1)
        local.practiceAttempts[0].source!.evaluatorVersion=nil
        local.practiceAttempts[0].observations![1].credit=nil
        // Missing version is the original evaluator, not a silent regrade using the new anchor.
        #expect(try local.eligiblePracticeAttempts(library:SimFixtures.library)[0].answers.isEmpty==true)
        local.practiceAttempts[0].source!.evaluatorVersion="future"
        #expect(throws:SessionError.invalidCommand){try local.eligiblePracticeAttempts(library:SimFixtures.library)}
    }
}
