import Foundation
import Testing
@testable import DryRunCore

enum SimFixtures {
    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }   // Tests/DryRunCoreTests/<file> -> packages/DryRunCore -> repo
        return u.deletingLastPathComponent()
    }()
    static let scenariosDir = repoRoot.appendingPathComponent("content/scenarios")
    static let library: ScenarioLibrary = try! ScenarioLibrary.load(from: scenariosDir)
    static let engine = RehearsalEngine(library: library, planner: EgressPlanner())
    static let home = SampleHomes.ranch

    static func input(_ h: HouseholdProfile, _ scenario: String, home: HomeModel = SampleHomes.ranch, choices: [String: String] = [:],
                      variants: [String] = [], interventions: [Intervention] = [], seed: UInt64 = 7) -> RehearsalInput {
        let s = library.scenario(scenario)!
        return RehearsalInput(household: h, home: home, scenarioID: scenario, scenarioVersion: s.version, contentVersion: "2026.10.0",
                              seed: seed, choices: choices, interventions: interventions, variants: variants)
    }

    static func run(_ h: HouseholdProfile, _ scenario: String, choices: [String: String] = [:], variants: [String] = [],
                    interventions: [Intervention] = [], home: HomeModel = SampleHomes.ranch) throws -> RehearsalResult {
        try engine.run(input(h, scenario, home: home, choices: choices, variants: variants, interventions: interventions))
    }

    static let scenarioIDs = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]
}
