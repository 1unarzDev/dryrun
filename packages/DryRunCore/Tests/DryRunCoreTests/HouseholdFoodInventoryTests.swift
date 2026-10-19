import Foundation
import Testing
@testable import DryRunCore

@Suite("Confirmed household food coverage") struct HouseholdFoodInventoryTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func item(_ id:String="food",amount:Double=3,unit:InventoryUnit = .day,access:EvidenceValue<Bool> = .confirmed(true),subjects:[String]=[])->InventoryItem {
        InventoryItem(id:id,physicalID:id,category:"food",quantity:.confirmed(amount),unit:unit,usableQuantity:.confirmed(amount),accessible:access,subjectIDs:subjects)
    }
    @Test func incompatibleCountsAndSubjectCoverageCannotInventDays()throws {
        var ledger=InventoryLedger()
        try ledger.confirm([item(unit:.count)],baseRevision:0,at:date)
        #expect(try ledger.householdFoodGap(personIDs:["a","b"],at:date).deficit==nil)
        try ledger.confirm([item(subjects:["a"])],baseRevision:1,at:date)
        #expect(try ledger.householdFoodGap(personIDs:["a","b"],at:date).deficit==nil)
        try ledger.confirm([item(subjects:["a","b"])],baseRevision:2,at:date)
        #expect(try ledger.householdFoodGap(personIDs:["a","b"],at:date).deficit==0)
        try ledger.confirm([item("unreadable-extra",unit:.count)],baseRevision:3,at:date)
        let sufficient=try ledger.householdFoodGap(personIDs:["a","b"],at:date)
        #expect(sufficient.deficit==0);#expect(sufficient.unknown)
    }
    @Test func confirmedFoodSupersedesLegacyAndExpiredQuantityCannotEarnCredit()throws {
        var h=SampleHouseholds.oak,local=IntegratedAIState()
        h.preparedness=PreparednessRecord(items:["food":PreparationFact(available:.confirmed(true),location:"Pantry")])
        func quantity(_ h:HouseholdProfile,_ ledger:InventoryLedger)throws->Bool? {
            try HouseholdAssessment.assess(household:h,home:nil,inventory:ledger,at:date).first{$0.criterionID=="food"}?.predicates["quantity"]
        }
        var expired=item();expired.expiresAt=date.addingTimeInterval(-1)
        try local.confirmInventory([expired],household:&h,baseHouseholdRevision:h.revision,baseInventoryRevision:0,at:date,persist:{_,_ in})
        #expect(h.supplies.shelfStableFoodDays.confirmedValue==0)
        #expect(try quantity(h,local.inventory)==false)
        #expect(BaselinePreparedness.evaluate(household:h,referenceDate:date).contains{$0.actionID=="prep.food"})
        try local.confirmInventory([item()],household:&h,baseHouseholdRevision:h.revision,baseInventoryRevision:1,at:date,persist:{_,_ in})
        #expect(h.supplies.shelfStableFoodDays.confirmedValue==3)
        #expect(try quantity(h,local.inventory)==true)
        #expect(!BaselinePreparedness.evaluate(household:h,referenceDate:date).contains{$0.actionID=="prep.food"})
        try local.confirmInventory([item(unit:.count)],household:&h,baseHouseholdRevision:h.revision,baseInventoryRevision:2,at:date,persist:{_,_ in})
        #expect(h.supplies.shelfStableFoodDays.confirmedValue==nil)
        #expect(try quantity(h,local.inventory)==nil)
    }
    @Test func foodConfirmationAndProjectionAreAtomic()throws {
        var h=SampleHouseholds.oak,local=IntegratedAIState()
        let beforeH=h,before=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.persistence){try local.confirmInventory([item(amount:1)],household:&h,baseHouseholdRevision:h.revision,baseInventoryRevision:0,at:date,persist:{_,_ in throw SessionError.persistence})}
        #expect(h==beforeH);#expect(try DryRunJSON.encoder().encode(local)==before)
        try local.confirmInventory([item(amount:1)],household:&h,baseHouseholdRevision:h.revision,baseInventoryRevision:0,at:date,persist:{_,_ in})
        #expect(h.supplies.shelfStableFoodDays.confirmedValue==1)
        h.preparedness=PreparednessRecord(items:["food":PreparationFact(available:.confirmed(true),location:"Pantry")])
        #expect(BaselinePreparedness.evaluate(household:h,referenceDate:date).contains{$0.actionID=="prep.food"})
        #expect(try local.inventory.householdFoodGap(personIDs:h.people.map(\.id),at:date).deficit==2)
    }
}
