import Foundation

/// Shared domain transition reducer for authored and incremental rehearsal adapters.
/// Commands are validated by the caller; this owns simulated time, ordered effects,
/// resource depletion, inventory settlement, and spatial synchronization at boundaries.
enum SessionTransitionReducer {
    static func initialize(_ run:inout RunState)throws {
        run.noteStaticUnknowns()
        try run.reevaluate(trigger:nil,emit:false)
    }
    static func advance(_ command:SessionCommand,run:inout RunState,pending:inout [SessionCommand],
        supplies:inout SessionSupplyLedger?,directorState:inout DirectorRuntimeState?,
                        horizon:Int,policyEnabled:Bool)throws {
        let scenario=run.scenario
        let started=run.minute
        let wait:SessionWaitPredicate?
        let until:Int
        if command.kind=="waitUntil" {
            guard policyEnabled,let predicate=command.target.flatMap(SessionWaitPredicate.init(rawValue:)),
                  let duration=command.durationMinutes,(1...4320).contains(duration),command.minute==nil,command.value==nil,command.hazard==nil else {throw SessionError.invalidCommand}
            wait=predicate;until=min(horizon,started+duration)
        } else {
            guard let minute=command.minute,minute>=run.minute,minute<=horizon else {throw SessionError.invalidCommand}
            wait=nil;until=minute
        }
        let alreadySatisfied=wait?.holds(in:run)==true
        var appliedIncident=false
        pending=DirectorPolicy.ordered(pending,scenario:scenario)
        var boundary = min(until,supplies?.nextExpiryMinute(after:run.minute) ?? until)
        if alreadySatisfied {boundary=run.minute}
        if wait == .nextIncident,let next=pending.first?.minute {boundary=min(boundary,next)}
        var depletion = run.nextDepletion()
        if let dep = depletion, dep.minute <= boundary { boundary = dep.minute }
        while !alreadySatisfied,let event = pending.first, let t = event.minute, t <= boundary {
            if let dep=depletion,dep.minute<=t {break}
            pending.removeFirst(); run.advance(to: t)
            try supplies?.synchronize(&run)
            guard var authored = scenario.events.first(where: { $0.id == event.target }) else { throw SessionError.invalidCommand }
            authored.minute = t
            guard Applicability.holds(authored.when, household: run.household, home: run.home, variants: run.effectiveVariants) else { throw SessionError.invalidCommand }
            if event.kind=="startIncident" {
                try validateIncidentOrigin(event,profile:authored,run:run)
                var options=run.input.effectiveSpatialOptions
                options.originSpaceID=event.value
                if scenario.hazard == .flashFlood,let room=event.value {options.floodAffectedSpaceIDs=[room]}
                run.input.spatialOptions=options
            }
            try run.apply(authored)
            appliedIncident=true
            if policyEnabled,DirectorPolicy.isSpatial(authored,in:scenario) {
                directorState?.activeIncidentCount=1;directorState?.stageID=authored.id
                if event.kind=="startIncident",let room=event.value {
                    run.spatialState?.originSpaceID=room
                    directorState?.originSpaceID=room
                } else {directorState?.originSpaceID=run.spatialState?.originSpaceID}
            }
            try supplies?.synchronize(&run)
            if supplies != nil {try run.reevaluate(trigger:run.events.last?.id,emit:true)}
            depletion = run.nextDepletion()
            if let dep = depletion, dep.minute < boundary { boundary = dep.minute }
            if wait == .nextIncident || wait?.holds(in:run)==true {boundary=run.minute;break}
        }
        let simultaneous = run.depletionSchedule().filter { $0.minute == boundary }
        run.advance(to: boundary)
        try supplies?.synchronize(&run)
        // Depletion at the boundary is computed from the same ledger, never set by the director.
        for dep in simultaneous { try run.handleDepletion(dep.resource) }
        try run.reevaluate(trigger: run.events.last?.id, emit: true)
        if let wait,let duration=command.durationMinutes {
            let satisfied=wait == .nextIncident ? appliedIncident : wait.holds(in:run)
            let reason=satisfied ? "predicate" : run.minute<until ? "mandatoryBoundary" : until<started+duration ? "policyHorizon" : "durationLimit"
            directorState?.lastWait=SessionWaitOutcome(predicate:wait,startedMinute:started,maximumDurationMinutes:duration,stoppedMinute:run.minute,satisfied:satisfied,reason:reason)
        }
    }
    static func validateIncidentOrigin(_ command:SessionCommand,profile:AuthoredEvent,run:RunState)throws {
        guard command.hazard==run.scenario.hazard,DirectorPolicy.isSpatial(profile,in:run.scenario) else {throw SessionError.invalidCommand}
        switch run.scenario.hazard {
        case .homeFire,.flashFlood:
            guard let room=command.value,run.home?.space(room) != nil else {throw SessionError.invalidCommand}
        case .tornado:
            // This profile models a regional warning, not an indoor tornado origin or a new shelter.
            guard command.value==nil else {throw SessionError.invalidCommand}
        default:throw SessionError.invalidCommand
        }
    }
}
