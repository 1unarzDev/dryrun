import Foundation

public extension IntegratedAIState {
    static let phasedPracticeEvaluatorVersion="dryrun.practice-anchors/2"
    static let phasedPracticeVariants=["practice-check-a/1","practice-check-b/1","practice-check-a/2","practice-check-b/2",PracticeCheckSources.secondSetVariant]
    private static func phasedEvaluator(_ variant:String)->String {variant.hasSuffix("/1") ? phasedPracticeEvaluatorVersion:"dryrun.practice-anchors/3"}

    /// Freeze all situations before presenting any question. No reroll, source switching or
    /// director difficulty changes are allowed during the scored check. Training stays separate.
    @discardableResult mutating func beginPracticeCheck(id:String,variantID:String,sessionIDs:[String],
        library:ScenarioLibrary,persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeAttempt {
        if let latest=practiceAttempts.max(by:{$0.sequence<$1.sequence}),latest.checkID==nil,latest.archivedUnverified != true,
           (latest.observations?.count ?? latest.answers.count)<4 {return latest}
        guard Self.phasedPracticeVariants.contains(variantID),sessionIDs.count==4,Set(sessionIDs).count==4,
              !practiceAttempts.contains(where:{$0.source != nil && $0.archivedUnverified==true}) else {throw SessionError.invalidCommand}
        let used=practiceAttempts.flatMap{($0.phaseSources ?? [])+($0.source.map{[$0]} ?? [])}.map(\.sessionID)
        guard Set(used).isDisjoint(with:sessionIDs) else {throw SessionError.invalidCommand}
        let order=Self.practiceOrder(variantID)
        var sources:[PracticeAttemptSource]=[]
        for (index,id) in sessionIDs.enumerated() {
            guard let session=sessions.first(where:{$0.id==id}),session.concernSeed==nil,
                  session.initial.scenarioID==Self.practiceScenario(order[index],variant:variantID,household:session.initial.household),
                  session.initial.choices.isEmpty,session.initial.interventions.isEmpty,
                  !session.commits.contains(where:{$0.actor=="user"}) else {throw SessionError.invalidCommand}
            let receipt=try session.query(library:library)
            guard !receipt.finished else {throw SessionError.finished}
            sources.append(.init(contractVersion:"dryrun.practice-capture/1",sessionID:id,
                initialDigest:try Self.practiceSourceDigest(session),startingRevision:session.revision,
                startingEventSequence:receipt.eventSequence,evaluatorVersion:Self.phasedEvaluator(variantID)))
        }
        var candidate=self
        var attempt=try candidate.beginPractice(id:id,variantID:variantID)
        attempt.source=sources[0];attempt.phaseSources=sources;attempt.observations=[]
        candidate.practiceAttempts[candidate.practiceAttempts.count-1]=attempt
        _=try candidate.validatePhasedPractice(attempt,library:library)
        try persist(candidate);self=candidate;return attempt
    }

    /// Native uses this source instead of reconstructing the phase order or mixing live household edits.
    func activePracticeCheckSession(attemptID:String,library:ScenarioLibrary)throws->SimulationSession? {
        guard let attempt=practiceAttempts.first(where:{$0.id==attemptID}),let sources=attempt.phaseSources,
              let observations=attempt.observations else {throw SessionError.invalidCommand}
        _=try validatePhasedPractice(attempt,library:library)
        guard observations.count<4 else {return nil}
        return sessions.first(where:{$0.id==sources[observations.count].sessionID})
    }

    /// One committed answer in its frozen situation; the scorer reconstructs it from the trace.
    @discardableResult mutating func submitPhasedPracticeAction(attemptID:String,competencyID:String,commit:SessionCommit,
        library:ScenarioLibrary,persist:(IntegratedAIState)throws->Void)throws->PracticeObservation {
        guard let a=practiceAttempts.firstIndex(where:{$0.id==attemptID}),Self.phasedPracticeVariants.contains(practiceAttempts[a].variantID),
              practiceAttempts[a].sequence==practiceAttempts.map(\.sequence).max(),
              let sources=practiceAttempts[a].phaseSources,sources.count==4,let observations=practiceAttempts[a].observations,
              observations.count<4,Self.practiceOrder(practiceAttempts[a].variantID)[observations.count]==competencyID,
              commit.actor=="user",commit.commands.count==1,
              !practiceAttempts.flatMap({$0.observations ?? []}).contains(where:{$0.actionID==commit.id}) else {throw SessionError.invalidCommand}
        _=try validatePhasedPractice(practiceAttempts[a],library:library)
        let source=sources[observations.count]
        guard let s=sessions.firstIndex(where:{$0.id==source.sessionID}),commit.baseRevision==source.startingRevision else {throw SessionError.stale}
        var candidate=self
        let receipt=try candidate.sessions[s].commit(commit,library:library)
        var answer:PracticeAnswer?
        do {answer=try PracticeEvaluator.evaluate(competencyID:competencyID,actionID:commit.id,session:candidate.sessions[s],library:library,evaluatorVersion:Self.phasedEvaluator(practiceAttempts[a].variantID))}
        catch SessionError.invalidCommand {answer=nil}
        let observation=PracticeObservation(competencyID:competencyID,actionID:commit.id,acceptedRevision:receipt.revision,
            receiptDigest:receipt.contextDigest,credit:answer?.credit,feedbackRevealed:false)
        candidate.practiceAttempts[a].observations!.append(observation)
        if let answer {candidate.practiceAttempts[a].answers.append(answer)}
        _=try candidate.validatePhasedPractice(candidate.practiceAttempts[a],library:library)
        try persist(candidate);self=candidate;return observation
    }

    /// Independent validation includes every phase, even one not yet answered. An edit to a
    /// future situation cannot quietly replace an immutable check after an earlier wrong answer.
    func validatePhasedPractice(_ attempt:PracticeAttempt,library:ScenarioLibrary)throws->PracticeAttempt {
        guard Self.phasedPracticeVariants.contains(attempt.variantID),attempt.archivedUnverified != true,
              Set(sessions.map(\.id)).count==sessions.count,
              let sources=attempt.phaseSources,sources.count==4,Set(sources.map(\.sessionID)).count==4,
              attempt.source==sources.first,let observations=attempt.observations,observations.count<=4,
              Set(observations.map(\.actionID)).count==observations.count,
              observations.map(\.competencyID)==Array(Self.practiceOrder(attempt.variantID).prefix(observations.count)) else {throw SessionError.invalidCommand}
        var accepted=attempt;accepted.answers=[]
        var common:SimulationSession?
        for (index,source) in sources.enumerated() {
            guard source.contractVersion=="dryrun.practice-capture/1",source.evaluatorVersion==Self.phasedEvaluator(attempt.variantID),
                  let session=sessions.first(where:{$0.id==source.sessionID}),session.concernSeed==nil,
                  session.initial.scenarioID==Self.practiceScenario(Self.practiceOrder(attempt.variantID)[index],variant:attempt.variantID,household:session.initial.household),
                  session.initial.choices.isEmpty,session.initial.interventions.isEmpty,
                  source.initialDigest==(try Self.practiceSourceDigest(session)),
                  source.startingRevision>=0,source.startingRevision<=session.revision,
                  session.commits.prefix(source.startingRevision).allSatisfy({$0.actor != "user"}) else {throw SessionError.invalidCommand}
            if let first=common {
                guard first.initial.household==session.initial.household,first.initial.home==session.initial.home,
                      try DryRunJSON.encoder().encode(first.inventory)==DryRunJSON.encoder().encode(session.inventory) else {throw SessionError.stale}
            } else {common=session}
            let observation=index<observations.count ? observations[index]:nil
            // Before completion, no uncaptured action or later director complication may enter any phase.
            if observations.count<4 {guard session.revision==source.startingRevision+(observation==nil ? 0:1) else {throw SessionError.invalidCommand}}
            var prefix=SimulationSession(id:session.id,initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed,dependencyPolicy:session.dependencyPolicy,mechanicsVersion:session.mechanicsVersion)
            for commit in session.commits.prefix(source.startingRevision) {try prefix.commit(commit,library:library)}
            guard try prefix.query(library:library).eventSequence==source.startingEventSequence else {throw SessionError.stale}
            if let observation {
                guard observation.acceptedRevision==source.startingRevision+1,session.commits.count>source.startingRevision else {throw SessionError.invalidCommand}
                let action=session.commits[source.startingRevision]
                guard action.id==observation.actionID,action.actor=="user",action.commands.count==1 else {throw SessionError.invalidCommand}
                let receipt=try prefix.commit(action,library:library)
                guard receipt.contextDigest==observation.receiptDigest else {throw SessionError.stale}
                var answer:PracticeAnswer?
                do {answer=try PracticeEvaluator.evaluate(competencyID:observation.competencyID,actionID:action.id,session:prefix,library:library,evaluatorVersion:Self.phasedEvaluator(attempt.variantID))}
                catch SessionError.invalidCommand {answer=nil}
                guard observation.credit==answer?.credit else {throw SessionError.invalidCommand}
                if let answer {accepted.answers.append(answer)}
            }
        }
        return accepted
    }

    private static func practiceScenario(_ competency:String,variant:String,household:HouseholdProfile)->String {
        if !variant.hasSuffix("/1") {return PracticeCheckSources.scenario(competency,variantID:variant,household:household)}
        switch competency {
        case "initialResponse","communication":return "water-outage"
        case "adaptation":return "home-fire"
        case "continuity":return "freeze-power-loss"
        default:return "unsupported"
        }
    }
}
