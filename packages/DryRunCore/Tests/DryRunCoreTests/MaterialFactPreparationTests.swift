import Foundation
import Testing
@testable import DryRunCore

/// Controlled-change pairs: one recorded household fact changes, and the Prepare action and the shopping list change
/// with it (reference §7.1). Each pair differs only in the named fact.
@Suite("Prepare actions respond to material household facts")
struct MaterialFactPreparationTests {
    let date = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!

    func prices() throws -> ShoppingList.PriceTable {
        try JSONDecoder().decode(ShoppingList.PriceTable.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/prices/tarrant-v1.json")))
    }
    func baseline(_ h: HouseholdProfile, home: HomeModel? = nil) -> [Recommendation] {
        BaselinePreparedness.evaluate(household: h, home: home, referenceDate: date)
    }
    func step(_ recs: [Recommendation], _ action: String, subject: String? = nil) -> Recommendation? {
        recs.first { $0.actionID == action && (subject == nil || $0.subjectID == subject) }
    }
    func withFact(_ h: HouseholdProfile, _ id: String, _ fact: PreparationFact) -> HouseholdProfile {
        var h = h
        var record = h.preparedness ?? PreparednessRecord()
        record.items[id] = fact
        h.preparedness = record
        return h
    }

    @Test("An owned extinguisher asks for its location, then a maintenance check, and is never a purchase")
    func extinguisherOwnership() throws {
        var unknown = SampleHouseholds.pine
        unknown.supplies.fireExtinguisher = .unknown
        unknown.preparedness?.items["extinguisher"] = nil

        var absent = unknown
        absent.supplies.fireExtinguisher = .confirmed(false)
        let get = try #require(step(baseline(absent), "prep.extinguisher"))
        #expect(get.titleKey == "prep.extinguisher.acquire.title")
        #expect(get.whyKey == "prep.acquire.why")
        #expect(get.effort == .low)
        #expect(try ShoppingList.build(household: absent, inventory: InventoryLedger(), prices: prices(), at: date).contains { $0.priceID == "fire-extinguisher" })

        // Unknown ownership is a free check first, not a purchase.
        let check = try #require(step(baseline(unknown), "prep.extinguisher"))
        #expect(check.titleKey == "prep.extinguisher.title")
        #expect(check.effort == .noCost)

        var owned = unknown
        owned.supplies.fireExtinguisher = .confirmed(true)
        let locate = try #require(step(baseline(owned), "prep.extinguisher"))
        #expect(locate.whyKey == "prep.location.why")
        #expect(locate.titleKey == "prep.extinguisher.title")
        #expect(locate.effort == .noCost)
        #expect(try !ShoppingList.build(household: owned, inventory: InventoryLedger(), prices: prices(), at: date).contains { $0.priceID == "fire-extinguisher" })

        // Ownership recorded only on the checklist (not the legacy supplies flag) still prevents a purchase suggestion.
        let checklistOwned = withFact(unknown, "extinguisher", PreparationFact(available: .confirmed(true)))
        #expect(try !ShoppingList.build(household: checklistOwned, inventory: InventoryLedger(), prices: prices(), at: date).contains { $0.priceID == "fire-extinguisher" })

        let located = withFact(owned, "extinguisher", PreparationFact(available: .confirmed(true), location: "Kitchen pantry"))
        let maintain = try #require(step(baseline(located), "prep.extinguisher"))
        #expect(maintain.titleKey == "prep.extinguisher.check.title")
        #expect(maintain.whyKey == "prep.extinguisher.check.why")

        let done = withFact(owned, "extinguisher", PreparationFact(available: .confirmed(true), location: "Kitchen pantry", checkedAt: date, familyAware: .confirmed(true)))
        #expect(step(baseline(done), "prep.extinguisher") == nil)
        #expect(BaselinePreparedness.recorded(household: done, referenceDate: date).contains { $0.actionID == "prep.extinguisher" && $0.titleKey == "prep.extinguisher.title" })
    }

    @Test("A recorded radio is never on the shopping list")
    func radioOwnership() throws {
        var h = SampleHouseholds.oak
        h.communications.batteryOrCrankRadio = .confirmed(false)
        #expect(try ShoppingList.build(household: h, inventory: InventoryLedger(), prices: prices(), at: date).contains { $0.priceID == "weather-radio" })
        h.communications.batteryOrCrankRadio = .confirmed(true)
        #expect(try !ShoppingList.build(household: h, inventory: InventoryLedger(), prices: prices(), at: date).contains { $0.priceID == "weather-radio" })
    }

    @Test("Absent alarms become an install task in the critical tier; renters see the landlord note")
    func absentAlarms() throws {
        var h = withFact(SampleHouseholds.lake, "smokeAlarms", PreparationFact(available: .confirmed(false)))
        h.housing.tenancy = .renter
        let alarm = try #require(step(baseline(h), "prep.smokeAlarms"))
        #expect(alarm.tier == .unmetEssentialRequirement)
        #expect(alarm.titleKey == "prep.smokeAlarms.acquire.title")
        #expect(alarm.whyKey == "prep.alarm.acquire.why")
        #expect(alarm.feasibilityNotes.contains("feasibility.landlord-for-repairs"))
    }

    @Test("Recorded medication storage instructions turn the task into an outage continuity plan")
    func medicationStorageContinuity() throws {
        let lake = SampleHouseholds.lake
        let insulin = try #require(lake.equipment.firstIndex { $0.requiresColdStorage })
        var none = lake
        none.equipment[insulin].storageInstructions = nil
        none.equipment[insulin].storagePlanConfirmed = nil
        let subject = "equipment.\(lake.equipment[insulin].id)"
        let record = try #require(step(baseline(none), "prep.coldStorage", subject: subject))
        #expect(record.titleKey == "prep.coldStorage.title")

        var recorded = none
        recorded.equipment[insulin].storageInstructions = "Keep refrigerated per the label"
        let plan = try #require(step(baseline(recorded), "prep.coldStorage", subject: subject))
        #expect(plan.titleKey == "prep.coldStorage.continuity.title")
        #expect(plan.whyKey == "prep.coldStorage.continuity.why")
        #expect(plan.matchedFactIDs.contains("\(subject).storageInstructions"))
        // Same identity, so a Beacon reorder or completion keeps pointing at the same task.
        #expect(plan.id == record.id)
        // Medical dependency stays first in its tier.
        #expect(RecommendationRanker.dependencyRank(plan.actionID) == 0)

        recorded.equipment[insulin].storagePlanConfirmed = .confirmed(true)
        #expect(step(baseline(recorded), "prep.coldStorage", subject: subject) == nil)
    }

    /// The ranch with one bedroom moved to a second floor.
    func twoStoryHome(upstairsRoom: String) -> HomeModel {
        var home = SampleHomes.ranch
        let ground = home.floors.map(\.level).min() ?? 0
        home.floors.append(Floor(id: "fl-upper", level: ground + 1, label: "Upstairs", elevationMeters: 2.8))
        if let i = home.spaces.firstIndex(where: { $0.id == upstairsRoom }) { home.spaces[i].floorID = "fl-upper" }
        return home
    }

    @Test("Upstairs sleeping plus a stair need adds a life-safety stair plan; a helper or a ground-floor room changes it")
    func upperFloorStairNeed() throws {
        var h = SampleHouseholds.pine
        let tio = try #require(h.people.firstIndex { $0.id == "p-pine-2" })
        let room = try #require(h.people[tio].sleepingSpaceID)
        let upstairs = twoStoryHome(upstairsRoom: room)
        h.people[tio].helperPersonID = nil
        let subject = "person.p-pine-2"

        let urgent = try #require(step(baseline(h, home: upstairs), "prep.stairPlan", subject: subject))
        #expect(urgent.tier == .unmetEssentialRequirement)
        #expect(urgent.whyKey == "prep.stairPlan.why")
        #expect(RecommendationRanker.dependencyRank(urgent.actionID) == 1)
        #expect(PreparationEditTarget.resolve(urgent, home: upstairs) == .checklist(id: "stairPlan.person.p-pine-2", titleKey: "prep.stairPlan.title"))

        var helped = h
        helped.people[tio].helperPersonID = "p-pine-1"
        let withHelper = try #require(step(baseline(helped, home: upstairs), "prep.stairPlan", subject: subject))
        #expect(withHelper.tier == .blockingUnknownFact)
        #expect(withHelper.whyKey == "prep.stairPlan.helper.why")

        // Same household, same stair need, ground-floor room: no stair task.
        #expect(step(baseline(h, home: SampleHomes.ranch), "prep.stairPlan") == nil)
        // No stair or mobility need upstairs: no stair task.
        var able = h
        able.people[tio].needs = []
        #expect(step(baseline(able, home: upstairs), "prep.stairPlan") == nil)

        // Multi-story without a known sleeping room: ask where they sleep.
        var unknownRoom = h
        unknownRoom.people[tio].sleepingSpaceID = nil
        #expect(step(baseline(unknownRoom, home: upstairs), "prep.stairPlan", subject: subject)?.whyKey == "prep.stairPlan.unknown.why")
        var noHome = h
        noHome.housing.floorCount = 2
        #expect(step(baseline(noHome), "prep.stairPlan", subject: subject)?.whyKey == "prep.stairPlan.unknown.why")

        // A recorded agreed plan closes it and is listed as recorded progress.
        let planned = withFact(h, "stairPlan.person.p-pine-2", PreparationFact(available: .confirmed(true), location: "Mamá helps; stair chair by the landing"))
        #expect(step(baseline(planned, home: upstairs), "prep.stairPlan") == nil)
        #expect(BaselinePreparedness.recorded(household: planned, home: upstairs, referenceDate: date).contains { $0.actionID == "prep.stairPlan" })
    }

    @Test("A stair plan never adds score points or changes the numeric score")
    func stairPlanDoesNotEnlargeScore() throws {
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        var h = SampleHouseholds.pine
        let tio = try #require(h.people.firstIndex { $0.id == "p-pine-2" })
        let upstairs = twoStoryHome(upstairsRoom: try #require(h.people[tio].sleepingSpaceID))
        h.people[tio].helperPersonID = nil
        let before = try ScoreCompiler.compile(rubric: rubric, assessments: HouseholdAssessment.assess(household: h, home: upstairs, inventory: InventoryLedger(), at: date))
        let planned = withFact(h, "stairPlan.person.p-pine-2", PreparationFact(available: .confirmed(true), location: "Plan"))
        let after = try ScoreCompiler.compile(rubric: rubric, assessments: HouseholdAssessment.assess(household: planned, home: upstairs, inventory: InventoryLedger(), at: date))
        #expect(before.overall == after.overall)
        #expect(before.evidenceCoverage == after.evidenceCoverage)
    }

    @Test("A tight budget puts free steps before purchases inside a tier; medical dependency still leads; tiers never cross")
    func budgetSequencing() {
        func rec(_ id: String, _ tier: PriorityTier, _ effort: EffortBand) -> Recommendation {
            Recommendation(actionID: id, tier: tier, titleKey: "", whyKey: "", matchedFactIDs: [], causeEventIDs: [], scenarioIDs: ["s"],
                           tryIntervention: nil, modeledEffectKey: nil, effort: effort, sourceIDs: [], verificationStatus: .unknown)
        }
        let recs = [
            rec("prep.smokeAlarms", .unmetEssentialRequirement, .low),
            rec("prep.contact", .unmetEssentialRequirement, .noCost),
            rec("prep.medicalBackup", .unmetEssentialRequirement, .moderate),
            rec("prep.firstAid", .scenarioSupplyOrContinuityGap, .low),
            rec("prep.outOfAreaContact", .scenarioSupplyOrContinuityGap, .noCost),
        ]
        func order(_ budget: Bool) -> [String] {
            recs.sorted { RecommendationRanker.prepareOrderKey($0, breadth: 1, limitedBudget: budget) < RecommendationRanker.prepareOrderKey($1, breadth: 1, limitedBudget: budget) }.map(\.actionID)
        }
        #expect(order(false) == ["prep.medicalBackup", "prep.smokeAlarms", "prep.contact", "prep.outOfAreaContact", "prep.firstAid"])
        #expect(order(true) == ["prep.medicalBackup", "prep.contact", "prep.smokeAlarms", "prep.outOfAreaContact", "prep.firstAid"])
    }

    @Test("A tight budget adds the budget note to purchases only")
    func budgetNote() throws {
        var h = SampleHouseholds.oak
        h.supplies.fireExtinguisher = .confirmed(false)
        h.supplies.limitedBudget = false
        #expect(step(baseline(h), "prep.extinguisher")?.feasibilityNotes.contains("feasibility.budget") == false)
        h.supplies.limitedBudget = true
        #expect(step(baseline(h), "prep.extinguisher")?.feasibilityNotes.contains("feasibility.budget") == true)
        #expect(baseline(h).filter { $0.effort == .noCost }.allSatisfy { !$0.feasibilityNotes.contains("feasibility.budget") })
    }

    @Test("Checking off an extinguisher or radio records ownership only, in one revision; Prepare moves on to find it")
    func purchaseRecordsOwnership() throws {
        var h = SampleHouseholds.pine
        h.supplies.fireExtinguisher = .confirmed(false)
        h.communications.batteryOrCrankRadio = .confirmed(false)
        var state = IntegratedAIState()
        let list = try ShoppingList.build(household: h, inventory: state.inventory, prices: prices(), at: date)
        let extinguisher = try #require(list.first { $0.priceID == "fire-extinguisher" })
        let radio = try #require(list.first { $0.priceID == "weather-radio" })
        let revision = h.revision
        var persisted = 0
        try state.recordPurchase(extinguisher, household: &h, baseHouseholdRevision: revision, at: date) { _, _ in persisted += 1 }
        #expect(persisted == 1 && h.revision == revision + 1)
        #expect(h.supplies.fireExtinguisher.confirmedValue == true)
        let next = try #require(step(baseline(h), "prep.extinguisher"))
        #expect(next.whyKey == "prep.location.why", "bought means owned, not located or checked")
        try state.recordPurchase(radio, household: &h, baseHouseholdRevision: h.revision, at: date) { _, _ in }
        #expect(h.communications.batteryOrCrankRadio.confirmedValue == true)
        let after = try ShoppingList.build(household: h, inventory: state.inventory, prices: prices(), at: date)
        #expect(!after.contains { ["fire-extinguisher", "weather-radio"].contains($0.priceID) })

        // A stale household revision saves nothing.
        var stale = h, staleState = state
        #expect(throws: SessionError.stale) {
            try staleState.recordPurchase(extinguisher, household: &stale, baseHouseholdRevision: h.revision - 1, at: date) { _, _ in Issue.record("stale write persisted") }
        }
        #expect(stale == h)
    }
}
