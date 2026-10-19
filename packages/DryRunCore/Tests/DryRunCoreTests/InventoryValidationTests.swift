import Foundation
import Testing
@testable import DryRunCore

@Suite("Inventory evidence, zero stock and read validation") struct InventoryValidationTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func item(_ category:String="water",amount:Double=0,unit:InventoryUnit = .liter)->InventoryItem {
        InventoryItem(id:category,physicalID:category,category:category,quantity:.confirmed(amount),unit:unit,usableQuantity:.confirmed(amount),accessible:.confirmed(true))
    }
    @Test func emptyAccessibleContainerCannotEarnAccessCredit()throws {
        for category in ["water","food"] {
            var ledger=InventoryLedger()
            try ledger.confirm([item(category,unit:category=="water" ? .liter:.day)],baseRevision:0,at:date)
            #expect(try ledger.usableAccess(category:category,at:date)==false)
            let values=try HouseholdAssessment.assess(household:SampleHouseholds.oak,home:nil,inventory:ledger,at:date)
            #expect(values.first{$0.criterionID==category}?.predicates["accessible"]==false)
            var unreadable=item(category,amount:2,unit:category=="water" ? .liter:.day)
            unreadable.usableQuantity = .unknown
            try ledger.confirm([unreadable],baseRevision:1,at:date)
            #expect(try ledger.usableAccess(category:category,at:date)==true)
            #expect(try HouseholdAssessment.assess(household:SampleHouseholds.oak,home:nil,inventory:ledger,at:date).first{$0.criterionID==category}?.predicates["quantity"]==nil)
        }
    }
    @Test func confirmedZeroIsKnownDespiteUnknownUsabilityAndAccess()throws {
        var ledger=InventoryLedger(),empty=item()
        empty.usableQuantity = .unknown;empty.accessible = .unknown
        try ledger.confirm([empty],baseRevision:0,at:date)
        let gap=try ledger.waterGap(people:2,at:date)
        #expect(!gap.unknown);#expect(gap.confirmedUsable==0);#expect(gap.deficit==gap.required)
        let session=SimulationSession(id:"empty",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),inventory:.init(ledger:ledger,asOf:date))
        let receipt=try session.query(library:SimFixtures.library)
        #expect(receipt.snapshot.resources["res.water.stored"]?.amount==0)
        #expect(receipt.inventory?.items.first?.remaining==0)
        #expect(session.inventory?.ledger.items.first?.usableQuantity.confirmedValue==nil)
    }
    @Test func duplicateBatchAndPersistenceFailureDoNotPublish()throws {
        var ledger=InventoryLedger();let first=item(amount:2)
        var second=first;second.quantity = .confirmed(3);second.usableQuantity = .confirmed(3)
        #expect(throws:SessionError.duplicate){try ledger.confirm([first,second],baseRevision:0,at:date)}
        #expect(ledger.revision==0);#expect(ledger.items.isEmpty)
        var local=IntegratedAIState(),household=SampleHouseholds.oak
        let original=household
        #expect(throws:SessionError.invalidCommand){try local.confirmInventory([item(amount:Double.greatestFiniteMagnitude,unit:.usGallon)],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in Issue.record("Overflow must reject before persistence")})}
        #expect(household==original);#expect(local.inventory.revision==0)
    }
    @Test func decodedUnconfirmedOriginCannotBypassQuantityOrAccessChecks()throws {
        var ledger=InventoryLedger();var stock=item(amount:2);stock.usableQuantity = .unknown
        try ledger.confirm([stock],baseRevision:0,at:date)
        var json=try #require(JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(ledger)) as? [String:Any])
        var items=try #require(json["items"] as? [[String:Any]])
        items[0]["accessible"]=["value":true,"origin":"scanObserved","status":"confirmed"]
        json["items"]=items
        let decoded=try DryRunJSON.decoder().decode(InventoryLedger.self,from:JSONSerialization.data(withJSONObject:json))
        #expect(throws:SessionError.invalidCommand){try decoded.waterGap(people:2,at:date)}
        #expect(throws:SessionError.invalidCommand){try decoded.usableAccess(category:"water",at:date)}
        #expect(throws:SessionError.invalidCommand){try HouseholdAssessment.assess(household:SampleHouseholds.oak,home:nil,inventory:decoded,at:date)}
    }
    @Test func overflowCannotBecomeInfiniteStockInGapsOrExercise()throws {
        var ledger=InventoryLedger()
        try ledger.confirm([item(amount:Double.greatestFiniteMagnitude,unit:.usGallon)],baseRevision:0,at:date)
        #expect(throws:SessionError.invalidCommand){try ledger.waterGap(people:2,at:date)}
        var another=item(amount:Double.greatestFiniteMagnitude,unit:.usGallon);another.id="second";another.physicalID="second"
        try ledger.confirm([another],baseRevision:1,at:date)
        let session=SimulationSession(id:"overflow",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),inventory:.init(ledger:ledger,asOf:date))
        #expect(throws:SessionError.invalidCommand){try session.query(library:SimFixtures.library)}
    }
    @Test func subjectRestrictedStockNeverBecomesSharedHouseholdStock()throws {
        let people=SampleHouseholds.oak.people.map(\.id)
        var water=item(amount:100),food=item("food",amount:10,unit:.day)
        water.subjectIDs=[people[0]];food.subjectIDs=[people[0]]
        var ledger=InventoryLedger()
        try ledger.confirm([water,food],baseRevision:0,at:date)
        let gap=try ledger.waterGap(people:people.count,personIDs:people,at:date)
        #expect(gap.scopeUnsupported==true);#expect(gap.deficit==nil);#expect(gap.confirmedUsable==0)
        #expect(try ledger.usableAccess(category:"water",personIDs:people,at:date)==nil)
        #expect(try ledger.householdFoodGap(personIDs:people,at:date).scopeUnsupported==true)
        #expect(try ledger.usableAccess(category:"food",personIDs:people,at:date)==nil)
        let session=SimulationSession(id:"scoped",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),inventory:.init(ledger:ledger,asOf:date))
        let receipt=try session.query(library:SimFixtures.library)
        #expect(receipt.inventory?.items.first(where:{$0.id=="water"})?.remaining==100)
        #expect(receipt.inventory?.items.first(where:{$0.id=="water"})?.consumed==0)
        // Source restrictions and balances remain unchanged by an exercise query.
        #expect(session.inventory?.ledger.items.first?.subjectIDs==[people[0]])
        water.subjectIDs=people;food.subjectIDs=people
        try ledger.confirm([water,food],baseRevision:1,at:date)
        #expect(try ledger.waterGap(people:people.count,personIDs:people,at:date).deficit==0)
        #expect(try ledger.waterGap(people:people.count,at:date).scopeUnsupported==true)
        #expect(try ledger.householdFoodGap(personIDs:people,at:date).deficit==0)
        var shared=item(amount:100);shared.id="shared";shared.physicalID="shared"
        water.subjectIDs=[people[0]]
        try ledger.confirm([water,shared],baseRevision:2,at:date)
        let mixed=try ledger.waterGap(people:people.count,personIDs:people,at:date)
        #expect(mixed.scopeUnsupported==true);#expect(mixed.deficit==0)
    }

}
