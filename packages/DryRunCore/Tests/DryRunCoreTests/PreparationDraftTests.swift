import Testing
@testable import DryRunCore

@Suite("Preparation drafts preserve unrelated evidence")
struct PreparationDraftTests {
    @Test func recordingALocationOrContactPreservesCanonicalOwnership() {
        var original = SampleHouseholds.oak
        original.supplies.firstAidKit = .confirmed(true)
        original.supplies.fireExtinguisher = .confirmed(true)
        original.supplies.flashlights = .confirmed(3)
        original.preparedness = PreparednessRecord()
        var draft = original
        for key in ["firstAid", "extinguisher", "flashlight"] { draft.preparedness?.items[key] = .init(location: "Hall cabinet") }
        PreparationDraft.synchronizeSupplyAnswers(&draft, original: original)
        #expect(draft.supplies == original.supplies)
        #expect(!BaselinePreparedness.evaluate(household: draft).contains { $0.actionID == "prep.firstAid" || $0.actionID == "prep.flashlight" })
        let saved = draft
        draft.contacts.append(.init(id: "new", role: .other, alias: "Contact"))
        PreparationDraft.synchronizeSupplyAnswers(&draft, original: saved)
        #expect(draft.supplies == original.supplies)
    }
    @Test func explicitOwnershipCorrectionsAndUnknownsUpdateOnlyThatItem() {
        var original = SampleHouseholds.oak
        original.preparedness = .init(items: ["firstAid": .init(available: .confirmed(true)), "extinguisher": .init(available: .confirmed(true))])
        original.supplies.firstAidKit = .confirmed(true); original.supplies.fireExtinguisher = .confirmed(true)
        var draft = original
        draft.preparedness?.items["firstAid"]?.available = .unknown
        draft.preparedness?.items["extinguisher"]?.available = .confirmed(false)
        PreparationDraft.synchronizeSupplyAnswers(&draft, original: original)
        #expect(draft.supplies.firstAidKit.confirmedValue == nil)
        #expect(draft.supplies.fireExtinguisher.confirmedValue == false)
        #expect(draft.supplies.flashlights == original.supplies.flashlights)
    }
    @Test func selectedFlashlightAnswerRetainsActualPositiveCount() {
        var original = SampleHouseholds.oak
        original.preparedness = .init(); original.supplies.flashlights = .confirmed(4)
        var draft = original
        draft.preparedness?.items["flashlight"] = .init(available: .confirmed(true))
        PreparationDraft.synchronizeSupplyAnswers(&draft, original: original)
        #expect(draft.supplies.flashlights.confirmedValue == 4)
        let prior = draft; draft.preparedness?.items["flashlight"]?.available = .confirmed(false)
        PreparationDraft.synchronizeSupplyAnswers(&draft, original: prior)
        #expect(draft.supplies.flashlights.confirmedValue == 0)
    }
    @Test func comparisonReportsTheResolvedDeviceWhileAnotherSameActionRemains() throws {
        var input = SimFixtures.input(SampleHouseholds.oak, "freeze-power-loss")
        var second = input.household.equipment[0]; second.id = "second.device"; second.compatibleBackupIDs = []
        input.household.equipment.append(second)
        let baseline = try SimFixtures.engine.run(input)
        let first = try #require(baseline.recommendations.first { $0.actionID == "act.backup.confirm-medical-backup" && $0.subjectID != "equipment.second.device" })
        let comparison = try SimFixtures.engine.compare(input, applying: try #require(first.tryIntervention))
        #expect(comparison.modified.recommendations.contains { $0.actionID == first.actionID && $0.subjectID == "equipment.second.device" })
        #expect(comparison.diff.resolvedRecommendations.contains(first.id))
        #expect(!comparison.diff.resolvedRecommendations.contains("\(first.actionID)|equipment.second.device"))
    }
}
