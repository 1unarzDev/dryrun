import XCTest
@testable import DryRunCore

final class ShoppingListTests: XCTestCase {
    let date = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
    func prices() throws -> ShoppingList.PriceTable {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../content/prices/tarrant-v1.json")
        return try JSONDecoder().decode(ShoppingList.PriceTable.self, from: Data(contentsOf: url))
    }

    func testQuantitiesAreSizedForTheHousehold() throws {
        let oak = SampleHouseholds.oak
        let items = try ShoppingList.build(household: oak, inventory: InventoryLedger(), prices: try prices(), at: date)
        let people = Double(oak.people.count)
        let water = try XCTUnwrap(items.first { $0.priceID == "water-gallon" })
        XCTAssertEqual(water.quantity, people * 3, "one gallon per person per day for three days (S26)")
        XCTAssertEqual(items.first { $0.priceID == "food-person-day" }?.quantity, people * 3)
        // One per person minus the flashlights Oak already recorded.
        XCTAssertEqual(items.first { $0.priceID == "flashlight" }?.quantity, people - Double(oak.supplies.flashlights.confirmedValue ?? 0))
        // Oak's oxygen concentrator has no confirmed compatible backup: a station sized for 12 hours.
        let station = try XCTUnwrap(items.first { $0.priceID == "battery-station-wh" })
        XCTAssertEqual(station.values["equipment"], .equipment("eq-oxygen"))
        let watts = oak.equipment.first { $0.id == "eq-oxygen" }!.powerWatts.confirmedValue ?? 300
        XCTAssertEqual(station.quantity, (watts * 12 / 100).rounded(.up) * 100)
        XCTAssertEqual(station.low, (0.6 * station.quantity * 100).rounded() / 100)

        // Recorded water reduces what to buy.
        var ledger = InventoryLedger()
        try ledger.confirm([InventoryItem(id: "w", physicalID: "jugs", category: "water", quantity: .confirmed(5), unit: .usGallon,
                                          usableQuantity: .confirmed(5), accessible: .confirmed(true))], baseRevision: 0, at: date)
        let after = try ShoppingList.build(household: oak, inventory: ledger, prices: try prices(), at: date)
        XCTAssertEqual(after.first { $0.priceID == "water-gallon" }?.quantity, people * 3 - 5)

        // Pets and refrigerated medication come from the household's own records.
        let lake = try ShoppingList.build(household: SampleHouseholds.lake, inventory: InventoryLedger(), prices: try prices(), at: date)
        XCTAssertTrue(lake.contains { $0.priceID == "medication-cooler" && $0.values["equipment"] == .equipment("eq-insulin") })
        for household in SampleHouseholds.all where !household.pets.isEmpty {
            let list = try ShoppingList.build(household: household, inventory: InventoryLedger(), prices: try prices(), at: date)
            XCTAssertEqual(list.filter { $0.priceID == "pet-food-week" }.reduce(0) { $0 + $1.quantity }, Double(household.pets.reduce(0) { $0 + $1.count }))
        }
    }

    func testMedicalDependenciesRankFirstThenBenefitPerDollar() throws {
        for household in SampleHouseholds.all {
            let items = try ShoppingList.build(household: household, inventory: InventoryLedger(), prices: try prices(), at: date)
            XCTAssertEqual(items.map(\.tier), items.map(\.tier).sorted(), "never reordered across tiers")
            if household.equipment.contains(where: { $0.isEssential }) { XCTAssertEqual(items.first?.tier, .medical, household.id) }
            for tier in [ShoppingList.Tier.medical, .lifeSafety, .basics] {
                let ratios = items.filter { $0.tier == tier }.map(\.benefitPerDollar)
                XCTAssertEqual(ratios, ratios.sorted(by: >), "\(household.id) \(tier)")
            }
            XCTAssertTrue(items.allSatisfy { $0.low <= $0.high && $0.quantity > 0 && !$0.sourceIDs.isEmpty })
            XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        }
    }

    func testBudgetKitStaysWithinTheLimitAndKeepsRankOrder() throws {
        let items = try ShoppingList.build(household: SampleHouseholds.oak, inventory: InventoryLedger(), prices: try prices(), at: date)
        for limit in [0.0, 50, 150, 400, 1000] {
            let kit = ShoppingList.kit(items, .budget(limit: limit))
            XCTAssertLessThanOrEqual(ShoppingList.total(kit).high, limit + 0.0001)
            let order = kit.compactMap { k in items.firstIndex { $0.id == k.id } }
            XCTAssertEqual(order, order.sorted())
        }
        XCTAssertEqual(ShoppingList.kit(items, .complete), items)
        XCTAssertTrue(ShoppingList.kit(items, .budget(limit: 0)).isEmpty)
        // A budget too small for the medical station still buys the cheaper items after it, in order.
        let small = ShoppingList.kit(items, .budget(limit: 150))
        XCTAssertFalse(small.contains { $0.priceID == "battery-station-wh" })
        XCTAssertFalse(small.isEmpty)
    }

    func testPriceTableIsLabelledAsADraftWithSourcesAndDate() throws {
        let table = try prices()
        XCTAssertEqual(table.retrievedAt, "2026-10-20")
        XCTAssertFalse(table.items.isEmpty)
        XCTAssertTrue(table.items.allSatisfy { !$0.source.isEmpty && !$0.guidanceSourceIDs.isEmpty && $0.low > 0 && $0.low <= $0.high })
    }

    func testBuyingAnItemUpdatesInventoryGapsAndTheList() throws {
        let oak = SampleHouseholds.oak
        var ledger = InventoryLedger()
        let items = try ShoppingList.build(household: oak, inventory: ledger, prices: try prices(), at: date)
        let water = items.first { $0.priceID == "water-gallon" }!, light = items.first { $0.priceID == "flashlight" }!
        let radio = items.first { $0.priceID == "weather-radio" }!
        let bought = [water, light, radio].map { ShoppingList.purchase($0, household: oak, at: date) }
        try ledger.confirm(bought, baseRevision: 0, at: date)
        XCTAssertEqual(try ledger.waterGap(people: oak.people.count, personIDs: oak.people.map(\.id), at: date).deficit, 0)
        XCTAssertEqual(try ledger.preparationItemGap(kind: .flashlight, personIDs: oak.people.map(\.id), at: date).deficit, 0)
        let after = try ShoppingList.build(household: oak, inventory: ledger, prices: try prices(), at: date)
        XCTAssertFalse(after.contains { ["water-gallon", "flashlight", "weather-radio"].contains($0.priceID) })
        XCTAssertTrue(after.contains { $0.priceID == "battery-station-wh" }, "unbought items remain")
    }
}
