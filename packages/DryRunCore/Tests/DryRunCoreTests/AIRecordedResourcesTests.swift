import Foundation
import Testing
@testable import DryRunCore

@Suite("Recorded resource context") struct AIRecordedResourcesTests {
    @Test func retainsResourceFactsAndLinksWithoutPrivateLabels() throws {
        var h=SampleHouseholds.oak
        h.backupPower[0].label="PRIVATE garage phone 555-0199"
        h.backupPower[0].setupConfirmed = .unknown
        h.backupPower[0].usableEnergyWh = .confirmed(600)
        let at=Date(timeIntervalSince1970:1_792_368_000)
        var inventory=InventoryLedger()
        try inventory.confirm([InventoryItem(id:"stored-water",physicalID:"PRIVATE physical label",category:"water",quantity:.confirmed(12),unit:.liter,usableQuantity:.confirmed(8),accessible:.confirmed(false),locationID:"sp-closet",expiresAt:at.addingTimeInterval(86400),subjectIDs:[h.people[1].id],evidenceIDs:["typed-water"])],baseRevision:0,at:at)
        let context=HouseholdContextSnapshot(h,inventory:inventory,at:at)
        #expect(context.inventory?.revision==1)
        #expect(context.inventory?.items.first?.accessible.confirmedValue==false)
        #expect(context.inventory?.items.first?.usableQuantity.confirmedValue==8)
        #expect(context.inventory?.items.first?.subjectIDs==[h.people[1].id])
        #expect(context.inventory?.items.first?.locationID=="sp-closet")
        #expect(context.inventory?.items.first?.lastConfirmedAt==at)
        #expect(context.backupPower?.first?.usableEnergyWh.confirmedValue==600)
        #expect(context.backupPower?.first?.setupConfirmed.confirmedValue==nil)
        #expect(context.equipment.first?.personID==h.equipment.first?.personID)
        let encoded=try DryRunJSON.encoder().encode(context),text=String(decoding:encoded,as:UTF8.self)
        #expect(!text.contains("PRIVATE"));#expect(!text.contains("physicalID"));#expect(!text.contains("555-0199"))
        #expect(context.evidence.contains{$0.id=="recorded-inventory"})
        let restored=try DryRunJSON.decoder().decode(HouseholdContextSnapshot.self,from:encoded)
        #expect(restored.inventory?.items.first?.expiresAt==at.addingTimeInterval(86400))
        #expect(HouseholdContextSnapshot(h,at:at).inventory==nil)
        #expect(inventory.items.first?.usableQuantity.confirmedValue==8)
    }
    @Test func typeScriptValidatedHostFixtureAndHistoricalContextDecode() throws {
        struct Context:Decodable {var household:HouseholdContextSnapshot;var taskCatalog:[PreparationTaskProposal]?}
        struct Proposal:Decodable {var tasks:[PreparationTaskProposal]}
        struct Fixture:Decodable {var context:Context;var proposal:Proposal}
        let data=try Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/recorded-resource-context.json"))
        let fixture=try DryRunJSON.decoder().decode(Fixture.self,from:data)
        #expect(fixture.context.taskCatalog?.first { $0.actionID == "prep.fireDrill" }?.destination == .checklist(id:"fireDrill",titleKey:"prep.fireDrill.title"))
        #expect(fixture.proposal.tasks.first?.destination == .equipment(fixture.context.household.equipment[0].id))
        #expect(fixture.proposal.tasks.last?.destination == nil)
        #expect(fixture.context.household.inventory?.items.count==2)
        #expect(fixture.context.household.inventory?.items.first?.accessible.confirmedValue==false)
        #expect(fixture.context.household.backupPower?.first?.setupConfirmed.confirmedValue==nil)
        let encoded=try DryRunJSON.encoder().encode(fixture.context.household)
        var historical=try #require(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        historical.removeValue(forKey:"inventory");historical.removeValue(forKey:"backupPower")
        let old=try DryRunJSON.decoder().decode(HouseholdContextSnapshot.self,from:JSONSerialization.data(withJSONObject:historical))
        #expect(old.inventory==nil);#expect(old.backupPower==nil)
        #expect(old.people.map(\.id)==fixture.context.household.people.map(\.id))
    }
}
