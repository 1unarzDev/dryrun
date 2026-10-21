import Foundation

/// The smart shopping list: what to buy, how much for THIS household, and a planning cost range from a reviewed
/// price table (content/prices). Core decides items, quantities, tiers and order; prices only estimate cost and
/// break ties within a tier (benefit per dollar). Beacon may explain an item; it never adds, removes or reorders.
public enum ShoppingList {
    public struct PriceTable: Codable, Sendable, Hashable {
        public struct Price: Codable, Sendable, Hashable {
            public var id: String; public var category: String; public var unit: String
            public var low: Double; public var high: Double; public var source: String; public var guidanceSourceIDs: [String]
        }
        public var version: String
        public var region: String
        public var retrievedAt: String
        public var reviewStatus: String
        public var items: [Price]
        public func price(_ id: String) -> Price? { items.first { $0.id == id } }
    }

    /// Medical dependencies first, then life safety, then the basic kit. Never reordered across tiers.
    public enum Tier: Int, Codable, Sendable, Comparable {
        case medical = 0, lifeSafety = 1, basics = 2
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Item: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var priceID: String
        public var tier: Tier
        /// Whole units to buy (gallons, person-days, watt-hours, each…), already sized for this household.
        public var quantity: Double
        public var unit: String
        /// Total planning range for `quantity`, in the table's currency.
        public var low: Double
        public var high: Double
        /// Relative safety benefit used only to order items inside a tier (higher first per dollar).
        public var benefit: Double
        /// Localization key `shop.reason.<reasonKey>` and its references.
        public var reasonKey: String
        public var values: [String: AlertResponse.Ref]
        public var sourceIDs: [String]
        public var benefitPerDollar: Double { benefit / max((low + high) / 2, 0.01) }
    }

    public enum Kit: Sendable, Equatable {
        /// Highest-ranked items whose upper cost estimates fit `limit` in total.
        case budget(limit: Double)
        case complete
    }

    /// Typical draw when the household has not recorded the device's watts (planning default, flagged in the reason).
    static let defaultWatts: [EquipmentPurpose: Double] = [
        .oxygenConcentrator: 300, .cpapOrBipap: 60, .powerWheelchair: 200, .homeDialysis: 500, .suction: 100,
        .feedingPump: 30, .communicationDevice: 20, .other: 100,
    ]
    /// Hours of backup the medical item is sized for (one overnight outage).
    public static let backupHours = 12.0

