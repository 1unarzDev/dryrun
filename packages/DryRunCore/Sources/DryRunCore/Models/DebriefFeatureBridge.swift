import Foundation

/// Native side of the gateway's `debrief` role: after a finished rehearsal, Beacon writes a short summary for this
/// household and may point at up to two of the rehearsal's own recommended tasks. It cannot add tasks, change their
/// order, score or completion; anything that does not name a supplied task is dropped here.
public enum DebriefFeatureBridge {
    public struct Output: Codable, Sendable, Equatable {
        public var summary: String
        public var focusTaskIDs: [String]
    }

    /// Host receipt of the finished rehearsal (D1, report-codex-served-debrief-resources-director-review): the family's
    /// committed choices and whether each was the recommended option, the events and the final service state, all
    /// computed by Core. `label`/`title` are the app's own localized text for authored keys, never model text.
    /// Bounded: at most 20 choices, 40 events, 20 routes.
    public struct RehearsalReceipt: Encodable, Sendable, Equatable {
        public struct Choice: Encodable, Sendable, Equatable {
            public var decisionID: String; public var simMinute: Int; public var optionID: String
            public var recommended: Bool; public var label: String?
        }
        public struct Event: Encodable, Sendable, Equatable {
            public var id: String; public var simMinute: Int; public var phaseID: String; public var severity: String; public var title: String?
        }
        public struct Route: Encodable, Sendable, Equatable {
            public var personID: String?; public var alternativeStatus: String; public var noRouteReason: String?
        }
        public var version = "dryrun.rehearsal-receipt/1"
        public var engineVersion: String
        public var variants: [String]
        public var choices: [Choice]
        /// Decisions the rehearsal presented that have no committed answer.
        public var unansweredDecisionIDs: [String]
        public var events: [Event]
        public var finalServices: [String: String]
        public var unmetRequirements: [String]
        public var unknowns: [String]
        public var routes: [Route]
        public var interventions: [String]

        public init(_ result: RehearsalResult, labels: [String: String] = [:]) {
            engineVersion = result.engineVersion
            variants = Array(result.input.variants.prefix(10))
            var choices: [Choice] = [], unanswered: [String] = []
            for decision in result.decisions {
                guard let chosen = result.input.choices[decision.id], let option = decision.options.first(where: { $0.id == chosen }) else {
                    unanswered.append(decision.id); continue
                }
                choices.append(Choice(decisionID: decision.id, simMinute: decision.simMinute, optionID: option.id,
                                      recommended: option.isRecommended, label: labels[option.labelKey]))
            }
            self.choices = Array(choices.prefix(20)); unansweredDecisionIDs = Array(unanswered.prefix(20))
            events = result.events.prefix(40).map { Event(id: $0.id, simMinute: $0.simMinute, phaseID: $0.phaseID, severity: $0.severity.rawValue, title: labels[$0.id] ?? labels[$0.titleKey]) }
            let last = result.snapshots.last
            finalServices = (last?.services ?? [:]).mapValues(\.rawValue)
            unmetRequirements = Array((last?.unmetRequirements ?? []).prefix(30))
            unknowns = Array(result.unknowns.prefix(30))
            routes = result.routes.prefix(20).map { Route(personID: $0.request.personID, alternativeStatus: $0.alternativeStatus.rawValue, noRouteReason: $0.noRouteReason?.rawValue) }
            interventions = Array(result.input.interventions.map(\.actionID).prefix(20))
        }
    }

    public struct Accepted: Sendable, Equatable {
        public var summary: String
        /// Recommendation action IDs, in Beacon's order, each one the rehearsal itself recommended.
        public var focusActionIDs: [String]
    }

    /// `readable` gives each recommendation's family-facing title and reason in the app's language (the model never
    /// sees localization keys); missing entries fall back to the reason key.
    /// `rehearsal` adds the host receipt of the finished rehearsal (committed choices, events, final state); `labels`
    /// maps its authored keys (event IDs or title keys, option label keys) to the app's localized text.
    public static func request(requestID: String, scenarioID: String, recommendations: [Recommendation], readable: [String: String] = [:],
                               rehearsal: RehearsalResult? = nil, labels: [String: String] = [:],
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
        request.context.debrief = .init(scenarioID: scenarioID, rehearsal: rehearsal.map { RehearsalReceipt($0, labels: labels) })
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
