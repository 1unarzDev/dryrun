import Foundation

// Authored scenario packs (content/scenarios/*.json). Packs own timing, choices, exclusions,
// advisories, and debrief keys. Rule semantics live in Swift (see `RuleID`), so a pack can only
// select from reviewed behaviour; it cannot invent new safety logic.

public enum ContentReviewStatus: String, Codable, Sendable, Hashable { case draft, reviewed, needsReview }

/// Water advisory types are distinct: each has different feasible responses [S24].
public enum WaterAdvisory: String, Codable, Sendable, Hashable, CaseIterable {
    case quantityUnavailable, unknownQuality, boilWater, doNotDrink, doNotUse
}

public struct ScenarioPhase: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var startMinute: Int
    public var titleKey: String
    /// `immediate` phases (fire/tornado/flood) are followed by optional 72-hour recovery.
    public var kind: String
}

public struct ScenarioVariant: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var labelKey: String
}

/// One authored event. `rule` selects Swift semantics; `params` are rule inputs.
public struct AuthoredEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var minute: Int
    public var priority: Int
    public var phaseID: String
    public var rule: String
    public var params: [String: String]
    public var titleKey: String
    public var detailKey: String?
    public var severity: EventSeverity
    public var sourceIDs: [String]
    /// Applicability predicates, all must hold (see `Applicability`).
    public var when: [String]

    private enum CodingKeys: String, CodingKey { case id, minute, priority, phaseID, rule, params, titleKey, detailKey, severity, sourceIDs, when }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        minute = try c.decode(Int.self, forKey: .minute)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        phaseID = try c.decode(String.self, forKey: .phaseID)
        rule = try c.decode(String.self, forKey: .rule)
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        titleKey = try c.decode(String.self, forKey: .titleKey)
        detailKey = try c.decodeIfPresent(String.self, forKey: .detailKey)
        severity = try c.decodeIfPresent(EventSeverity.self, forKey: .severity) ?? .info
        sourceIDs = try c.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []
        when = try c.decodeIfPresent([String].self, forKey: .when) ?? []
    }
}

public struct AuthoredOption: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var labelKey: String
    public var feedbackKey: String
    /// Authored effect selector: relocate, shelterInPlace, unsafe, useStoredWater, boilTapWater,
    /// goToShelter, stayInBedroom, takeExit, leaveEarly, driveThroughWater, waitForInstructions, ...
    public var effect: String
    /// Unsafe options are never recommended, whatever the household state.
    public var unsafe: Bool

    private enum CodingKeys: String, CodingKey { case id, labelKey, feedbackKey, effect, unsafe }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        labelKey = try c.decode(String.self, forKey: .labelKey)
        feedbackKey = try c.decode(String.self, forKey: .feedbackKey)
        effect = try c.decode(String.self, forKey: .effect)
        unsafe = try c.decodeIfPresent(Bool.self, forKey: .unsafe) ?? false
    }
}

public struct ChoicePoint: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var minute: Int
    public var phaseID: String
    public var promptKey: String
    /// Used when the rehearsal input has not chosen yet (lets the timeline run end-to-end).
    public var defaultOptionID: String
    public var options: [AuthoredOption]
    public var sourceIDs: [String]
    public var when: [String]

    private enum CodingKeys: String, CodingKey { case id, minute, phaseID, promptKey, defaultOptionID, options, sourceIDs, when }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        minute = try c.decode(Int.self, forKey: .minute)
        phaseID = try c.decode(String.self, forKey: .phaseID)
        promptKey = try c.decode(String.self, forKey: .promptKey)
        defaultOptionID = try c.decode(String.self, forKey: .defaultOptionID)
        options = try c.decode([AuthoredOption].self, forKey: .options)
        sourceIDs = try c.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []
        when = try c.decodeIfPresent([String].self, forKey: .when) ?? []
    }
}

public struct ScenarioDebrief: Codable, Sendable, Hashable {
    public var pointKeys: [String]
    public var sourceIDs: [String]
}

