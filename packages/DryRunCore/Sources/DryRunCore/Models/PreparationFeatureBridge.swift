import Foundation

/// Native side of the gateway's `/v1/features` role `preparation` (services/ai-orchestrator/src/features.ts).
/// Builds the same minimized context the macOS host builds (DryRunHost), and accepts the model's answer only where it
/// names a preparation this household's own Prepare list already contains. The model may reorder within a priority
/// tier and explain; it never adds a scored item, changes a tier, closes a task or decides a fact. Nothing here sends
/// data; the app's transport does, and only for fictional households.
public enum PreparationFeatureBridge {
    public struct Context: Encodable, Sendable {
        /// Set only for the `debrief` role: which rehearsal just finished and, when supplied, the host receipt of what
        /// the family actually committed in it (DebriefFeatureBridge.RehearsalReceipt).
        public struct Debrief: Encodable, Sendable {
            public var scenarioID: String
            public var rehearsal: DebriefFeatureBridge.RehearsalReceipt?
            public init(scenarioID: String, rehearsal: DebriefFeatureBridge.RehearsalReceipt? = nil) { self.scenarioID = scenarioID; self.rehearsal = rehearsal }
        }
        public var debrief: Debrief?
        public var household: HouseholdContextSnapshot
        public var tasks: [PreparationTaskProposal] = []
        public var gaps: [SupplyGap]
        public var taskCatalog: [PreparationTaskProposal]
        public var allowedActionIDs: [String]
        public var allowedCriterionIDs: [String]
        public var rubric: RubricDefinition
        public var scene: HomeSceneContext?
        public var locale: String?
        public var privateContext: AuthorizedAIContext?
        public var contextBinding: AuthorizedAIContext.Binding?
    }

    public struct Request: Encodable, Sendable {
        public var contractVersion = DirectorGatewayBridge.contractVersion
        public var requestID: String
        public var synthetic = true
        public var role = "preparation"
        /// Providers the gateway may use, in order; nil leaves the configured gateway provider default.
        public var providerConsent: [String]?
        public var context: Context
    }

    public static func request(requestID: String, household: HouseholdProfile, home: HomeModel?, inventory: InventoryLedger,
                               rubric: RubricDefinition, at date: Date = Date(), state: IntegratedAIState? = nil,
                               places: [SavedPlace] = [], scopeSessionID: String? = nil, locale: String? = nil, currentScorecard: PreparednessScorecard? = nil) throws -> Request {
        guard household.isFictional else { throw SessionError.invalidCommand }
        let catalog = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: date)
        var context = Context(
            debrief: nil,
            household: HouseholdContextSnapshot(household, inventory: inventory, at: date),
            gaps: try inventory.preparationGaps(personIDs: household.people.map(\.id), at: date),
            taskCatalog: catalog,
            allowedActionIDs: BaselinePreparedness.evaluate(household: household, home: home, referenceDate: date).map(\.actionID),
            allowedCriterionIDs: rubric.criteria.map(\.id), rubric: rubric,
            scene: home.map { HomeSceneContext($0, household: household) }, locale: locale ?? household.preferredLocale,
            privateContext: try scopeSessionID.map { try AuthorizedAIContext(household: household, home: home,
                state: state ?? IntegratedAIState(inventory: inventory), places: places, tasks: catalog,
                sessionID: $0, cloudPlanningConsent: true, currentScorecard: currentScorecard) })
        context.contextBinding = context.privateContext?.binding
        return Request(requestID: requestID, context: context)
    }

    /// The model's answer, as the gateway returns it after its own schema and claim-language checks.
    public struct Output: Codable, Sendable, Equatable {
        public struct Task: Codable, Sendable, Equatable {
            public var id: String; public var actionID: String; public var subjectID: String; public var why: String
            public var bespoke: Bespoke?
        }
        public struct Bespoke: Codable, Sendable, Equatable {
            public var title: String; public var fact: String; public var implication: String; public var action: String; public var completionCheck: String
        }
        public var tasks: [Task]
        public var question: String?
    }

    /// What the Prepare tab may show from one accepted answer.
    public struct Personalization: Sendable, Equatable {
        /// Prepare-list step IDs in the model's order, each with the model's household-specific reason.
        public var ranked: [(stepID: String, why: String)]
        /// Ideas outside the scored catalog: shown separately, never counted, never completing anything.
        public var ideas: [Output.Bespoke]
        public var question: String?
        /// Model tasks that were refused because they did not name a current Prepare-list item.
        public var rejectedCount: Int
        public static func == (a: Personalization, b: Personalization) -> Bool {
            a.ranked.map(\.stepID) == b.ranked.map(\.stepID) && a.ranked.map(\.why) == b.ranked.map(\.why)
                && a.ideas == b.ideas && a.question == b.question && a.rejectedCount == b.rejectedCount
        }
    }

    /// Family-facing model text names things by the household's own labels, never by internal record IDs:
    /// "(eq-oxygen)" is removed and a bare "bk-station" becomes that backup's label.
    public static func readable(_ text: String, household: HouseholdProfile?) -> String {
        guard let h = household else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var labels: [String: String] = [:]
        for e in h.equipment { labels[e.id] = e.label.isEmpty ? e.purpose.rawValue : e.label }
        for b in h.backupPower { labels[b.id] = b.label.isEmpty ? b.kind.rawValue : b.label }
        for p in h.people where !p.alias.isEmpty { labels[p.id] = p.alias }
        var out = text
        for (id, label) in labels.sorted(by: { $0.key.count > $1.key.count }) {
            out = out.replacingOccurrences(of: " (\(id))", with: "").replacingOccurrences(of: "(\(id))", with: "")
            out = out.replacingOccurrences(of: id, with: label)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Accepts only tasks whose ID and action/subject identity match a step currently to do; duplicates are dropped.
    public static func accept(_ output: Output, summary: NextStepsSummary, household: HouseholdProfile? = nil) -> Personalization {
        var ranked: [(String, String)] = [], ideas: [Output.Bespoke] = [], rejected = 0
        for task in output.tasks.prefix(3) {
            let why = readable(task.why, household: household)
            if var bespoke = task.bespoke {
                bespoke.title = readable(bespoke.title, household: household); bespoke.action = readable(bespoke.action, household: household)
                ideas.append(bespoke); continue
            }
            guard !why.isEmpty, !ranked.contains(where: { $0.0 == task.id }),
                  let step = summary.toDo.first(where: { $0.id == task.id }),
                  step.recommendation.actionID == task.actionID,
                  (step.recommendation.subjectID ?? "household") == task.subjectID else { rejected += 1; continue }
            ranked.append((step.id, why))
        }
        return Personalization(ranked: ranked, ideas: ideas, question: output.question.map { readable($0, household: household) }, rejectedCount: rejected)
    }

    /// The model sequences within each priority tier only: a lower-priority item never moves above a more urgent one.
    /// Unranked steps keep their deterministic order after the ranked ones of the same tier.
    public static func order(_ toDo: [NextStep], by personalization: Personalization) -> [NextStep] {
        let position = Dictionary(uniqueKeysWithValues: personalization.ranked.enumerated().map { ($0.element.stepID, $0.offset) })
        return toDo.enumerated().sorted { a, b in
            (a.element.recommendation.tier.rawValue, position[a.element.id] ?? Int.max, a.offset)
                < (b.element.recommendation.tier.rawValue, position[b.element.id] ?? Int.max, b.offset)
        }.map(\.element)
    }
}
