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
    /// Legacy intake can resume/import an attempt, but cannot establish pre-feedback eligibility.
    /// Use beginPractice(...sessionID:library:persist:) for new scored checks.
    public mutating func beginPractice(id:String,variantID:String) throws -> PracticeAttempt {
        if let latest=practiceAttempts.max(by:{$0.sequence<$1.sequence}),
           latest.archivedUnverified != true,(latest.observations?.count ?? latest.answers.count)<4{return latest}
        guard !id.isEmpty,ScoreCompiler.variants.contains(variantID),!practiceAttempts.contains(where:{$0.id==id}) else {throw SessionError.invalidCommand}
        let attempt=PracticeAttempt(id:id,sequence:(practiceAttempts.map(\.sequence).max() ?? 0)+1,variantID:variantID,answers:[])
        practiceAttempts.append(attempt);return attempt
    }
    /// Caller-supplied credit/chronology is not an eligible capture path. Kept for source compatibility.
    @available(*,deprecated,message:"Use submitPracticeAction to atomically commit and grade before feedback")
    public mutating func recordPracticeAnswer(_ answer:PracticeAnswer,attemptID:String,library:ScenarioLibrary?=nil) throws {
        throw SessionError.invalidCommand
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
        if candidate.inventory.items.contains(where:{$0.category=="food"}) {
            let gap=try candidate.inventory.householdFoodGap(personIDs:h.people.map(\.id),at:date)
            h.supplies.shelfStableFoodDays=gap.unknown ? .unknown : .confirmed(gap.confirmedUsable,unit:"day",verifiedAt:date)
        }
        h.bumpRevision(at:date)
        try persist(h,candidate)
        self=candidate;household=h
    }
}
