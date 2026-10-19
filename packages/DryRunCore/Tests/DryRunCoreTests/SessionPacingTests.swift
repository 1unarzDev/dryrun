import Foundation
import Testing
@testable import DryRunCore

@Suite("Host wait predicates and submitted door posture") struct SessionPacingTests {
    func session(_ scenarioID:String="water-outage",horizon:Int?=nil)throws->SimulationSession {
        let scenario=SimFixtures.library.scenario(scenarioID)!
        var policy=DirectorPolicy.reviewed(scenario);if let horizon {policy.schedulingHorizonMinutes=horizon}
        return SimulationSession(id:"pacing",initial:SimFixtures.input(SampleHouseholds.oak,scenarioID),directorPolicy:policy)
    }
    @discardableResult func submit(_ s:inout SimulationSession,_ commands:[SessionCommand],actor:String="director")throws->SessionReceipt {
        try s.commit(.init(id:"commit-\(s.revision)",actor:actor,baseRevision:s.revision,commands:commands),library:SimFixtures.library)
    }
    @Test func waitUsesHostDepletionAndRetainsCompletedState()throws {
        var s=try session()
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)])
        let result=try submit(&s,[.init(kind:"waitUntil",target:"storedWaterUnavailable",durationMinutes:4320)])
        #expect(result.snapshot.simMinute==1800)
        #expect(result.snapshot.resources["res.water.stored"]?.amount==0)
        #expect(result.directorState?.lastWait?.satisfied==true)
        #expect(result.directorState?.lastWait?.reason=="predicate")
        let again=try submit(&s,[.init(kind:"waitUntil",target:"storedWaterUnavailable",durationMinutes:30)])
        #expect(again.snapshot.simMinute==1800)
        #expect(again.snapshot.resources==result.snapshot.resources)
        let resumed=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try resumed.query(library:SimFixtures.library)==again)
    }
    @Test func nextIncidentDurationAndPolicyHorizonAreDistinct()throws {
        var s=try session()
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:60)])
        let event=try submit(&s,[.init(kind:"waitUntil",target:"nextIncident",durationMinutes:120)])
        #expect(event.snapshot.simMinute==60)
        #expect(event.pending.isEmpty)
        #expect(event.directorState?.lastWait?.satisfied==true)
        let timeout=try submit(&s,[.init(kind:"waitUntil",target:"nextIncident",durationMinutes:30)])
        #expect(timeout.snapshot.simMinute==90)
        #expect(timeout.directorState?.lastWait?.reason=="durationLimit")
        #expect(timeout.directorState?.lastWait?.satisfied==false)
        var bounded=try session(horizon:10)
        let horizon=try submit(&bounded,[.init(kind:"waitUntil",target:"nextIncident",durationMinutes:100)])
        #expect(horizon.snapshot.simMinute==10)
        #expect(horizon.directorState?.lastWait?.reason=="policyHorizon")
        #expect(horizon.directorState?.lastWait?.satisfied==false)
    }
    @Test func unrelatedMandatoryBoundaryInterruptsAndUnknownIsNotSuccess()throws {
        let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
        var ledger=InventoryLedger()
        try ledger.confirm([.init(id:"water",physicalID:"container",category:"water",quantity:.confirmed(5),unit:.usGallon,usableQuantity:.confirmed(5),accessible:.confirmed(true),expiresAt:date.addingTimeInterval(3600))],baseRevision:0,at:date)
        let base=try session()
        var expiry=SimulationSession(id:base.id,initial:base.initial,inventory:.init(ledger:ledger,asOf:date),directorPolicy:base.directorPolicy)
        let stopped=try submit(&expiry,[.init(kind:"waitUntil",target:"nextIncident",durationMinutes:720)])
        #expect(stopped.snapshot.simMinute==60)
        #expect(stopped.directorState?.lastWait?.satisfied==false)
        #expect(stopped.directorState?.lastWait?.reason=="mandatoryBoundary")
        var input=base.initial;input.household.supplies.storedWaterGallons = .unknown
        var unknown=SimulationSession(id:"unknown",initial:input,directorPolicy:base.directorPolicy)
        _=try submit(&unknown,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)])
        let result=try submit(&unknown,[.init(kind:"waitUntil",target:"storedWaterUnavailable",durationMinutes:5)])
        #expect(result.snapshot.resources["res.water.stored"]?.amount==nil)
        #expect(result.directorState?.lastWait?.satisfied==false)
    }
    @Test func invalidWaitIntentsAndDoorPermissionsFailAtomically()throws {
        var s=try session();let before=try s.query(library:SimFixtures.library)
        for command in [SessionCommand(kind:"waitUntil",target:"arbitraryExpression()",durationMinutes:5),.init(kind:"waitUntil",target:"nextIncident",durationMinutes:0),.init(kind:"waitUntil",target:"nextIncident",minute:5,durationMinutes:5)] {
            #expect(throws:SessionError.invalidCommand){try submit(&s,[command])}
        }
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"waitUntil",target:"nextIncident",durationMinutes:5)],actor:"user")}
        #expect(try s.query(library:SimFixtures.library)==before)
        var input=s.initial
        var options=input.effectiveSpatialOptions;let person=input.household.people[0].id;options.startingSpaceIDs[person]="sp-living";input.spatialOptions=options
        var door=SimulationSession(id:"door",initial:input,directorPolicy:s.directorPolicy)
        #expect(throws:SessionError.invalidCommand){try submit(&door,[.init(kind:"closeDoor",target:"pt-front",value:person)])}
        let result=try submit(&door,[.init(kind:"closeDoor",target:"pt-front",value:person)],actor:"user")
        #expect(result.closedPortalIDs==["pt-front"])
        #expect(door.initial==input)
        #expect(result.snapshot.resources==before.snapshot.resources)
        #expect(try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(door)).query(library:SimFixtures.library)==result)
        var unknownInput=input
        let index=unknownInput.home!.portals.firstIndex{$0.id=="pt-front"}!
        unknownInput.home!.portals[index].operable = .unknown
        var unknownDoor=SimulationSession(id:"unknownDoor",initial:unknownInput,directorPolicy:s.directorPolicy)
        #expect(throws:SessionError.invalidCommand){try submit(&unknownDoor,[.init(kind:"closeDoor",target:"pt-front",value:person)],actor:"user")}
    }
    @Test func aRequestedDecisionCannotBeSkippedOrFollowedByHiddenEffects()throws {
        var s=try session()
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"requestDecision"),.init(kind:"finish")])}
        let paused=try submit(&s,[.init(kind:"requestDecision")])
        #expect(paused.directorState?.awaitingUserAction==true)
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"advance",minute:100)])}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"finish")])}
        let fallback=try s.commit(s.fallback(),library:SimFixtures.library)
        #expect(fallback.snapshot.resources==paused.snapshot.resources)
        #expect(fallback.directorState?.awaitingUserAction==true)
        _=try submit(&s,[.init(kind:"useStoredWater",value:"essential")],actor:"user")
        let continued=try submit(&s,[.init(kind:"advance",minute:100)])
        #expect(continued.directorState?.awaitingUserAction==false)
        #expect(continued.snapshot.simMinute==100)
        _=try submit(&s,[.init(kind:"requestDecision")])
        let exited=try submit(&s,[.init(kind:"finish")],actor:"user")
        #expect(exited.finished)
    }
    @Test func finiteQuantitiesCannotOverflowDepletionTime()throws {
        let base=try session();var input=base.initial
        input.household.supplies.storedWaterGallons = .confirmed(1e200)
        var s=try SimulationSession.initialize(id:"large",initial:input,library:SimFixtures.library)
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)])
        let result=try submit(&s,[.init(kind:"waitUntil",target:"storedWaterUnavailable",durationMinutes:4320)])
        #expect(result.snapshot.simMinute==4320)
        #expect(result.directorState?.lastWait?.satisfied==false)
        #expect(result.snapshot.resources["res.water.stored"]!.amount!.isFinite)
    }
    @Test func actualUserChoiceOverridesAnEarlierHypotheticalInterventionChoice()throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"water-outage")
        let choiceID="choice.water-outage.drinking-water"
        input.interventions=[.init(actionID:"synthetic-choice",parameters:[choiceID:"use-stored"])]
        var s=try SimulationSession.initialize(id:"choice",initial:input,library:SimFixtures.library)
        let result=try submit(&s,[.init(kind:"choose",target:choiceID,value:"drink-tap")],actor:"user")
        #expect(result.events.contains{$0.templateValues["option"]=="drink-tap"})
        #expect(!result.events.contains{$0.templateValues["option"]=="use-stored"})
        let content=try ContentLibrary.load(from:SimFixtures.repoRoot.appendingPathComponent("content"))
        let localizer=content.localizer(for:"en")
        for event in result.events {#expect(localizer.has(event.titleKey,in:"en"))}
    }
    @Test func spatialBatchPreviewIsReadOnlyAndShowsAppliedEffects()throws {
        var s=try session("home-fire")
        let before=try s.query(library:SimFixtures.library)
        let commands:[SessionCommand]=[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:"sp-kitchen",minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)]
        let preview=try s.executeTool(.init(kind:.evaluateCandidateAction,baseRevision:0,commands:commands),library:SimFixtures.library)
        #expect(preview.receipt.snapshot.spatialState?.affectedSpaceIDs==["sp-kitchen"])
        #expect(try s.query(library:SimFixtures.library)==before)
        #expect(throws:SessionError.invalidCommand){try s.executeTool(.init(kind:.evaluateCandidateAction,baseRevision:0,command:commands[0],commands:commands),library:SimFixtures.library)}
        let committed=try submit(&s,commands)
        #expect(committed.snapshot==preview.receipt.snapshot)
        #expect(committed.routes==preview.receipt.routes)
    }
}
