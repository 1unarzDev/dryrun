import Foundation
import Testing
@testable import DryRunCore

@Suite("Offline nearby-resource plans from open tasks") struct ResourceSuggestionPlannerTests {
    let rubric = try! JSONDecoder().decode(RubricDefinition.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))

    func plans(_ household: HouseholdProfile, transport: String? = nil) -> [ResourceSearchPlan] {
        let tasks = PreparationTaskCatalog.build(household: household, home: SampleHomes.ranch, rubric: rubric, at: Date())
        return ResourceSuggestionPlanner.plans(tasks: tasks, gaps: [], transport: transport ?? HouseholdContextSnapshot(household).transport,
                                               limitedBudget: household.supplies.limitedBudget)
    }

    @Test func atMostThreeDistinctCategoriesEachTiedToARealTask() {
        let household = SampleHouseholds.oak
        let tasks = PreparationTaskCatalog.build(household: household, home: SampleHomes.ranch, rubric: rubric, at: Date())
        let result = plans(household)
        #expect(!result.isEmpty && result.count <= 3)
        #expect(Set(result.map(\.category)).count == result.count)
        #expect(result.allSatisfy { plan in tasks.contains { $0.id == plan.taskID } })
        #expect(result.allSatisfy { $0.cloudReturnPolicy == "local_only" && !$0.requiredEvidence.isEmpty && !$0.unknowns.isEmpty })
    }

    @Test func poweredMedicalEquipmentGetsASupplierPlanThatKeepsCompatibilityUnknown() throws {
        let plan = try #require(plans(SampleHouseholds.oak).first { $0.category == "equipmentSupplier" })
        #expect(plan.unknowns.contains("resource.unknown.compatibility"))
        #expect(plan.requiredEvidence == ["resource.evidence.manufacturer"])
    }

    @Test func aHouseholdWithoutACarIsNeverPlannedToDrive() {
        #expect(plans(SampleHouseholds.oak, transport: "noCar").allSatisfy { $0.travelMode != "driving" && $0.maximumDistanceKm <= 3 })
    }

    @Test func limitedBudgetFoodGoesToFoodAssistanceAndShortfallsComeFirst() throws {
        let task = PreparationTaskProposal(id: "t-food", actionID: "prep.food", criterionID: "food", subjectID: "household", why: "",
                                           evidenceIDs: ["household-needs"], completionPredicates: ["days"], editor: "supplies", dependencyIDs: [], priority: 2)
        let light = PreparationTaskProposal(id: "t-light", actionID: "prep.flashlight", criterionID: "essentials", subjectID: "household", why: "",
                                            evidenceIDs: ["household-needs"], completionPredicates: ["light"], editor: "supplies", dependencyIDs: [], priority: 0)
        let gap = try JSONDecoder().decode(SupplyGap.self, from: Data(#"{"category":"food","required":3,"confirmedUsable":1,"deficit":2,"unit":"day","unknown":false,"sourceIDs":["S64"]}"#.utf8))
        let result = ResourceSuggestionPlanner.plans(tasks: [light, task], gaps: [gap], transport: "car", limitedBudget: true)
        #expect(result.first?.category == "foodAssistance")
        #expect(result.first?.unknowns.contains("resource.unknown.eligibility") == true)
    }

    @Test func officialOnlyCategoriesNeverBecomeMapListings() {
        for category in ResourceSuggestionPlanner.officialOnly {
            #expect(ResourceSuggestionPlanner.mapQuery(category: category) == nil)
            #expect(!ResourceSuggestionPlanner.officialServiceTypes(category: category).isEmpty)
        }
        #expect(ResourceSuggestionPlanner.mapQuery(category: "hardware") == "hardware store")
    }
}
