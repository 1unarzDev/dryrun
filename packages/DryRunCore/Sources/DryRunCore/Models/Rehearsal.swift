import Foundation

// Rehearsal contract. Initial version by lead; Agent A owns subsequent edits to this file.
// The UI and plan builder depend on the names below; additive changes are fine, renames go through the lead.

public enum HazardKind: String, Codable, Sendable, Hashable, CaseIterable {
    case freezePowerLoss, heatGridStrain, tornado, flashFlood, homeFire, waterOutage
}

public enum ServiceState: String, Codable, Sendable, Hashable, CaseIterable {
    case operational, degraded, unavailable, unknown
}

/// A user-visible choice made at a decision point or a preparation applied for "Try this change".
public struct Intervention: Codable, Sendable, Hashable {
    /// Recommendation/action ID from content (e.g. "act.backup.confirm-medical").
    public var actionID: String
    public var parameters: [String: String]
    public init(actionID: String, parameters: [String: String] = [:]) { self.actionID = actionID; self.parameters = parameters }
}

/// Immutable rehearsal input. Counterfactual replay copies this and changes only `interventions`.
public struct RehearsalInput: Codable, Sendable, Hashable {
    public var household: HouseholdProfile
    public var home: HomeModel
    public var scenarioID: String
    public var scenarioVersion: String
    public var contentVersion: String
    public var seed: UInt64
    /// Choice-point ID -> option ID.
    public var choices: [String: String]
    /// Preparations applied to a simulation copy only.
    public var interventions: [Intervention]
    /// Named variant toggles authored in the scenario (e.g. "night" for tornado).
    public var variants: [String]
    public var spatialOptions: SpatialExerciseOptions?
    public init(household: HouseholdProfile, home: HomeModel, scenarioID: String, scenarioVersion: String,
                contentVersion: String, seed: UInt64 = 1, choices: [String: String] = [:],
                interventions: [Intervention] = [], variants: [String] = [], spatialOptions: SpatialExerciseOptions? = nil) {
        self.household = household; self.home = home; self.scenarioID = scenarioID; self.scenarioVersion = scenarioVersion
        self.contentVersion = contentVersion; self.seed = seed; self.choices = choices
        self.interventions = interventions; self.variants = variants; self.spatialOptions = spatialOptions
    }
}

/// One step in an explanation chain: a rule fired because of these facts/events.
public struct EvidenceLink: Codable, Sendable, Hashable {
    public var ruleID: String
    /// Household/home input IDs (e.g. "housing.waterSource", "equipment.eq-oxygen").
    public var factIDs: [String]
    /// Upstream event IDs this depends on.
    public var causedByEventIDs: [String]
    public var sourceIDs: [String]
    public init(ruleID: String, factIDs: [String] = [], causedByEventIDs: [String] = [], sourceIDs: [String] = []) {
        self.ruleID = ruleID; self.factIDs = factIDs; self.causedByEventIDs = causedByEventIDs; self.sourceIDs = sourceIDs
    }
}

public enum EventSeverity: String, Codable, Sendable, Hashable { case info, caution, critical }

public struct SimulationEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// Simulated minutes since scenario start. Distinct from wall clock.
    public var simMinute: Int
    public var priority: Int
    public var phaseID: String
    /// Localized via locale packs ("scenario.freeze.event.grid-loss.title").
    public var titleKey: String
    public var detailKey: String?
    /// Values substituted into localized templates (numbers keep units).
    public var templateValues: [String: String]
    public var severity: EventSeverity
    public var serviceChanges: [String: ServiceState]
    public var evidence: EvidenceLink
    public init(id: String, simMinute: Int, priority: Int = 0, phaseID: String, titleKey: String, detailKey: String? = nil,
                templateValues: [String: String] = [:], severity: EventSeverity = .info,
                serviceChanges: [String: ServiceState] = [:], evidence: EvidenceLink) {
        self.id = id; self.simMinute = simMinute; self.priority = priority; self.phaseID = phaseID; self.titleKey = titleKey
        self.detailKey = detailKey; self.templateValues = templateValues; self.severity = severity
        self.serviceChanges = serviceChanges; self.evidence = evidence
    }
}

public struct ResourceQuantity: Codable, Sendable, Hashable {
    /// nil = unknown; never invented.
    public var amount: Double?
    public var unit: String
    public init(amount: Double?, unit: String) { self.amount = amount; self.unit = unit }
}

public struct SimulationSnapshot: Codable, Sendable, Hashable {
    public var simMinute: Int
    public var services: [String: ServiceState]
    public var resources: [String: ResourceQuantity]
    /// Requirement IDs currently unmet (e.g. "req.power.eq-oxygen").
    public var unmetRequirements: [String]
    public var unknowns: [String]
    public var firedEventIDs: [String]
    public var spatialState: SpatialExerciseState?
    public var revealedEventCount: Int?
    public init(simMinute: Int, services: [String: ServiceState], resources: [String: ResourceQuantity],
                unmetRequirements: [String], unknowns: [String], firedEventIDs: [String], spatialState: SpatialExerciseState? = nil, revealedEventCount: Int? = nil) {
        self.spatialState = spatialState; self.revealedEventCount = revealedEventCount
        self.simMinute = simMinute; self.services = services; self.resources = resources
        self.unmetRequirements = unmetRequirements; self.unknowns = unknowns; self.firedEventIDs = firedEventIDs
    }
}

