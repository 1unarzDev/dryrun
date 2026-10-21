import Foundation

/// Native side of the gateway's `debrief` role: after a finished rehearsal, Beacon writes a short summary for this
/// household and may point at up to two of the rehearsal's own recommended tasks. It cannot add tasks, change their
/// order, score or completion; anything that does not name a supplied task is dropped here.
public enum DebriefFeatureBridge {
    public struct Output: Codable, Sendable, Equatable {
        public var summary: String
        public var focusTaskIDs: [String]
    }

    public struct Accepted: Sendable, Equatable {
        public var summary: String
        /// Recommendation action IDs, in Beacon's order, each one the rehearsal itself recommended.
        public var focusActionIDs: [String]
    }

    /// `readable` gives each recommendation's family-facing title and reason in the app's language (the model never
    /// sees localization keys); missing entries fall back to the reason key.
    public static func request(requestID: String, scenarioID: String, recommendations: [Recommendation], readable: [String: String] = [:],
                               household: HouseholdProfile, home: HomeModel?, inventory: InventoryLedger, rubric: RubricDefinition,
                               at date: Date = Date(), state: IntegratedAIState? = nil, places: [SavedPlace] = [],
                               scopeSessionID: String? = nil, locale: String? = nil, currentScorecard: PreparednessScorecard? = nil) throws -> PreparationFeatureBridge.Request {
        var request = try PreparationFeatureBridge.request(requestID: requestID, household: household, home: home,
                                                           inventory: inventory, rubric: rubric, at: date, state: state,
                                                           places: places, scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentScorecard)
        let fallbackCriterion = rubric.criteria.first?.id ?? "device"
        var seen = Set<String>()
        // The rehearsal's own recommendations, in its order (its ranking is Core's and is not changed).
        let tasks = recommendations.filter { seen.insert($0.id).inserted }.prefix(8).map { rec in
            let catalogMatch = request.context.taskCatalog.first { $0.subjectID == (rec.subjectID ?? "household") }
            return PreparationTaskProposal(id: rec.id, actionID: rec.actionID, criterionID: catalogMatch?.criterionID ?? fallbackCriterion,
                                           subjectID: rec.subjectID ?? "household", why: readable[rec.id] ?? rec.whyKey,
                                           evidenceIDs: ["household-needs"], completionPredicates: [], editor: "supplies",
                                           dependencyIDs: rec.matchedFactIDs, priority: min(3, max(0, rec.tier.rawValue - 1)))
        }
        request.role = "debrief"
        request.context.debrief = .init(scenarioID: scenarioID)
        request.context.tasks = Array(tasks)
        return request
    }

    public static func accept(_ output: Output, request: PreparationFeatureBridge.Request) -> Accepted? {
        let summary = output.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 600 else { return nil }
        let byID = Dictionary(request.context.tasks.map { ($0.id, $0.actionID) }, uniquingKeysWith: { a, _ in a })
        var actions: [String] = []
        for id in output.focusTaskIDs.prefix(2) { if let action = byID[id], !actions.contains(action) { actions.append(action) } }
        return Accepted(summary: summary, focusActionIDs: actions)
    }
}
