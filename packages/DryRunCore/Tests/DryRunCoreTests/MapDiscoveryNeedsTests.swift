import Testing
@testable import DryRunCore

@Suite("Household resource discovery")
struct MapDiscoveryNeedsTests {
    @Test func ownedExtinguisherDoesNotCreateAnotherSupplyPurchaseSearch() {
        var family = SampleHouseholds.oak
        family.preparedness = PreparednessRecord()
        var missing = PreparationFact()
        missing.available = .confirmed(false)
        family.preparedness?.items["extinguisher"] = missing
        #expect(MapDiscoveryNeeds.queries(for: family).contains("hardware store"))
        family.preparedness?.items["extinguisher"]?.available = .confirmed(true)
        #expect(!MapDiscoveryNeeds.queries(for: family).contains("hardware store"))
        #expect(MapDiscoveryNeeds.queries(for: family).contains("pharmacy"))
        #expect(MapDiscoveryNeeds.queries(for: family).contains("grocery"))
    }
}
