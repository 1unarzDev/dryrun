import Foundation

/// Native side of the gateway's resource-strategy role (`POST /v1/features`, role `resources`): Gemini proposes at most
/// three search plans for the household's open, resource-relevant tasks. Only anonymous needs, tasks and gaps are sent:
/// never the address, coordinates or map listings. Returned plans are accepted only through `ResourceStrategyRefresh`
/// (allowed categories, real task IDs, no driving without a car, local-only listings), so they share the offline path.
public enum ResourceStrategyBridge {
    public struct Context: Encodable, Sendable {
        public var household: HouseholdContextSnapshot
        public var tasks: [PreparationTaskProposal]
        public var gaps: [SupplyGap]
        public var allowedActionIDs: [String]
        public var allowedCriterionIDs: [String] = []
        public var locale: String?
        public var privateContext: AuthorizedAIContext?
        public var contextBinding: AuthorizedAIContext.Binding?
    }
    public struct Request: Encodable, Sendable {
        public var contractVersion = "dryrun.ai/1"
        public var requestID: String
        public var synthetic = true
        public var role = "resources"
        public var context: Context
        public var images: [String] = []
        public var providerConsent: [String]?
    }
    public struct Response: Decodable, Sendable {
        public var status: String
        public var requestID: String?
        public var contextBinding: AuthorizedAIContext.Binding?
        public var proposal: Proposal?
        public struct Proposal: Decodable, Sendable {
            public var searchPlans: [ResourceSearchPlan]
            public var officialRecommendations: [OfficialRecommendation]?
            public var question: String?
        }
        public struct OfficialRecommendation: Decodable, Sendable { public var resourceID: String; public var taskID: String; public var reason: String }
    }

    /// Tasks with a resource side (the same reviewed table as the offline planner), shaped to the gateway's strict
    /// task schema. Shortfalls lead, at most 30.
    public static func resourceTasks(_ tasks: [PreparationTaskProposal], limitedBudget: Bool) -> [PreparationTaskProposal] {
        tasks.filter { task in
            let action = task.actionID.hasPrefix("prep.") ? String(task.actionID.dropFirst(5)) : task.actionID
            return ResourceSuggestionPlanner.rule(action: action, limitedBudget: limitedBudget) != nil
                && !task.evidenceIDs.isEmpty && !task.completionPredicates.isEmpty
        }.prefix(30).map { task in
            var t = task
            t.dependencyIDs = Array(t.dependencyIDs.prefix(10)); t.evidenceIDs = Array(t.evidenceIDs.prefix(10))
            t.completionPredicates = Array(t.completionPredicates.prefix(8))
            return t
        }
    }

    public static func request(requestID: String, household: HouseholdProfile, tasks: [PreparationTaskProposal], gaps: [SupplyGap],
                               at date: Date = Date()) -> Request {
        let relevant = resourceTasks(tasks, limitedBudget: household.supplies.limitedBudget)
        return Request(requestID: requestID, context: Context(household: HouseholdContextSnapshot(household, at: date), tasks: relevant,
                                                               gaps: Array(gaps.prefix(30)), allowedActionIDs: relevant.map(\.actionID)))
    }

    /// Private planning receives the complete authorized snapshot; downstream public discovery must
    /// independently derive its small public query without forwarding this private context.
    public static func authorizedRequest(requestID: String, household: HouseholdProfile, home: HomeModel?,
                                         tasks: [PreparationTaskProposal], gaps: [SupplyGap], state: IntegratedAIState,
                                         places: [SavedPlace], scopeSessionID: String, locale: String,
                                         currentScorecard: PreparednessScorecard? = nil, at date: Date = Date()) throws -> Request {
        guard household.isFictional else { throw SessionError.invalidCommand }
        var request = request(requestID: requestID, household: household, tasks: tasks, gaps: gaps, at: date)
        request.context.locale = locale
        request.context.privateContext = try AuthorizedAIContext(household: household, home: home, state: state,
            places: places, tasks: tasks, sessionID: scopeSessionID, cloudPlanningConsent: true, currentScorecard: currentScorecard)
        request.context.contextBinding = request.context.privateContext?.binding
        request.providerConsent = ["codex", "gemini", "groq"]
        return request
    }

    /// Gemini chooses which open tasks to search for, how to travel and how far; the words the family reads stay the
    /// reviewed, localized ones. Each plan takes its task's reviewed purpose, unknowns and evidence keys; a plan whose
    /// category is not the reviewed one for its task (or whose task has no resource side) is dropped.
    public static func reviewed(_ plans: [ResourceSearchPlan], tasks: [PreparationTaskProposal], limitedBudget: Bool) -> [ResourceSearchPlan] {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return plans.compactMap { plan in
            guard let task = byID[plan.taskID] else { return nil }
            let action = task.actionID.hasPrefix("prep.") ? String(task.actionID.dropFirst(5)) : task.actionID
            guard let rule = ResourceSuggestionPlanner.rule(action: action, limitedBudget: limitedBudget), rule.category == plan.category else { return nil }
            var p = plan
            p.purpose = rule.purpose; p.unknowns = rule.unknowns; p.requiredEvidence = rule.evidence
            return p
        }
    }

    /// The normalized refresh key for these inputs (unrelated edits do not change it; quantity/prerequisite changes do).
    public static func key(household: HouseholdProfile, home: HomeModel?, tasks: [PreparationTaskProposal], gaps: [SupplyGap],
                           at date: Date = Date()) throws -> ResourceStrategyKey {
        try ResourceStrategyKey.normalized(gaps: gaps, tasks: resourceTasks(tasks, limitedBudget: household.supplies.limitedBudget),
                                           transport: HouseholdContextSnapshot(household, at: date).transport,
                                           limitedBudget: household.supplies.limitedBudget, regionID: household.regionID,
                                           dependencies: HousingPlanning.strategyDependencies(household: household, home: home, at: date))
    }
}
