import Foundation
/// Durable local state only: no raw provider history, opaque signatures, image bytes or deliberations.
public struct IntegratedAIState: Codable, Sendable {
    public var schemaVersion:Int = 1
    public var inventory:InventoryLedger
    public var concerns:ConcernLedger
    public var sessions:[SimulationSession]
    public var practiceAttempts:[PracticeAttempt]
    public var scorecards:[PreparednessScorecard]
    public init(inventory:InventoryLedger=InventoryLedger(),concerns:ConcernLedger=ConcernLedger(),sessions:[SimulationSession]=[],practiceAttempts:[PracticeAttempt]=[],scorecards:[PreparednessScorecard]=[]){
        self.inventory=inventory;self.concerns=concerns;self.sessions=sessions;self.practiceAttempts=practiceAttempts;self.scorecards=scorecards
    }
    /// Resuming the newest attempt prevents a restart from erasing unsafe pre-feedback answers.
    public mutating func beginPractice(id:String,variantID:String) throws -> PracticeAttempt {
        if let latest=practiceAttempts.max(by:{$0.sequence<$1.sequence}),latest.answers.count<4{return latest}
        guard ScoreCompiler.variants.contains(variantID),!practiceAttempts.contains(where:{$0.id==id}) else {throw SessionError.invalidCommand}
        let attempt=PracticeAttempt(id:id,sequence:(practiceAttempts.map(\.sequence).max() ?? 0)+1,variantID:variantID,answers:[])
        practiceAttempts.append(attempt);return attempt
    }
    public mutating func recordPracticeAnswer(_ answer:PracticeAnswer,attemptID:String,library:ScenarioLibrary?=nil) throws {
        guard let index=practiceAttempts.firstIndex(where:{$0.id==attemptID}),!practiceAttempts[index].answers.contains(where:{$0.competencyID==answer.competencyID}),
            answer.beforeFeedback,ScoreCompiler.competencies.contains(answer.competencyID),[0,0.5,1].contains(answer.credit),
            !practiceAttempts[index].coached,
            !practiceAttempts[index].answers.contains(where:{$0.committedActionID==answer.committedActionID}),
            let library,let session=sessions.first(where:{$0.commits.contains(where:{$0.actor=="user" && $0.id==answer.committedActionID})}) else {throw SessionError.invalidCommand}
        let evaluated=try PracticeEvaluator.evaluate(competencyID:answer.competencyID,actionID:answer.committedActionID,session:session,library:library)
        guard answer.credit==evaluated.credit else {throw SessionError.invalidCommand}
        practiceAttempts[index].answers.append(answer)
    }
}

public extension IntegratedAIState {
    /// One accepted inventory batch updates the legacy simulation input in the same private transaction.
    /// Inventory becomes the source of quantity truth; never add this projection back into the ledger.
    mutating func confirmInventory(_ items:[InventoryItem],household:inout HouseholdProfile,baseHouseholdRevision:Int,baseInventoryRevision:Int,at date:Date,
        persist:(HouseholdProfile,IntegratedAIState)throws->Void) throws {
        guard household.revision==baseHouseholdRevision else{throw SessionError.stale}
        var candidate=self,h=household
        try candidate.inventory.confirm(items,baseRevision:baseInventoryRevision,at:date)
        if candidate.inventory.items.contains(where:{$0.category=="water"}) {
            let gap=try candidate.inventory.waterGap(people:h.people.count,at:date)
            h.supplies.storedWaterGallons=gap.unknown ? .unknown : .confirmed(gap.confirmedUsable/3.785411784,unit:"gal",verifiedAt:date)
        }
        h.bumpRevision(at:date)
        try persist(h,candidate)
        self=candidate;household=h
    }
}
