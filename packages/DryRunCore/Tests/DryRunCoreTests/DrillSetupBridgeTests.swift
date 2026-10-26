import Foundation
import Testing
@testable import DryRunCore

struct DrillSetupBridgeTests {
    let rubric = try! DryRunJSON.decoder().decode(RubricDefinition.self,
        from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))

    @Test func offersOriginsOnlyForFireAndBoundedStartingRooms() throws {
        let oak = SampleHouseholds.oak, ranch = SampleHomes.ranch
        let fire = try DrillSetupBridge.request(requestID: "s-1", scenarioID: "home-fire", readableRoom: { $0 }, household: oak, home: ranch,
                                                inventory: InventoryLedger(), rubric: rubric)
        #expect(fire.role == "drillSetup")
        #expect(fire.context.tasks.contains { $0.id.hasPrefix("origin:") })
        #expect(fire.context.tasks.count <= 30)
        #expect(!fire.context.tasks.contains { t in oak.people.contains { !$0.alias.isEmpty && t.why.contains($0.alias) } }, "no names in candidates")
        let tornado = try DrillSetupBridge.request(requestID: "s-2", scenarioID: "tornado", readableRoom: { $0 }, household: oak, home: ranch,
                                                   inventory: InventoryLedger(), rubric: rubric)
        #expect(!tornado.context.tasks.contains { $0.id.hasPrefix("origin:") })
        #expect(tornado.context.tasks.allSatisfy { $0.id.hasPrefix("start:") })
    }

    @Test func acceptKeepsOneOriginAndOneStartPerPersonFromOfferedChoices() throws {
        let oak = SampleHouseholds.oak, ranch = SampleHomes.ranch
        let request = try DrillSetupBridge.request(requestID: "s-3", scenarioID: "home-fire", readableRoom: { $0 }, household: oak, home: ranch,
                                                   inventory: InventoryLedger(), rubric: rubric)
        let starts = request.context.tasks.filter { $0.id.hasPrefix("start:p-oak-4:") }.map(\.id)
        let output = DrillSetupBridge.Output(choiceTaskIDs: ["origin:sp-kitchen", "origin:sp-living", starts[0], starts.last!, "start:invented:sp-bed1"],
                                             reason: "Grandpa starts far from the back door while the kitchen burns.")
        let accepted = try #require(DrillSetupBridge.accept(output, request: request, home: ranch, household: oak))
        #expect(accepted.originSpaceID == "sp-kitchen")
        #expect(accepted.startingSpaceIDs.count == 1)
        #expect(accepted.startingSpaceIDs["p-oak-4"] == String(starts[0].split(separator: ":")[2]))
        #expect(DrillSetupBridge.accept(.init(choiceTaskIDs: ["origin:nowhere"], reason: "x"), request: request, home: ranch, household: oak) == nil)
    }
}
