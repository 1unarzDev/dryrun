import Foundation
import Testing
@testable import DryRunCore

/// Golden-household and controlled-change checks of the fixed score rubric (reference §7.4). Every sample household is
/// scored through the same path the app uses: recorded facts -> HouseholdAssessment predicates -> ScoreCompiler.
/// Practice preservation (short continuity check keeps route/communication evidence) is covered in
/// PracticeEvidencePreservationTests.
@Suite("Score rubric invariants")
struct ScoreRubricInvariantTests {
    let date = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
    let rubric: RubricDefinition = try! DryRunJSON.decoder().decode(RubricDefinition.self,
        from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))

    func score(_ h: HouseholdProfile, home: HomeModel? = SampleHomes.ranch, inventory: InventoryLedger = InventoryLedger()) throws -> PreparednessScorecard {
        try ScoreCompiler.compile(rubric: rubric, assessments: HouseholdAssessment.assess(household: h, home: home, inventory: inventory, at: date))
    }
    func water(_ gallons: Double, id: String = "jugs") throws -> InventoryLedger {
        var ledger = InventoryLedger()
        try ledger.confirm([InventoryItem(id: id, physicalID: id, category: "water", quantity: .confirmed(gallons), unit: .usGallon,
                                          usableQuantity: .confirmed(gallons), accessible: .confirmed(true))], baseRevision: 0, at: date)
        return ledger
    }
    func withFact(_ h: HouseholdProfile, _ id: String, _ fact: PreparationFact) -> HouseholdProfile {
        var h = h
        var record = h.preparedness ?? PreparednessRecord()
        record.items[id] = fact
        h.preparedness = record
        return h
    }

    @Test("Golden households: bounded, capped, provisional, every criterion has a status, and repeatable")
    func goldenHouseholds() throws {
        for h in SampleHouseholds.all {
            let card = try score(h)
            #expect(card.provisional, "\(h.id)")
            #expect(card.rubricVersion == rubric.version)
            #expect(Set(card.statuses.keys) == Set(rubric.criteria.map(\.id)), "\(h.id)")
            if let overall = card.overall {
                #expect((0...100).contains(overall) && overall <= card.cap, "\(h.id)")
            }
            #expect((0...100).contains(card.evidenceCoverage))
            // Identical accepted evidence gives an identical number.
            let again = try score(h)
            #expect(again.overall == card.overall && again.preparation == card.preparation && again.statuses == card.statuses)
        }
    }

    @Test("Unknown is never confirmed: an unanswered critical item earns nothing and caps at the unverified level, not the gap level")
    func unknownIsNotConfirmed() throws {
        var h = SampleHouseholds.oak
        h.preparedness?.items["smokeAlarms"] = nil
        let unknown = try score(h)
        #expect(unknown.statuses["alarms"] == .unknown)
        #expect(unknown.capReasons.contains("alarms"))
        // Unknown alarms leave no assessed failure for this criterion; confirmed absence does.
        let unknownAlarms = try HouseholdAssessment.assess(household: h, home: SampleHomes.ranch, inventory: InventoryLedger(), at: date).first { $0.criterionID == "alarms" }
        #expect(unknownAlarms?.predicates.values.contains(false) == false)

        let absent = try score(withFact(h, "smokeAlarms", PreparationFact(available: .confirmed(false))))
        #expect(absent.cap == rubric.knownGapCap, "a confirmed gap caps at the gap level")
        #expect(unknown.cap >= absent.cap)

        let ready = try score(withFact(h, "smokeAlarms", PreparationFact(available: .confirmed(true), location: "Hallway", checkedAt: date, coverageReviewed: .confirmed(true))))
        #expect(ready.statuses["alarms"] == .met)
        #expect(try #require(ready.preparation) > (unknown.preparation ?? 0))
        // An assumed value is not a confirmed one.
        var assumed = h
        assumed.supplies.fireExtinguisher = .assumed(true)
        #expect(try score(assumed).overall == unknown.overall)
    }

    @Test("A critical known gap is not hidden by easy points")
    func criticalGapNotHidden() throws {
        var h = withFact(SampleHouseholds.oak, "smokeAlarms", PreparationFact(available: .confirmed(false)))
        h = withFact(h, "sanitation", PreparationFact(available: .confirmed(true), location: "Garage"))
        h.preparedness?.reviewedAt = date
        let base = try score(h)
        let ample = try water(100)
        let more = try score(h, inventory: ample)
        #expect(try #require(more.preparation) >= (base.preparation ?? 0))
        for card in [base, more] {
            #expect(card.capReasons.contains("alarms"))
            #expect(try #require(card.overall) <= rubric.knownGapCap)
        }
    }

    @Test("Duplicate evidence cannot add credit")
    func duplicateEvidence() throws {
        let h = SampleHouseholds.oak
        var ledger = try water(4)
        let once = try score(h, inventory: ledger)
        // Re-confirming the same container replaces it rather than adding it again.
        try ledger.confirm([InventoryItem(id: "jugs", physicalID: "jugs", category: "water", quantity: .confirmed(4), unit: .usGallon,
                                          usableQuantity: .confirmed(4), accessible: .confirmed(true))], baseRevision: ledger.revision, at: date)
        let twice = try score(h, inventory: ledger)
        #expect(twice.overall == once.overall && twice.statuses == once.statuses)
        let single = try water(4).waterGap(people: h.people.count, personIDs: h.people.map(\.id), at: date).confirmedUsable
        #expect(try ledger.waterGap(people: h.people.count, personIDs: h.people.map(\.id), at: date).confirmedUsable == single)
        // The same physical container under a second record is refused.
        #expect(throws: SessionError.duplicate) {
            try ledger.confirm([InventoryItem(id: "jugs-copy", physicalID: "jugs", category: "water", quantity: .confirmed(4), unit: .usGallon,
                                              usableQuantity: .confirmed(4), accessible: .confirmed(true))], baseRevision: ledger.revision, at: date)
        }
        // A criterion cannot be assessed twice.
        let assessments = try HouseholdAssessment.assess(household: h, home: SampleHomes.ranch, inventory: ledger, at: date)
        let water = try #require(assessments.first { $0.criterionID == "water" })
        #expect(throws: SessionError.invalidCommand) { try ScoreCompiler.compile(rubric: rubric, assessments: assessments + [water]) }
    }

    @Test("Wording, names and language never change the number for identical evidence")
    func wordingInvariant() throws {
        let h = withFact(SampleHouseholds.oak, "smokeAlarms", PreparationFact(available: .confirmed(true), location: "Hallway", checkedAt: date, coverageReviewed: .confirmed(true)))
        var reworded = withFact(h, "smokeAlarms", PreparationFact(available: .confirmed(true), location: "Upstairs hall, by the stairs", checkedAt: date, notes: "Tested together", coverageReviewed: .confirmed(true)))
        for i in reworded.people.indices { reworded.people[i].alias = "Renamed \(i)" }
        for i in reworded.equipment.indices { reworded.equipment[i].label = "Relabelled device \(i)" }
        for i in reworded.contacts.indices { reworded.contacts[i].alias = "Contact \(i)" }
        reworded.preferredLocale = "es"
        let a = try score(h), b = try score(reworded)
        #expect(a.overall == b.overall && a.preparation == b.preparation && a.evidenceCoverage == b.evidenceCoverage && a.statuses == b.statuses && a.cap == b.cap)
    }

    @Test("A valid improvement changes only the criterion it applies to")
    func improvementIsLocal() throws {
        let h = SampleHouseholds.oak
        let before = try score(h, inventory: try water(1))
        let after = try score(h, inventory: try water(Double(h.people.count) * 3))
        #expect(before.statuses["water"] != after.statuses["water"])
        for id in rubric.criteria.map(\.id) where id != "water" {
            #expect(before.statuses[id] == after.statuses[id], "\(id) changed by a water record")
        }
        #expect(try #require(after.preparation) > (before.preparation ?? 0))
    }

    @Test("Prepare tasks and shopping check-offs cannot enlarge the score budget")
    func budgetIsFixed() throws {
        // Every criterion keeps its fixed weight whatever the Prepare list contains; a recorded purchase can only satisfy
        // an existing predicate, never add one.
        var h = SampleHouseholds.pine
        h.supplies.fireExtinguisher = .confirmed(false)
        let before = try score(h)
        var state = IntegratedAIState()
        let prices = try JSONDecoder().decode(ShoppingList.PriceTable.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/prices/tarrant-v1.json")))
        let item = try #require(try ShoppingList.build(household: h, inventory: state.inventory, prices: prices, at: date).first { $0.priceID == "fire-extinguisher" })
        try state.recordPurchase(item, household: &h, baseHouseholdRevision: h.revision, at: date) { _, _ in }
        let after = try score(h, inventory: state.inventory)
        #expect(Set(before.statuses.keys) == Set(after.statuses.keys))
        #expect(before.overall == after.overall, "the rubric has no extinguisher predicate; buying one adds no points")
    }
}
