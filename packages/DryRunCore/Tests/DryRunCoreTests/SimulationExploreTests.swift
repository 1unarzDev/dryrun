import Foundation
import Testing
@testable import DryRunCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["DRYRUN_EXPLORE"] != nil))
func simulationExploreDump() throws {
    for h in SampleHouseholds.all {
        for s in SimFixtures.scenarioIDs {
            let r = try SimFixtures.run(h, s)
            print("=== \(h.id) \(s)")
            for e in r.events { print("  \(e.simMinute) \(e.id) [\(e.severity)] \(e.templateValues)") }
            print("  unmet:", Set(r.snapshots.flatMap(\.unmetRequirements)).sorted())
            print("  recs:", r.recommendations.map { "\($0.tier.rawValue):\($0.actionID)" })
            print("  unknowns:", r.unknowns)
        }
    }
}