public struct ScenarioDefinition: Codable, Sendable, Hashable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var hazard: HazardKind
    public var titleKey: String
    public var summaryKey: String
    public var startingConditionsKey: String
    /// Always true: every time, severity, and condition in a pack is a fictional exercise assumption.
    public var fictional: Bool
    public var reviewStatus: ContentReviewStatus
    public var durationMinutes: Int
    /// Ambient condition the household's heating/cooling must answer: "cold", "hot", or "none".
    public var ambient: String
    public var phases: [ScenarioPhase]
    public var variants: [ScenarioVariant]
    public var events: [AuthoredEvent]
    public var choicePoints: [ChoicePoint]
    public var ruleIDs: [String]
    public var sourceIDs: [String]
    public var debrief: ScenarioDebrief
}

public enum ScenarioLoadError: Error, Equatable, Sendable {
    case unreadable(String)
    case invalid(String, String)
    case duplicateScenario(String)
    case unknownRule(scenario: String, rule: String)
}

public struct ScenarioLibrary: Sendable {
    public var scenarios: [ScenarioDefinition]

    public init(scenarios: [ScenarioDefinition]) throws {
        var seen = Set<String>()
        for s in scenarios {
            guard seen.insert(s.id).inserted else { throw ScenarioLoadError.duplicateScenario(s.id) }
            try Self.validate(s)
        }
        self.scenarios = scenarios.sorted { $0.id < $1.id }
    }

    /// Decodes every `*.json` in the directory (non-recursive), sorted by filename for determinism.
    public static func load(from directory: URL) throws -> ScenarioLibrary {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            throw ScenarioLoadError.unreadable(directory.path)
        }
        var out: [ScenarioDefinition] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            do {
                let data = try Data(contentsOf: url)
                out.append(try DryRunJSON.decoder().decode(ScenarioDefinition.self, from: data))
            } catch {
                throw ScenarioLoadError.invalid(name, String(describing: error))
            }
        }
        return try ScenarioLibrary(scenarios: out)
    }

    public func scenario(_ id: String) -> ScenarioDefinition? { scenarios.first { $0.id == id } }

    static func validate(_ s: ScenarioDefinition) throws {
        for e in s.events where !RuleID.known.contains(e.rule) {
            throw ScenarioLoadError.unknownRule(scenario: s.id, rule: e.rule)
        }
        guard s.fictional else { throw ScenarioLoadError.invalid(s.id, "packs must be marked fictional") }
        for c in s.choicePoints where !c.options.contains(where: { $0.id == c.defaultOptionID }) {
            throw ScenarioLoadError.invalid(s.id, "choice \(c.id) default option missing")
        }
        for c in s.choicePoints {
            if let d = c.options.first(where: { $0.id == c.defaultOptionID }), d.unsafe {
                throw ScenarioLoadError.invalid(s.id, "choice \(c.id) default option must not be unsafe")
            }
        }
    }
}

/// Rule identifiers whose semantics are implemented in `RehearsalEngine`.
public enum RuleID {
    /// Sets an external service state: params service, state.
    public static let setExternal = "rule.external.set"
    /// Issues a utility water advisory: params advisory.
    public static let waterAdvisory = "rule.water.advisory"
    /// Fire ignition with an origin space kind: params originKind. Plans per-person practice routes.
    public static let fireIgnition = "rule.fire.ignition"
    /// Authored blockage of the primary route's exit and chokepoint; replans.
    public static let fireBlockPrimary = "rule.fire.block-primary"
    /// Tornado warning: checks preselected shelter, alerting at night, manufactured-home limits.
    public static let tornadoWarning = "rule.tornado.warning"
    /// Flash-flood warning: road crossings closed, relocation constraints.
    public static let floodWarning = "rule.flood.warning"
    /// A selected local water-affected area, without regional road, utility or evacuation assumptions.
    public static let householdLeak = "rule.flood.household-leak"
    /// Planning checkpoint: resource accounting summary (water storage target, handset, backups).
    public static let checkpoint = "rule.checkpoint"
    /// Recovery: power back. Must NOT refill batteries/water, clear advisories, or certify devices.
    public static let recoveryPowerRestored = "rule.recovery.power-restored"
    /// Displacement / recovery planning note (after immediate phases).
    public static let recoveryDisplacement = "rule.recovery.displacement"
    /// Informational authored event with no state change.
    public static let note = "rule.note"

    public static let known: Set<String> = [setExternal, waterAdvisory, fireIgnition, fireBlockPrimary, tornadoWarning,
                                            floodWarning, householdLeak, checkpoint, recoveryPowerRestored, recoveryDisplacement, note]
}
