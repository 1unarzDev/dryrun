import Foundation
import Testing
@testable import DryRunCore

@Suite("Director policy, stages and recorded origins") struct DirectorPolicyTests {
    func session(policy:((inout DirectorPolicy)->Void)?=nil)throws->SimulationSession {
        let scenario=SimFixtures.library.scenario("home-fire")!
        var bounds=DirectorPolicy.reviewed(scenario);policy?(&bounds)
        var input=SimFixtures.input(SampleHouseholds.oak,"home-fire");input.variants=["hallway-smoke"]
        return SimulationSession(id:"policy",initial:input,directorPolicy:bounds)
    }
    @discardableResult func submit(_ s:inout SimulationSession,_ commands:[SessionCommand],actor:String="director")throws->SessionReceipt {
        try s.commit(.init(id:"commit-\(s.revision)",actor:actor,baseRevision:s.revision,commands:commands),library:SimFixtures.library)
    }
    @Test func budgetsAndPersistedForwardStages()throws {
        var s=try session{p in p.schedulingHorizonMinutes=10;p.eventBudget=2;p.maximumPendingEvents=1}
        _=try submit(&s,[.init(kind:"startIncident",target:"evt.home-fire.alarm",value:"sp-kitchen",minute:0,hazard:.homeFire)])
        let queued=try s.query(library:SimFixtures.library)
        #expect(queued.directorState?.activeIncidentCount==0)
        #expect(queued.directorState?.scheduledEventCount==1)
        #expect(throws:SessionError.budget){try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:11)])}
        #expect(throws:SessionError.budget){try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1)])}
        #expect(try s.query(library:SimFixtures.library)==queued)
        let ignition=try submit(&s,[.init(kind:"advance",minute:0)])
        #expect(ignition.directorState?.activeIncidentCount==1)
        #expect(ignition.directorState?.stageID=="evt.home-fire.alarm")
        #expect(ignition.snapshot.spatialState?.originSpaceID=="sp-kitchen")
        #expect(throws:SessionError.budget){try submit(&s,[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:"sp-bed1",minute:1,hazard:.homeFire)])}
        _=try submit(&s,[.init(kind:"advanceIncident",target:"evt.home-fire.fire-origin",minute:1,hazard:.homeFire)])
        let result=try submit(&s,[.init(kind:"advance",minute:1)])
        #expect(result.snapshot.spatialState?.affectedSpaceIDs.contains("sp-kitchen")==true)
        #expect(result.directorState?.stageID=="evt.home-fire.fire-origin")
        #expect(throws:SessionError.budget){try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.hallway-smoke",minute:2)])}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"advance",minute:11)])}
        let resumed=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try resumed.query(library:SimFixtures.library)==result)
    }
    @Test func directorChoosesARealRoomAndHostComputesConsequences()throws {
        var kitchen=try session(),bedroom=kitchen
        let a=try submit(&kitchen,[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:"sp-kitchen",minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)])
        let b=try submit(&bedroom,[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:"sp-bed1",minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)])
        #expect(a.snapshot.spatialState?.originSpaceID=="sp-kitchen")
        #expect(b.snapshot.spatialState?.originSpaceID=="sp-bed1")
        #expect(a.snapshot.spatialState?.affectedSpaceIDs==["sp-kitchen"])
        #expect(b.snapshot.spatialState?.affectedSpaceIDs==["sp-bed1"])
        #expect(a.routes != b.routes)
        #expect(a.snapshot.spatialState?.routes==a.routes)
        #expect(b.snapshot.spatialState?.routes==b.routes)
        #expect(kitchen.initial==bedroom.initial)
        let person=kitchen.initial.household.people[0].id
        let moved=try submit(&kitchen,[.init(kind:"moveTo",target:person,value:"sp-living")],actor:"user")
        #expect(moved.snapshot.spatialState?.routes==moved.routes)
    }
    @Test func invalidOriginsHazardsAndImplicitStageBypassesFailAtomically()throws {
        var s=try session()
        let before=try s.query(library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"startIncident",target:"evt.home-fire.alarm",value:"invented-room",minute:0,hazard:.homeFire)])}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"startIncident",target:"evt.home-fire.alarm",value:"sp-kitchen",minute:0,hazard:.flashFlood)])}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"startIncident",target:"evt.home-fire.alarm",value:"sp-kitchen",minute:0,hazard:.homeFire)],actor:"user")}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"advanceIncident",target:"evt.home-fire.fire-origin",minute:0,hazard:.homeFire)])}
        #expect(try s.query(library:SimFixtures.library)==before)
        // A later stage may be scheduled first, but an earlier *time-ordered* stage cannot follow it.
        _=try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1)])
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:2)])}
        _=try submit(&s,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0)])
        let result=try submit(&s,[.init(kind:"advance",minute:2)])
        #expect(result.directorState?.stageID=="evt.home-fire.fire-origin")
    }
    @Test func policiesAreValidatedAndIncludedInSourceBinding()throws {
        let a=try session(),b=try session{$0.schedulingHorizonMinutes=10}
        #expect(try a.query(library:SimFixtures.library).contextDigest != b.query(library:SimFixtures.library).contextDigest)
        for invalid in [try session{$0.maximumActiveIncidents=2},try session{$0.eventBudget=33},try session{$0.maximumPendingEvents=0},try session{$0.allowedStageTransitions=[.init(from:"evt.home-fire.fire-origin",to:"evt.home-fire.alarm")]},try session{$0.version="future"}] {
            #expect(throws:SessionError.invalidCommand){try invalid.query(library:SimFixtures.library)}
        }
        var disabled=try session{$0.maximumActiveIncidents=0}
        #expect(throws:SessionError.invalidCommand){try submit(&disabled,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0)])}
        var wrongFamily=try session{$0.permittedHazardFamilies=[.flashFlood]}
        #expect(throws:SessionError.invalidCommand){try submit(&wrongFamily,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0)])}
    }
    @Test func fullProposalEnvelopeBindsSourceAndRejectsIncompleteMetadata()throws {
        let original=try session()
        let receipt=try original.query(library:SimFixtures.library)
        let binding=AgentContextBinding(receipt:receipt,householdRevision:original.initial.household.revision,homeRevision:original.initial.home!.revision)
        let bindingJSON=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(binding))
        let json:[String:Any]=["contractVersion":"dryrun.director-proposal/1","id":"proposal","requestID":"request","actor":"director","baseRevision":0,"binding":bindingJSON,
            "commands":[["kind":"requestDecision"]],"purpose":"Ask for a submitted action","evidenceIDs":[],"assumptionIDs":["assumption.educational-incident-profiles/1"],
            "nextBoundary":["kind":"pauseForDecision"],"presentationIntent":["focus":"decision","sceneFirst":true,"renderFrom":"committedReceipt","narration":"unverifiedProposal"]]
        func decode(_ object:[String:Any])throws->DirectorProposal {try DryRunJSON.decoder().decode(DirectorProposal.self,from:JSONSerialization.data(withJSONObject:object))}
        var committed=original
        let result=try decode(json).commit(to:&committed,binding:binding,library:SimFixtures.library,persist:{_ in})
        #expect(result.directorState?.awaitingUserAction==true)
        var incomplete=json;incomplete.removeValue(forKey:"binding")
        var unmodified=original
        #expect(throws:SessionError.invalidCommand){try decode(incomplete).commit(to:&unmodified,binding:binding,library:SimFixtures.library,persist:{_ in})}
        var stale=json;var wrongBinding=binding;wrongBinding.contextDigest="another-source"
        stale["binding"]=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(wrongBinding))
        #expect(throws:SessionError.stale){try decode(stale).commit(to:&unmodified,binding:binding,library:SimFixtures.library,persist:{_ in})}
        var misleading=json;misleading["nextBoundary"]=["kind":"pauseForDecision","requestedMinute":100]
        #expect(throws:SessionError.invalidCommand){try decode(misleading).commit(to:&unmodified,binding:binding,library:SimFixtures.library,persist:{_ in})}
        #expect(try unmodified.query(library:SimFixtures.library)==receipt)
    }
    @Test func equalTimeOrderingAndRegionalWarningsRemainHazardSpecific()throws {
        var a=try session(),b=a
        let alarm=SessionCommand(kind:"schedule",target:"evt.home-fire.alarm",minute:0)
        let origin=SessionCommand(kind:"schedule",target:"evt.home-fire.fire-origin",minute:0)
        let left=try submit(&a,[origin,alarm,.init(kind:"advance",minute:0)])
        let right=try submit(&b,[alarm,origin,.init(kind:"advance",minute:0)])
        #expect(left.snapshot==right.snapshot)
        #expect(left.events==right.events)
        let scenario=SimFixtures.library.scenario("tornado")!
        var tornado=SimulationSession(id:"tornado",initial:SimFixtures.input(SampleHouseholds.oak,"tornado"),directorPolicy:.reviewed(scenario))
        let warning=scenario.events.first{$0.rule==RuleID.tornadoWarning}!
        #expect(throws:SessionError.invalidCommand){try submit(&tornado,[.init(kind:"startIncident",target:warning.id,value:"sp-closet",minute:0,hazard:.tornado)])}
        let result=try submit(&tornado,[.init(kind:"startIncident",target:warning.id,minute:0,hazard:.tornado),.init(kind:"advance",minute:0)])
        #expect(result.snapshot.spatialState?.originSpaceID==nil)
        #expect(result.directorState?.activeIncidentCount==1)
    }
}
