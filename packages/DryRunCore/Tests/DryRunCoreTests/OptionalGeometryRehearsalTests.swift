import Foundation
import Testing
@testable import DryRunCore

@Suite("Rehearsal without a home layout")
struct OptionalGeometryRehearsalTests {
    private func input(_ scenarioID: String) -> RehearsalInput {
        var input = SimFixtures.input(SampleHouseholds.oak, "\(scenarioID)")
        input.home = nil
        return input
    }

    @Test("All six hazards retain deterministic decisions and household preparations without spatial claims")
    func allHazards() throws {
        for scenarioID in SimFixtures.scenarioIDs {
            let original = input(scenarioID)
            let first = try SimFixtures.engine.run(original)
            let second = try SimFixtures.engine.run(original)
            #expect(first == second, "\(scenarioID)")
            #expect(try DryRunJSON.encoder().encode(first) == DryRunJSON.encoder().encode(second))
            #expect(first.input == original && first.input.home == nil)
            #expect(!first.events.isEmpty && !first.decisions.isEmpty, "\(scenarioID)")
            #expect(!first.recommendations.isEmpty, "\(scenarioID)")
            #expect(first.routes.isEmpty, "\(scenarioID)")
            #expect(first.snapshots.allSatisfy { $0.spatialState == nil }, "\(scenarioID)")
            let spatial = ["home-fire", "flash-flood", "tornado"].contains(scenarioID)
            #expect(first.unknowns.contains("home") == spatial, "\(scenarioID)")
        }
    }

    @Test("A family can answer every decision and finish each no-layout exercise")
    func interactiveJourney() throws {
        for scenarioID in SimFixtures.scenarioIDs {
            var recorded = input(scenarioID)
            var cursor = RehearsalCursor(result: try SimFixtures.engine.run(recorded))
            var answered = Set<String>()
            while !cursor.isFinished {
                cursor.advanceUntilDecisionOrEnd()
                guard let decision = cursor.pendingDecision else { continue }
                #expect(answered.insert(decision.id).inserted)
                let choice = try #require(decision.options.first)
                recorded.choices[decision.id] = choice.id
                cursor.replace(result: try SimFixtures.engine.run(recorded))
            }
            #expect(answered.count == cursor.result.decisions.count, "\(scenarioID)")
            #expect(cursor.result.input.home == nil && cursor.result.routes.isEmpty)
        }
    }

    @Test("Household-only comparisons work without creating a layout or editing real facts")
    func comparison() throws {
        let original = input("freeze-power-loss")
        let comparison = try SimFixtures.engine.compare(original, applying: Intervention(actionID: "act.water.store-3day"))
        #expect(comparison.baseline.input.home == nil && comparison.modified.input.home == nil)
        #expect(comparison.modified.input.household == original.household)
        #expect(comparison.diff.resolvedRequirements.contains("req.water"))
        #expect(!comparison.diff.removedEventIDs.isEmpty)
        #expect(comparison.baseline.routes.isEmpty && comparison.modified.routes.isEmpty)
    }

    @Test("A hypothetical shelter cannot supply missing geometry or establish a shelter")
    func shelterCannotFabricateHome() throws {
        let original = input("tornado")
        let comparison = try SimFixtures.engine.compare(original, applying: Intervention(actionID: "act.tornado.choose-shelter"))
        #expect(comparison.modified.input.home == nil)
        #expect(comparison.modified.routes.isEmpty)
        #expect(!comparison.diff.resolvedRequirements.contains("req.shelter"))
        #expect(comparison.modified.events.contains { $0.id == "evt.tornado.shelter-not-chosen" })
        #expect(!comparison.modified.events.contains { $0.id == "evt.tornado.shelter-preselected" })
    }

    @Test("Absent geometry is neither evidence of stairs nor evidence of their absence")
    func applicability() {
        for predicate in ["hasStairs", "!hasStairs"] {
            #expect(!Applicability.holds([predicate], household: SampleHouseholds.oak, home: nil, variants: []))
        }
        #expect(Applicability.holds(["!hasStairs"], household: SampleHouseholds.oak, home: SampleHomes.ranch, variants: []))
        #expect(Applicability.holds(["hasEssentialEquipment"], household: SampleHouseholds.oak, home: nil, variants: []))
    }

    @Test("Missing and present layouts round-trip while corrupt present layouts still fail")
    func codable() throws {
        let noLayout = input("home-fire")
        let encoder = DryRunJSON.encoder(), decoder = DryRunJSON.decoder()
        #expect(try decoder.decode(RehearsalInput.self, from: encoder.encode(noLayout)) == noLayout)
        let legacy = SimFixtures.input(SampleHouseholds.oak, "home-fire")
        #expect(try decoder.decode(RehearsalInput.self, from: encoder.encode(legacy)) == legacy)
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "home")
        #expect(try decoder.decode(RehearsalInput.self, from: JSONSerialization.data(withJSONObject: object)).home == nil)
        object["home"] = ["spaces": "corrupt"]
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try decoder.decode(RehearsalInput.self, from: corrupted) }
    }
}
