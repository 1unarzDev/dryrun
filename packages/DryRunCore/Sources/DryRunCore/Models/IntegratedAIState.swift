import Foundation
/// Durable local state only: no raw provider history, opaque signatures, image bytes or deliberations.
public struct IntegratedAIState: Codable, Sendable {
    public var schemaVersion:Int = 1
    public var inventory:InventoryLedger
    public var concerns:ConcernLedger
    public var sessions:[SimulationSession]
    public var practiceAttempts:[PracticeAttempt]
    public var scorecards:[PreparednessScorecard]
    /// Optional local-only metadata for selected frames; absent in historical state. No image/depth bytes.
    public var imageGeometryRecords:[RoomImageCaptureGeometry]?
    public init(inventory:InventoryLedger=InventoryLedger(),concerns:ConcernLedger=ConcernLedger(),sessions:[SimulationSession]=[],practiceAttempts:[PracticeAttempt]=[],scorecards:[PreparednessScorecard]=[],imageGeometryRecords:[RoomImageCaptureGeometry]?=nil){
        self.inventory=inventory;self.concerns=concerns;self.sessions=sessions;self.practiceAttempts=practiceAttempts;self.scorecards=scorecards;self.imageGeometryRecords=imageGeometryRecords
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
            let gap=try candidate.inventory.waterGap(people:h.people.count,personIDs:h.people.map(\.id),at:date)
            h.supplies.storedWaterGallons=gap.unknown ? .unknown : .confirmed(gap.confirmedUsable/3.785411784,unit:"gal",verifiedAt:date)
        }
        if candidate.inventory.items.contains(where:{$0.category=="food"}) {
            let gap=try candidate.inventory.householdFoodGap(personIDs:h.people.map(\.id),at:date)
            h.supplies.shelfStableFoodDays=gap.unknown ? .unknown : .confirmed(gap.confirmedUsable,unit:"day",verifiedAt:date)
        }
        if candidate.inventory.items.contains(where:{$0.preparationKind == .flashlight}) || inventory.items.contains(where:{$0.preparationKind == .flashlight}) {
            let gap=try candidate.inventory.preparationItemGap(kind:.flashlight,personIDs:h.people.map(\.id),at:date)
            guard gap.confirmedUsable<Double(Int.max) else {throw SessionError.invalidCommand}
            h.supplies.flashlights=gap.unknown ? .unknown:.confirmed(Int(gap.confirmedUsable),verifiedAt:date)
            if var fact=h.preparedness?.items["flashlight"] {
                fact.available=h.supplies.flashlights.confirmedValue.map{.confirmed($0>0,verifiedAt:date)} ?? .unknown
                h.preparedness?.items["flashlight"]=fact
            }
        }
        if candidate.inventory.items.contains(where:{$0.preparationKind == .firstAidKit}) || inventory.items.contains(where:{$0.preparationKind == .firstAidKit}) {
            let gap=try candidate.inventory.preparationItemGap(kind:.firstAidKit,personIDs:h.people.map(\.id),at:date)
            h.supplies.firstAidKit=gap.deficit.map{.confirmed($0==0,verifiedAt:date)} ?? .unknown
            if var fact=h.preparedness?.items["firstAid"] {fact.available=h.supplies.firstAidKit;h.preparedness?.items["firstAid"]=fact}
        }
        h.bumpRevision(at:date)
        try persist(h,candidate)
        self=candidate;household=h
    }
}
