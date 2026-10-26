import Foundation
import Testing
@testable import DryRunCore

@Suite("Confirmed inventory identity drives existing preparations") struct PreparationInventoryTests {
    let date=Date(timeIntervalSince1970:1792368000)
    func item(_ kind:InventoryPreparationKind,amount:Double=1)->InventoryItem {
        InventoryItem(id:kind.rawValue,physicalID:kind.rawValue,category:kind == .flashlight ? "light":"firstAid",quantity:.confirmed(amount),unit:.count,usableQuantity:.confirmed(amount),accessible:.confirmed(true),preparationKind:kind)
    }
    @Test func confirmationPropagatesWithoutMarkingUnreviewedChecksComplete()throws {
        var household=SampleHouseholds.oak,local=IntegratedAIState()
        household.preparedness=PreparednessRecord(items:["flashlight":PreparationFact(available:.confirmed(false)),"firstAid":PreparationFact(available:.confirmed(false))])
        try local.confirmInventory([item(.flashlight,amount:2),item(.firstAidKit)],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in})
        #expect(household.supplies.flashlights.confirmedValue==2)
        #expect(household.supplies.firstAidKit.confirmedValue==true)
        #expect(BaselinePreparedness.recordedSupplyAvailability("flashlight",household:household)==true)
        #expect(BaselinePreparedness.recordedSupplyAvailability("firstAid",household:household)==true)
        // Item identity/usable stock do not invent a storage location or complete unrelated tasks.
        #expect(household.preparedness?.items["flashlight"]?.location.isEmpty ?? true)
        let assessment=try HouseholdAssessment.assess(household:household,home:nil,inventory:local.inventory,at:date)
        #expect(assessment.first{$0.criterionID=="essentials"}?.predicates["light"]==true)
        #expect(assessment.first{$0.criterionID=="essentials"}?.predicates["firstAid"]==true)
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let catalog=PreparationTaskCatalog.build(household:household,home:nil,rubric:rubric,at:date,includeSatisfied:true)
        #expect(catalog.first{$0.actionID=="prep.flashlight"}?.completionPredicates==["light"])
        #expect(catalog.first{$0.actionID=="prep.firstAid"}?.completionPredicates==["firstAid"])
        #expect(catalog.first{$0.actionID=="prep.sanitation"}?.completionPredicates==["sanitation"])

    }
    @Test func categoryAloneDoesNotInferIdentityAndReplacementClearsProjection()throws {
        var household=SampleHouseholds.oak,local=IntegratedAIState()
        try local.confirmInventory([item(.flashlight),item(.firstAidKit)],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in})
        var light=item(.flashlight),aid=item(.firstAidKit)
        light.preparationKind=nil;aid.preparationKind=nil
        try local.confirmInventory([light,aid],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:1,at:date,persist:{_,_ in})
        #expect(household.supplies.flashlights.confirmedValue==nil)
        #expect(household.supplies.firstAidKit.confirmedValue==nil)
        #expect(try local.inventory.preparationItemGap(kind:.flashlight,personIDs:household.people.map(\.id),at:date).deficit==nil)
    }
    @Test func expiryScopeAndUnknownsOverrideOlderPositiveTotals()throws {
        var household=SampleHouseholds.oak,local=IntegratedAIState()
        household.supplies.flashlights = .confirmed(8);household.supplies.firstAidKit = .confirmed(true)
        var light=item(.flashlight),aid=item(.firstAidKit)
        light.expiresAt=date.addingTimeInterval(-1);aid.subjectIDs=[household.people[0].id]
        try local.confirmInventory([light,aid],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in})
        #expect(household.supplies.flashlights.confirmedValue==0)
        #expect(household.supplies.firstAidKit.confirmedValue==nil)
        let values=try HouseholdAssessment.assess(household:household,home:nil,inventory:local.inventory,at:date).first{$0.criterionID=="essentials"}
        #expect(values?.predicates["light"]==false);#expect(values?.predicates["firstAid"]==nil)
    }
    @Test func invalidMappingFractionalCountsAndFailedSavesDoNotPublish()throws {
        var household=SampleHouseholds.oak,local=IntegratedAIState()
        let before=household
        var wrong=item(.flashlight);wrong.category="fuel"
        for invalid in [wrong,item(.firstAidKit,amount:0.5),item(.flashlight,amount:Double.greatestFiniteMagnitude)] {
            #expect(throws:SessionError.invalidCommand){try local.confirmInventory([invalid],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in Issue.record("Invalid mapping reached persistence")})}
        }
        #expect(throws:SessionError.persistence){try local.confirmInventory([item(.flashlight)],household:&household,baseHouseholdRevision:household.revision,baseInventoryRevision:0,at:date,persist:{_,_ in throw SessionError.persistence})}
        #expect(household==before);#expect(local.inventory.items.isEmpty)
        let legacy=item(.flashlight);var json=try #require(JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(legacy)) as? [String:Any]);json.removeValue(forKey:"preparationKind")
        #expect(try DryRunJSON.decoder().decode(InventoryItem.self,from:JSONSerialization.data(withJSONObject:json)).preparationKind==nil)
    }
}
