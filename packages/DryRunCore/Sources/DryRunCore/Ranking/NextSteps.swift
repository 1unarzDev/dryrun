import Foundation

/// One preparation on the "Next steps" screen, merged across every rehearsed scenario that raised it.
public struct NextStep: Sendable, Hashable, Identifiable {
    public var id: String { recommendation.id }
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
    public static func summarize(_ results: [RehearsalResult], household: HouseholdProfile, home: HomeModel? = nil, savedPlaces: [SavedPlace] = []) -> NextStepsSummary {
        var best: [String: (rec: Recommendation, scenario: String)] = [:]
        var scenarios: [String: Set<String>] = [:]
        for r in results {
            let scenario = r.input.scenarioID
            for rec in r.recommendations {
                scenarios[rec.id, default: []].insert(scenario)
                if let current = best[rec.id] {
                    // Keep the highest-priority instance; ties go to the scenario listed first, so the result
                    // does not depend on the order results were computed in.
                    let better = rec.tier < current.rec.tier
                        || (rec.tier == current.rec.tier && PlanBuilder.order(scenario) < PlanBuilder.order(current.scenario))
                    if better { best[rec.id] = (rec, scenario) }
                } else {
                    best[rec.id] = (rec, scenario)
                }
            }
        }
        for rec in BaselinePreparedness.evaluate(household: household, home: home, savedPlaces: savedPlaces) {
            best[rec.id] = (rec, rec.scenarioIDs.first ?? "")
            scenarios[rec.id] = Set(rec.scenarioIDs)
        }
        // One real preparation can explain several exercise gaps. Retain the exercise intervention
        // and source scenario while keeping the direct factual editor and household wording.
        let equivalents = ["act.backup.confirm-medical-backup": "prep.medicalBackup", "act.medical.document-runtime": "prep.medicalBackup",
                           "act.refrigeration.cooler-plan": "prep.coldStorage", "act.water.store-3day": "prep.water",
                           "act.fire.meeting-point": "prep.nearMeetup", "act.fire.smoke-alarms": "prep.smokeAlarms",
                           "act.assist.assign-helper": "prep.helper"]
        for key in best.keys.sorted() {
            guard let exercise = best[key], let action = equivalents[exercise.rec.actionID] else { continue }
            let canonical = exercise.rec.subjectID.map { "\(action)|\($0)" } ?? action
            guard var baseline = best[canonical] else { continue }
            baseline.rec.tier = min(baseline.rec.tier, exercise.rec.tier)
            baseline.rec.matchedFactIDs = Array(Set(baseline.rec.matchedFactIDs + exercise.rec.matchedFactIDs)).sorted()
            baseline.rec.sourceIDs = Array(Set(baseline.rec.sourceIDs + exercise.rec.sourceIDs)).sorted()
            if baseline.rec.tryIntervention == nil, exercise.rec.tryIntervention != nil {
                baseline.rec.tryIntervention = exercise.rec.tryIntervention
                baseline.rec.modeledEffectKey = exercise.rec.modeledEffectKey
                baseline.scenario = exercise.scenario
            }
            scenarios[canonical, default: []].formUnion(scenarios[key] ?? [])
            best[canonical] = baseline
            best.removeValue(forKey: key)
        }
        let steps = best.map { id, value in
            NextStep(recommendation: value.rec, sourceScenarioID: value.scenario,
                     scenarioIDs: (scenarios[id] ?? []).sorted { PlanBuilder.order($0) < PlanBuilder.order($1) },
                     completedAt: household.completedPreparations.first { PreparationCompletion.isValid($0, for: value.rec, household: household, home: home) }?.completedAt)
        }
        .sorted {
            ($0.recommendation.tier, RecommendationRanker.effortRank($0.recommendation.effort), -$0.scenarioIDs.count, $0.id) < ($1.recommendation.tier, RecommendationRanker.effortRank($1.recommendation.effort), -$1.scenarioIDs.count, $1.id)
        }
        return NextStepsSummary(
            toDo: steps.filter { $0.completedAt == nil },
            completed: steps.filter { $0.completedAt != nil },
            unknownFacts: Array(Set(results.flatMap(\.unknowns))).sorted(),
            scenarioIDs: results.map(\.input.scenarioID).sorted { PlanBuilder.order($0) < PlanBuilder.order($1) })
    }
}

extension Recommendation {
    /// Type labels follow the selected language; personal names and custom model names remain unchanged.
    public func localizedTemplateValues(household: HouseholdProfile?, localizer: Localizer) -> [String: String] {
        guard let household else { return templateValues }
        var values = templateValues
        if let subjectID, subjectID.hasPrefix("equipment."), let equipment = household.equipment.first(where: { "equipment.\($0.id)" == subjectID }) {
            values["device"] = equipment.localizedLabel(localizer)
        }
        if let subjectID, subjectID.hasPrefix("person."), let person = household.people.first(where: { "person.\($0.id)" == subjectID }) {
            values["person"] = person.alias.isEmpty ? localizer(person.isSelf == true ? "family.you" : "ui.person") : person.alias
        }
        if let subjectID, subjectID.hasPrefix("backup."), let backup = household.backupPower.first(where: { "backup.\($0.id)" == subjectID }) {
            values["backup"] = backup.label.isEmpty ? localizer("enum.\(backup.kind.rawValue)") : backup.label
        }
        return values
    }
}