    public static func build(household: HouseholdProfile, inventory: InventoryLedger, prices: PriceTable, at date: Date) throws -> [Item] {
        var items: [Item] = []
        // Items checked off in the list are confirmed inventory (see `purchase`); water and food instead shrink Core's gaps.
        let bought = Set(inventory.items.filter { ($0.quantity.confirmedValue ?? 0) > 0 }.map(\.physicalID))
        func add(_ priceID: String, _ tier: Tier, quantity: Double, benefit: Double, reason: String,
                 values: [String: AlertResponse.Ref] = [:], subject: String? = nil, sources: [String] = []) {
            guard quantity > 0, let price = prices.price(priceID) else { return }
            let id = subject.map { "\(priceID)|\($0)" } ?? priceID
            guard !bought.contains(purchasedPhysicalID(id)) else { return }
            items.append(Item(id: id, priceID: priceID, tier: tier, quantity: quantity, unit: price.unit,
                              low: (price.low * quantity * 100).rounded() / 100, high: (price.high * quantity * 100).rounded() / 100,
                              benefit: benefit, reasonKey: reason, values: values,
                              sourceIDs: Array(Set(sources + price.guidanceSourceIDs)).sorted()))
        }

        // Medical dependencies.
        for equipment in household.equipment where equipment.isEssential {
            if equipment.requiresElectricalPower, equipment.compatibleBackupIDs.isEmpty {
                let recorded = equipment.powerWatts.confirmedValue
                let watts = recorded ?? defaultWatts[equipment.purpose] ?? 100
                let wattHours = (watts * backupHours / 100).rounded(.up) * 100
                add("battery-station-wh", .medical, quantity: wattHours, benefit: 100,
                    reason: recorded == nil ? "medical-power-estimated" : "medical-power",
                    values: ["equipment": .equipment(equipment.id)], subject: equipment.id, sources: ["S25"])
            }
            if equipment.requiresColdStorage {
                add("medication-cooler", .medical, quantity: 1, benefit: 90, reason: "medication-cold",
                    values: ["equipment": .equipment(equipment.id)], subject: equipment.id, sources: ["S25", "S54"])
            }
        }

        // Life safety.
        let people = max(household.people.count, 1)
        if household.supplies.fireExtinguisher.confirmedValue != true {
            add("fire-extinguisher", .lifeSafety, quantity: 1, benefit: 60, reason: "extinguisher", sources: ["S53"])
        }
        if !inventory.items.contains(where: { $0.preparationKind == .flashlight && $0.quantity.confirmedValue ?? 0 > 0 }) {
            add("flashlight", .lifeSafety, quantity: Double(people), benefit: 40, reason: "flashlight")
            add("batteries-aa", .lifeSafety, quantity: 1, benefit: 15, reason: "batteries")
        }
        add("weather-radio", .lifeSafety, quantity: 1, benefit: 35, reason: "radio")
        if let cold = household.people.first(where: { $0.needs.contains(.coldSensitive) || $0.ageBand == .infant || $0.ageBand == .olderAdult }) {
            add("emergency-blankets", .lifeSafety, quantity: Double(people), benefit: 20, reason: "blankets",
                values: ["person": .person(cold.id)])
        }

        // Basic kit, sized from Core's own gaps.
        let personIDs = household.people.map(\.id)
        let water = try inventory.waterGap(people: people, personIDs: personIDs.isEmpty ? nil : personIDs, at: date)
        let missingLiters = water.deficit ?? water.required
        add("water-gallon", .basics, quantity: (missingLiters / 3.785411784).rounded(.up), benefit: 50, reason: "water",
            sources: water.sourceIDs)
        if !personIDs.isEmpty {
            let food = try inventory.householdFoodGap(personIDs: personIDs, at: date)
            let days = (food.deficit ?? food.required).rounded(.up)
            add("food-person-day", .basics, quantity: days * Double(people), benefit: 45, reason: "food", sources: food.sourceIDs)
        }
        if !inventory.items.contains(where: { $0.preparationKind == .firstAidKit && $0.quantity.confirmedValue ?? 0 > 0 }) {
            add("first-aid-kit", .basics, quantity: 1, benefit: 30, reason: "first-aid")
        }
        if household.communications.powerBankCharges.confirmedValue ?? 0 < 1 {
            add("power-bank", .basics, quantity: Double(max(household.communications.handsetCount, 1)), benefit: 25, reason: "power-bank")
        }
        for pet in household.pets {
            add("pet-food-week", .basics, quantity: Double(pet.count), benefit: 20, reason: "pet-food", subject: pet.id)
            if pet.carrierAvailable.confirmedValue != true {
                add("pet-carrier", .basics, quantity: Double(pet.count), benefit: 15, reason: "pet-carrier", subject: pet.id)
            }
        }
        let infants = household.people.filter { $0.ageBand == .infant }.count
        add("infant-supplies-week", .basics, quantity: Double(infants), benefit: 40, reason: "infant")

        return items.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.benefitPerDollar != b.benefitPerDollar { return a.benefitPerDollar > b.benefitPerDollar }
            return a.id < b.id
        }
    }

    /// The Budget kit keeps the ranked order and skips anything whose upper estimate no longer fits; the Complete kit is
    /// every item. A medical item that alone exceeds the budget is never silently dropped from the Complete kit.
    public static func kit(_ ranked: [Item], _ kit: Kit) -> [Item] {
        guard case .budget(let limit) = kit else { return ranked }
        var remaining = limit
        return ranked.filter { item in
            guard item.high <= remaining else { return false }
            remaining -= item.high
            return true
        }
    }

    static func purchasedPhysicalID(_ itemID: String) -> String { "shop-" + itemID }

    /// What checking an item off records: confirmed, accessible inventory the household now has. Water and food enter
    /// Core's gap arithmetic in their own units; flashlights and first-aid kits carry their reviewed identity so the
    /// Prepare list and the score count them; everything else is remembered so the list no longer suggests it.
    public static func purchase(_ item: Item, household: HouseholdProfile, at date: Date) -> InventoryItem {
        let people = max(household.people.count, 1)
        let everyone = household.people.map(\.id)
        let base = "shop-\(item.id)-\(Int(date.timeIntervalSince1970))"
        switch item.priceID {
        case "water-gallon":
            return InventoryItem(id: base, physicalID: base, category: "water", quantity: .confirmed(item.quantity), unit: .usGallon,
                                 usableQuantity: .confirmed(item.quantity), accessible: .confirmed(true), lastConfirmedAt: date)
        case "food-person-day":
            let days = (item.quantity / Double(people)).rounded(.down)
            return InventoryItem(id: base, physicalID: base, category: "food", quantity: .confirmed(days), unit: .day,
                                 usableQuantity: .confirmed(days), accessible: .confirmed(true), subjectIDs: everyone, lastConfirmedAt: date)
        default:
            let physical = purchasedPhysicalID(item.id)
            let kind: InventoryPreparationKind? = item.priceID == "flashlight" ? .flashlight : item.priceID == "first-aid-kit" ? .firstAidKit : nil
            let category = categories[item.priceID] ?? "other"
            let unit: InventoryUnit = item.unit == "wattHour" ? .wattHour : .count
            return InventoryItem(id: physical, physicalID: physical, category: category, quantity: .confirmed(item.quantity), unit: unit,
                                 usableQuantity: .confirmed(item.quantity), accessible: .confirmed(true), lastConfirmedAt: date, preparationKind: kind)
        }
    }

    static let categories: [String: String] = [
        "flashlight": "light", "batteries-aa": "light", "first-aid-kit": "firstAid", "weather-radio": "communication",
        "power-bank": "power", "battery-station-wh": "power", "medication-cooler": "medication", "pet-food-week": "petSupplies",
        "pet-carrier": "petSupplies", "infant-supplies-week": "infantSupplies", "fire-extinguisher": "other", "emergency-blankets": "other",
    ]

    public static func total(_ items: [Item]) -> (low: Double, high: Double) {
        (items.reduce(0) { $0 + $1.low }, items.reduce(0) { $0 + $1.high })
    }
}
