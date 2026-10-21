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

    @Test func preparationRequestsStillOmitTheDebriefField() throws {
        let request = try PreparationFeatureBridge.request(requestID: "p-1", household: SampleHouseholds.oak, home: SampleHomes.ranch,
                                                           inventory: InventoryLedger(), rubric: rubric)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("\"debrief\""))
    }
}