public struct DecisionPoint: Codable, Sendable, Hashable, Identifiable {
    public struct Option: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var labelKey: String
        /// Authored outcome note shown in the debrief. Unsafe options are never rewarded.
        public var feedbackKey: String
        public var isRecommended: Bool
        public init(id: String, labelKey: String, feedbackKey: String, isRecommended: Bool) {
            self.id = id; self.labelKey = labelKey; self.feedbackKey = feedbackKey; self.isRecommended = isRecommended
        }
    }
    public var id: String
    public var simMinute: Int
    public var promptKey: String
    public var options: [Option]
    public init(id: String, simMinute: Int, promptKey: String, options: [Option]) {
        self.id = id; self.simMinute = simMinute; self.promptKey = promptKey; self.options = options
    }
}

public enum PriorityTier: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case unmetEssentialRequirement = 1
    case blockingUnknownFact = 2
    case scenarioSupplyOrContinuityGap = 3
    case multiScenarioPreparation = 4
    case general = 5
    public static func < (a: PriorityTier, b: PriorityTier) -> Bool { a.rawValue < b.rawValue }
}

public enum EffortBand: String, Codable, Sendable, Hashable { case noCost, low, moderate, high }

public struct Recommendation: Codable, Sendable, Hashable, Identifiable {
    public var subjectID: String?
    public var id: String { subjectID.map { "\(actionID)|\($0)" } ?? actionID }
    public var actionID: String
    public var tier: PriorityTier
    public var titleKey: String
    public var whyKey: String
    public var templateValues: [String: String]
    public var matchedFactIDs: [String]
    public var causeEventIDs: [String]
    public var scenarioIDs: [String]
    /// The intervention that "Try this change" applies to a simulation copy, if modelable.
    public var tryIntervention: Intervention?
    public var modeledEffectKey: String?
    public var effort: EffortBand
    public var feasibilityNotes: [String]
    public var unconfirmed: [String]
    public var sourceIDs: [String]
    public var verificationStatus: EvidenceStatus
    public init(actionID: String, tier: PriorityTier, titleKey: String, whyKey: String, templateValues: [String: String] = [:],
                matchedFactIDs: [String], causeEventIDs: [String], scenarioIDs: [String], tryIntervention: Intervention?,
                modeledEffectKey: String?, effort: EffortBand, feasibilityNotes: [String] = [], unconfirmed: [String] = [],
                sourceIDs: [String], verificationStatus: EvidenceStatus, subjectID: String? = nil) {
        self.actionID = actionID; self.subjectID = subjectID; self.tier = tier; self.titleKey = titleKey; self.whyKey = whyKey
        self.templateValues = templateValues; self.matchedFactIDs = matchedFactIDs; self.causeEventIDs = causeEventIDs
        self.scenarioIDs = scenarioIDs; self.tryIntervention = tryIntervention; self.modeledEffectKey = modeledEffectKey
        self.effort = effort; self.feasibilityNotes = feasibilityNotes; self.unconfirmed = unconfirmed
        self.sourceIDs = sourceIDs; self.verificationStatus = verificationStatus
    }
}

public struct RehearsalResult: Codable, Sendable, Hashable {
    public var input: RehearsalInput
    public var events: [SimulationEvent]
    public var snapshots: [SimulationSnapshot]
    public var decisions: [DecisionPoint]
    /// Fire/egress scenarios: per-person route results under the authored exclusions.
    public var routes: [RouteResult]
    public var recommendations: [Recommendation]
    public var unknowns: [String]
    public var engineVersion: String
    public init(input: RehearsalInput, events: [SimulationEvent], snapshots: [SimulationSnapshot], decisions: [DecisionPoint],
                routes: [RouteResult], recommendations: [Recommendation], unknowns: [String], engineVersion: String) {
        self.input = input; self.events = events; self.snapshots = snapshots; self.decisions = decisions
        self.routes = routes; self.recommendations = recommendations; self.unknowns = unknowns; self.engineVersion = engineVersion
    }
}

public struct RehearsalDiff: Codable, Sendable, Hashable {
    public var addedEventIDs: [String]
    public var removedEventIDs: [String]
    /// service ID -> (baseline final, modified final)
    public var serviceChanges: [String: [ServiceState]]
    public var resolvedRequirements: [String]
    public var newRequirements: [String]
    public var resourceChanges: [String: [ResourceQuantity]]
    public var resolvedRecommendations: [String]
    public init(addedEventIDs: [String], removedEventIDs: [String], serviceChanges: [String: [ServiceState]],
                resolvedRequirements: [String], newRequirements: [String], resourceChanges: [String: [ResourceQuantity]],
                resolvedRecommendations: [String]) {
        self.addedEventIDs = addedEventIDs; self.removedEventIDs = removedEventIDs; self.serviceChanges = serviceChanges
        self.resolvedRequirements = resolvedRequirements; self.newRequirements = newRequirements
        self.resourceChanges = resourceChanges; self.resolvedRecommendations = resolvedRecommendations
    }
}

public struct RehearsalComparison: Codable, Sendable, Hashable {
    public var baseline: RehearsalResult
    public var modified: RehearsalResult
    public var intervention: Intervention
    public var diff: RehearsalDiff
    public init(baseline: RehearsalResult, modified: RehearsalResult, intervention: Intervention, diff: RehearsalDiff) {
        self.baseline = baseline; self.modified = modified; self.intervention = intervention; self.diff = diff
    }
}

/// Cache key for anything derived from household/home/content. Any change invalidates.
public struct RevisionKey: Codable, Sendable, Hashable {
    public var householdID: String
    public var householdRevision: Int
    public var homeID: String
    public var homeRevision: Int
    public var contentVersion: String
    public var algorithmVersion: String
    public init(householdID: String, householdRevision: Int, homeID: String, homeRevision: Int, contentVersion: String, algorithmVersion: String) {
        self.householdID = householdID; self.householdRevision = householdRevision; self.homeID = homeID
        self.homeRevision = homeRevision; self.contentVersion = contentVersion; self.algorithmVersion = algorithmVersion
    }
}
