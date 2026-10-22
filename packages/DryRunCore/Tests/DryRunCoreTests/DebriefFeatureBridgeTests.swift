import Foundation
import Testing
@testable import DryRunCore

struct DebriefFeatureBridgeTests {
    let rubric = try! DryRunJSON.decoder().decode(RubricDefinition.self,
        from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))

    @Test func requestCarriesOnlyThisRehearsalsRecommendations() throws {
        let oak = SampleHouseholds.oak
        let result = try SimFixtures.run(oak, "freeze-power-loss")
        let request = try DebriefFeatureBridge.request(requestID: "d-1", scenarioID: "freeze-power-loss", recommendations: result.recommendations,
                                                       household: oak, home: SampleHomes.ranch, inventory: InventoryLedger(), rubric: rubric)
        #expect(request.role == "debrief")
        #expect(request.context.debrief?.scenarioID == "freeze-power-loss")
        #expect(!request.context.tasks.isEmpty)
        #expect(request.context.tasks.map(\.id) == Array(result.recommendations.map(\.id).prefix(8)), "the rehearsal's own order")
        #expect(request.context.tasks.count <= 8)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"debrief\""))
    }

    @Test func acceptKeepsOnlySuppliedTasksAndBoundsTheSummary() throws {
        let oak = SampleHouseholds.oak
        let result = try SimFixtures.run(oak, "freeze-power-loss")
        let request = try DebriefFeatureBridge.request(requestID: "d-2", scenarioID: "freeze-power-loss", recommendations: result.recommendations,
                                                       household: oak, home: SampleHomes.ranch, inventory: InventoryLedger(), rubric: rubric)
        let first = request.context.tasks[0]
        let accepted = DebriefFeatureBridge.accept(.init(summary: "  Confirm the oxygen backup first.  ", focusTaskIDs: ["invented", first.id, first.id]), request: request)
        #expect(accepted?.summary == "Confirm the oxygen backup first.")
        #expect(accepted?.focusActionIDs == [first.actionID])
        #expect(DebriefFeatureBridge.accept(.init(summary: "   ", focusTaskIDs: []), request: request) == nil)
        #expect(DebriefFeatureBridge.accept(.init(summary: String(repeating: "a", count: 601), focusTaskIDs: []), request: request) == nil)
    }

    /// D1: the debrief can ground "what happened" in the family's committed choices, not only in retrieved records.
    @Test func requestCarriesTheHostRehearsalReceiptOfCommittedChoices() throws {
        let oak = SampleHouseholds.oak
        let plain = try SimFixtures.run(oak, "flash-flood")
        let decision = try #require(plain.decisions.first)
        let notRecommended = try #require(decision.options.first { !$0.isRecommended } ?? decision.options.first)
        let result = try SimFixtures.run(oak, "flash-flood", choices: [decision.id: notRecommended.id])
        let labels = [notRecommended.labelKey: "Synthetic localized option label"]
        let request = try DebriefFeatureBridge.request(requestID: "d-3", scenarioID: "flash-flood", recommendations: result.recommendations,
                                                       rehearsal: result, labels: labels, household: oak, home: SampleHomes.ranch,
                                                       inventory: InventoryLedger(), rubric: rubric)
        let receipt = try #require(request.context.debrief?.rehearsal)
        #expect(receipt.version == "dryrun.rehearsal-receipt/1")
        #expect(receipt.choices.first?.decisionID == decision.id)
        #expect(receipt.choices.first?.optionID == notRecommended.id)
        #expect(receipt.choices.first?.recommended == notRecommended.isRecommended)
        #expect(receipt.choices.first?.label == "Synthetic localized option label")
        #expect(Set(receipt.unansweredDecisionIDs).isDisjoint(with: receipt.choices.map(\.decisionID)))
        #expect(receipt.events.count == min(40, result.events.count))
        #expect(receipt.finalServices == (result.snapshots.last?.services ?? [:]).mapValues(\.rawValue))
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("rehearsal-receipt"))
        // Without a result the field is absent, as before.
        let bare = try DebriefFeatureBridge.request(requestID: "d-4", scenarioID: "flash-flood", recommendations: result.recommendations,
                                                    household: oak, home: SampleHomes.ranch, inventory: InventoryLedger(), rubric: rubric)
        #expect(bare.context.debrief?.rehearsal == nil)
    }

    @Test func preparationRequestsStillOmitTheDebriefField() throws {
        let request = try PreparationFeatureBridge.request(requestID: "p-1", household: SampleHouseholds.oak, home: SampleHomes.ranch,
                                                           inventory: InventoryLedger(), rubric: rubric)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("\"debrief\""))
    }
}
