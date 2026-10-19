import Foundation

extension SimulationSession {
    /// Compatibility adapter: authored packs supply a deterministic schedule and default choices;
    /// incremental exercises supply committed commands. Both use SessionTransitionReducer for
    /// actual time/effect/depletion mechanics. Authored defaults never enter an agent session.
    static func authoredResult(_ input:RehearsalInput,library:ScenarioLibrary,planner:EgressPlanning,
                               actions:ActionCatalog)throws->RehearsalResult {
        guard let scenario=library.scenario(input.scenarioID) else {throw RehearsalError.unknownScenario(input.scenarioID)}
        guard scenario.version==input.scenarioVersion else {
            throw RehearsalError.scenarioVersionMismatch(expected:scenario.version,actual:input.scenarioVersion)
        }
        let prepared=InterventionApplier.apply(input.interventions,household:input.household,home:input.home)
        var run=RunState(scenario:scenario,input:input,household:prepared.0,home:prepared.1,planner:planner)
        try SessionTransitionReducer.initialize(&run)
        run.snapshot()
        var schedule:[ScheduledItem]=[]
        for event in scenario.events where Applicability.holds(event.when,household:run.household,home:run.home,variants:run.effectiveVariants) {
            schedule.append(.init(minute:event.minute,priority:event.priority,id:event.id,kind:.event(event)))
        }
        for choice in scenario.choicePoints where Applicability.holds(choice.when,household:run.household,home:run.home,variants:run.effectiveVariants) {
            schedule.append(.init(minute:choice.minute,priority:100,id:choice.id,kind:.choice(choice)))
        }
        schedule.sort{($0.minute,$0.priority,$0.id)<($1.minute,$1.priority,$1.id)}
        var index=0,iterations=0
        var supplies:SessionSupplyLedger?=nil
        var directorState:DirectorRuntimeState?=nil
        while true {
            iterations+=1
            guard iterations<=RehearsalEngine.maxEvents else {throw RehearsalError.eventLimitExceeded}
            let next=index<schedule.count ? schedule[index] : nil
            if let depletion=run.nextDepletion(),depletion.minute<=scenario.durationMinutes,
               next==nil || depletion.minute<=next!.minute {
                var pending:[SessionCommand]=[]
                try SessionTransitionReducer.advance(.init(kind:"advance",minute:depletion.minute),run:&run,
                    pending:&pending,supplies:&supplies,directorState:&directorState,
                    horizon:scenario.durationMinutes,policyEnabled:false)
                run.snapshot()
                continue
            }
            guard let item=next else {break}
            index+=1
            var pending:[SessionCommand]=[]
            if case .event(let event)=item.kind {pending=[.init(kind:"schedule",target:event.id,minute:item.minute)]}
            try SessionTransitionReducer.advance(.init(kind:"advance",minute:item.minute),run:&run,
                pending:&pending,supplies:&supplies,directorState:&directorState,
                horizon:scenario.durationMinutes,policyEnabled:false)
            if case .choice(let choice)=item.kind {try run.choose(choice)}
            run.snapshot()
        }
        // The authored API historically returns event/depletion snapshots, not a synthetic final
        // snapshot. Preserve that contract and planner/action injection for existing native clients.
        var pending:[SessionCommand]=[]
        try SessionTransitionReducer.advance(.init(kind:"advance",minute:max(run.minute,scenario.durationMinutes)),run:&run,
            pending:&pending,supplies:&supplies,directorState:&directorState,
            horizon:scenario.durationMinutes,policyEnabled:false)
        let recommendations=RecommendationRanker.rank(ActionRules.evaluate(run.summary(),catalog:actions))
        return RehearsalResult(input:input,events:run.events,snapshots:run.snapshots,decisions:run.decisions,
            routes:run.currentRoutes.keys.sorted().compactMap{run.currentRoutes[$0]},recommendations:recommendations,
            unknowns:run.unknowns.sorted(),engineVersion:RehearsalEngine.engineVersion)
    }
}
