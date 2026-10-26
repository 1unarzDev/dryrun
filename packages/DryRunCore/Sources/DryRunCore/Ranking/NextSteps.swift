import Foundation

/// One preparation on the "Next steps" screen, merged across every rehearsed scenario that raised it.
public struct NextStep: Sendable, Hashable, Identifiable {
    public var id: String { recommendation.actionID }
    /// The highest-priority instance (lowest tier). Its event IDs and "Try this change" intervention belong to
    /// `sourceScenarioID`, so a comparison must be run against that scenario.
    public var recommendation: Recommendation
    public var sourceScenarioID: String
    /// Every scenario in which this preparation came up, in the order the planner lists scenarios.
    public var scenarioIDs: [String]
    /// Set when the household marked it completed (a real-world record, never inferred).
    public var completedAt: Date?
}

/// The household's preparations across scenarios: what to do, what is done, and which facts are still unknown.
/// Ordered by the ranker's tier, then by how many scenarios raised it. There is no score.
public struct NextStepsSummary: Sendable, Hashable {
    public var toDo: [NextStep]
    public var completed: [NextStep]
    /// Household facts the rehearsals could not confirm (IDs as in `RehearsalResult.unknowns`), de-duplicated.
    public var unknownFacts: [String]
    /// Scenarios these steps were computed from.
    public var scenarioIDs: [String]
}

public enum NextSteps {
    public static func summarize(_ results: [RehearsalResult], household: HouseholdProfile) -> NextStepsSummary {
        var best: [String: (rec: Recommendation, scenario: String)] = [:]
        var scenarios: [String: Set<String>] = [:]
        for r in results {
            let scenario = r.input.scenarioID
            for rec in r.recommendations {
                scenarios[rec.actionID, default: []].insert(scenario)
                if let current = best[rec.actionID] {
                    // Keep the highest-priority instance; ties go to the scenario listed first, so the result
                    // does not depend on the order results were computed in.
                    let better = rec.tier < current.rec.tier
                        || (rec.tier == current.rec.tier && PlanBuilder.order(scenario) < PlanBuilder.order(current.scenario))
                    if better { best[rec.actionID] = (rec, scenario) }
                } else {
                    best[rec.actionID] = (rec, scenario)
                }
            }
        }
        let completedAt = Dictionary(household.completedPreparations.map { ($0.actionID, $0.completedAt) },
                                     uniquingKeysWith: { a, _ in a })
        let steps = best.map { id, value in
            NextStep(recommendation: value.rec, sourceScenarioID: value.scenario,
                     scenarioIDs: (scenarios[id] ?? []).sorted { PlanBuilder.order($0) < PlanBuilder.order($1) },
                     completedAt: completedAt[id])
        }
        .sorted {
            ($0.recommendation.tier, -$0.scenarioIDs.count, $0.id) < ($1.recommendation.tier, -$1.scenarioIDs.count, $1.id)
        }
        return NextStepsSummary(
            toDo: steps.filter { $0.completedAt == nil },
            completed: steps.filter { $0.completedAt != nil },
            unknownFacts: Array(Set(results.flatMap(\.unknowns))).sorted(),
            scenarioIDs: results.map(\.input.scenarioID).sorted { PlanBuilder.order($0) < PlanBuilder.order($1) })
    }
}
