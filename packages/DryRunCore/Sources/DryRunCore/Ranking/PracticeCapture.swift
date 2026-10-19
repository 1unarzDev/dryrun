import Foundation

/// Persisted source identity; a practice check is not a label applied after a coached drill.
public struct PracticeAttemptSource:Codable,Sendable,Equatable {
    public var contractVersion:String
    public var sessionID:String
    public var initialDigest:String
    public var startingRevision:Int
    public var startingEventSequence:Int
    /// Missing on persisted capture/1 sources means anchors/1; never regrade old answers.
    public var evaluatorVersion:String? = nil
}
public struct PracticeObservation:Codable,Sendable,Equatable {
    public var competencyID:String
    public var actionID:String
    public var acceptedRevision:Int
    public var receiptDigest:String
    /// nil means unsupported/unassessed. It remains in the fixed competency denominator.
    public var credit:Double?
    public var feedbackRevealed:Bool
}

public extension IntegratedAIState {
    /// Persist before presenting the check. Reopening resumes the newest incomplete attempt,
    /// preserving its source and variant even if the caller requested a different variant.
    @discardableResult mutating func beginPractice(id:String,variantID:String,sessionID:String,
        library:ScenarioLibrary,persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeAttempt {
        guard !practiceAttempts.contains(where:{$0.source != nil && $0.archivedUnverified==true}) else {throw SessionError.invalidCommand}
        if let latest=practiceAttempts.max(by:{$0.sequence<$1.sequence}),
           latest.archivedUnverified != true,(latest.observations?.count ?? latest.answers.count)<4 {return latest}
        guard let session=sessions.first(where:{$0.id==sessionID}),session.concernSeed==nil,
              !practiceAttempts.contains(where:{$0.source?.sessionID==sessionID}) else {throw SessionError.invalidCommand}
        let receipt=try session.query(library:library)
        guard !session.commits.contains(where:{$0.actor=="user"}) else {throw SessionError.invalidCommand}
        guard !receipt.finished else {throw SessionError.finished}
        var candidate=self
        var attempt=try candidate.beginPractice(id:id,variantID:variantID)
        attempt.source=PracticeAttemptSource(contractVersion:"dryrun.practice-capture/1",sessionID:sessionID,
            initialDigest:try Self.practiceSourceDigest(session),
            startingRevision:session.revision,startingEventSequence:receipt.eventSequence,evaluatorVersion:PracticeEvaluator.version)
        attempt.observations=[]
        candidate.practiceAttempts[candidate.practiceAttempts.count-1]=attempt
        try persist(candidate);self=candidate;return attempt
    }

    /// Explicit legacy migration/retest action. Preserve every imported answer as history; no
    /// source-bound attempt can be archived to evade a first response or reroll its variant.
    mutating func archiveUnverifiedPractice(attemptID:String,persist:(IntegratedAIState)throws->Void={_ in})throws {
        guard let index=practiceAttempts.firstIndex(where:{$0.id==attemptID}),
              practiceAttempts[index].source==nil else {throw SessionError.invalidCommand}
        var candidate=self;candidate.practiceAttempts[index].archivedUnverified=true
        try persist(candidate);self=candidate
    }

    /// One transaction stores the real submitted action, its computed result and its first answer.
    /// No credit or beforeFeedback input is accepted. A failed persistence publishes neither.
    @discardableResult mutating func submitPracticeAction(attemptID:String,competencyID:String,
        commit:SessionCommit,library:ScenarioLibrary,persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeObservation {
        guard let a=practiceAttempts.firstIndex(where:{$0.id==attemptID}),
              practiceAttempts[a].sequence==practiceAttempts.map(\.sequence).max(),
              let source=practiceAttempts[a].source,source.contractVersion=="dryrun.practice-capture/1",
              [PracticeEvaluator.version,PracticeEvaluator.legacyVersion].contains(source.evaluatorVersion ?? PracticeEvaluator.legacyVersion),
              let s=sessions.firstIndex(where:{$0.id==source.sessionID}),
              sessions[s].concernSeed==nil,
              var observations=practiceAttempts[a].observations,
              let expected=Self.practiceOrder(practiceAttempts[a].variantID).dropFirst(observations.count).first,
              expected==competencyID,commit.actor=="user",commit.commands.count==1,
              commit.baseRevision>=source.startingRevision,
              !practiceAttempts.flatMap({$0.observations ?? []}).contains(where:{$0.actionID==commit.id}),
              source.initialDigest==(try Self.practiceSourceDigest(sessions[s])) else {throw SessionError.invalidCommand}
        // Every user action while the check is incomplete must be captured, including wrong or
        // unsupported actions. A caller cannot rehearse through the generic session API and then
        // submit a later, improved answer as its first response.
        try Self.validatePracticeChronology(source:source,observations:observations,session:sessions[s])
        var candidate=self
        let receipt=try candidate.sessions[s].commit(commit,library:library)
        var answer:PracticeAnswer?
        do {answer=try PracticeEvaluator.evaluate(competencyID:competencyID,actionID:commit.id,session:candidate.sessions[s],library:library,evaluatorVersion:source.evaluatorVersion ?? PracticeEvaluator.legacyVersion)}
        catch SessionError.invalidCommand {answer=nil} // Unsupported anchor, not an invented wrong/correct answer.
        let observation=PracticeObservation(competencyID:competencyID,actionID:commit.id,acceptedRevision:receipt.revision,
            receiptDigest:receipt.contextDigest,credit:answer?.credit,feedbackRevealed:false)
        observations.append(observation)
        candidate.practiceAttempts[a].observations=observations
        if let answer {candidate.practiceAttempts[a].answers.append(answer)}
        try persist(candidate);self=candidate;return observation
    }

    /// Call before showing any feedback. This never regrades the captured answer.
    @discardableResult mutating func revealPracticeFeedback(attemptID:String,actionID:String,
        coached:Bool=false,persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeObservation {
        guard let a=practiceAttempts.firstIndex(where:{$0.id==attemptID}),
              let i=practiceAttempts[a].observations?.firstIndex(where:{$0.actionID==actionID}) else {throw SessionError.invalidCommand}
        var candidate=self
        candidate.practiceAttempts[a].observations![i].feedbackRevealed=true
        candidate.practiceAttempts[a].coached = candidate.practiceAttempts[a].coached || coached
        try persist(candidate);self=candidate
        return candidate.practiceAttempts[a].observations![i]
    }

    /// Validate captured answers against immutable source traces before passing trusted inputs to
    /// the numeric compiler. Legacy imported answers have no chronology proof and earn no credit.
    func eligiblePracticeAttempts(library:ScenarioLibrary)throws->[PracticeAttempt] {
        try practiceAttempts.map {attempt in
            var accepted=attempt;accepted.answers=[]
            guard let source=attempt.source else {return accepted}
            guard attempt.archivedUnverified != true,source.contractVersion=="dryrun.practice-capture/1",
              [PracticeEvaluator.version,PracticeEvaluator.legacyVersion].contains(source.evaluatorVersion ?? PracticeEvaluator.legacyVersion),let session=sessions.first(where:{$0.id==source.sessionID}),session.concernSeed==nil,
                  source.initialDigest==(try Self.practiceSourceDigest(session)),
                  let observations=attempt.observations,observations.count<=4,
                  Set(observations.map(\.actionID)).count==observations.count,
                  observations.map(\.acceptedRevision)==observations.map(\.acceptedRevision).sorted(),
                  observations.map(\.competencyID)==Array(Self.practiceOrder(attempt.variantID).prefix(observations.count)) else {throw SessionError.invalidCommand}
            try Self.validatePracticeChronology(source:source,observations:observations,session:session)
            var prefix=SimulationSession(id:session.id,initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed)
            var found=0
            let initialReceipt=try prefix.query(library:library)
            guard source.startingRevision>=0,source.startingRevision<=session.revision else {throw SessionError.invalidCommand}
            if source.startingRevision==0 {guard initialReceipt.eventSequence==source.startingEventSequence else {throw SessionError.stale}}
            for commit in session.commits {
                let receipt=try prefix.commit(commit,library:library)
                if prefix.revision==source.startingRevision {guard receipt.eventSequence==source.startingEventSequence else {throw SessionError.stale}}
                if let observation=observations.first(where:{$0.actionID==commit.id}) {
                    guard commit.actor=="user",prefix.revision>source.startingRevision,
                          observation.acceptedRevision==receipt.revision,observation.receiptDigest==receipt.contextDigest else {throw SessionError.stale}
                    var answer:PracticeAnswer?
                    do {answer=try PracticeEvaluator.evaluate(competencyID:observation.competencyID,actionID:commit.id,session:prefix,library:library,evaluatorVersion:source.evaluatorVersion ?? PracticeEvaluator.legacyVersion)}
                    catch SessionError.invalidCommand {answer=nil}
                    guard observation.credit==answer?.credit else {throw SessionError.invalidCommand}
                    if let answer {accepted.answers.append(answer)}
                    found+=1
                }
            }
            guard found==observations.count else {throw SessionError.invalidCommand}
            return accepted
        }
    }
    func compileScorecard(rubric:RubricDefinition,assessments:[CriterionAssessment],library:ScenarioLibrary)throws->PreparednessScorecard {
        try ScoreCompiler.compile(rubric:rubric,assessments:assessments,attempts:eligiblePracticeAttempts(library:library))
    }
    private static func validatePracticeChronology(source:PracticeAttemptSource,observations:[PracticeObservation],session:SimulationSession)throws {
        guard source.startingRevision>=0,source.startingRevision<=session.commits.count,
              session.commits.prefix(source.startingRevision).allSatisfy({$0.actor != "user"}) else {throw SessionError.invalidCommand}
        let userIDs=session.commits.dropFirst(source.startingRevision).filter{$0.actor=="user"}.map(\.id)
        let capturedIDs=observations.map(\.actionID)
        guard Array(userIDs.prefix(observations.count))==capturedIDs,
              observations.count==4 || userIDs.count==observations.count else {throw SessionError.invalidCommand}
    }
    private struct PracticeSourceSnapshot:Encodable {
        var initial:RehearsalInput
        var inventory:SessionInventorySeed?
        var directorPolicy:DirectorPolicy?
        var concernSeed:ConcernExerciseSeed?
    }
    private static func practiceSourceDigest(_ session:SimulationSession)throws->String {
        StableDigest.of(try DryRunJSON.encoder().encode(PracticeSourceSnapshot(initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed)))
    }
    private static func practiceOrder(_ variantID:String)->[String] {
        switch variantID {
        case "practice-check-a/0":return ["initialResponse","adaptation","communication","continuity"]
        case "practice-check-b/0":return ["continuity","communication","adaptation","initialResponse"]
        default:return []
        }
    }
}
