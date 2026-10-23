import Foundation

/// One answer option of a planned practice situation. The command and the consequence (credit and the host receipt
/// digest of a preview commit) are Core's; the label and feedback are optional explanation text (deterministic copy
/// when nil, AI wording when a validated proposal supplied it). Every branch is computed before the set is shown, so
/// answering needs no server round trip.
public struct PracticePlanOption: Codable, Sendable, Hashable {
    public var id: String
    public var command: SessionCommand
    /// Core's anchored credit for this option (nil = this option is not assessed by the versioned anchors).
    public var credit: Double?
    /// The previewed committed-state consequence (receipt digest of the answer at the frozen revision).
    public var consequenceDigest: String
    public var label: String?
    public var feedback: String?
    public init(id: String, command: SessionCommand, credit: Double?, consequenceDigest: String, label: String? = nil, feedback: String? = nil) {
        self.id = id; self.command = command; self.credit = credit; self.consequenceDigest = consequenceDigest
        self.label = label; self.feedback = feedback
    }
}

/// A practice situation Core can set up for this household and home: a hazard, director setup events and the
/// options Core accepts. Candidates are the closed universe a plan (deterministic or AI-proposed) chooses from.
public struct PracticePlanCandidate: Codable, Sendable, Hashable {
    public var id: String
    public var competency: String
    public var scenarioID: String
    public var setupEventIDs: [String]
    public var options: [PracticePlanOption]
}

public struct PracticePlanSituation: Codable, Sendable, Hashable {
    public var competency: String
    public var candidateID: String
    public var scenarioID: String
    public var setupEventIDs: [String]
    /// Question wording; nil uses the deterministic copy.
    public var prompt: String?
    public var options: [PracticePlanOption]
}

/// A whole four-situation practice set (practice-phases/3), planned up front and bound to the household/home it was
/// built for. Core recomputes every option's consequence before adopting it; AI text is explanation only.
public struct PracticeSetPlan: Codable, Sendable, Hashable {
    public static let contractVersion = "dryrun.practice-plan/1"
    public var contractVersion: String = PracticeSetPlan.contractVersion
    public var variantID: String
    public var attemptIndex: Int
    public var bindingDigest: String
    /// "core" for the deterministic generator, otherwise the provider that worded a validated proposal.
    public var servedBy: String
    public var situations: [PracticePlanSituation]
}

/// An AI proposal: candidate choice and wording only. Commands and consequences always come from Core.
public struct PracticePlanProposal: Codable, Sendable, Hashable {
    public struct Option: Codable, Sendable, Hashable { public var id: String; public var label: String; public var feedback: String
        public init(id: String, label: String, feedback: String) { self.id = id; self.label = label; self.feedback = feedback } }
    public struct Situation: Codable, Sendable, Hashable { public var competency: String; public var candidateID: String; public var prompt: String; public var options: [Option]
        public init(competency: String, candidateID: String, prompt: String, options: [Option]) { self.competency = competency; self.candidateID = candidateID; self.prompt = prompt; self.options = options } }
    public var situations: [Situation]
    public init(situations: [Situation]) { self.situations = situations }
}

public enum PracticeSetPlanner {
    public static let variants = ["practice-check-a/3", "practice-check-b/3"]
    static let maxOptions = 6, minOptions = 2
    static let probeID = "practice-plan-probe"

    public static func variant(attemptIndex: Int) -> String { attemptIndex % 2 == 0 ? variants[0] : variants[1] }

    /// Which hazards each competency's versioned anchors can assess.
    static let scenariosByCompetency: [String: [String]] = [
        "initialResponse": ["home-fire", "water-outage"],
        "adaptation": ["home-fire"],
        "communication": ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"],
        "continuity": ["water-outage", "freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood"],
    ]
    static func allows(competency: String, scenarioID: String) -> Bool { scenariosByCompetency[competency]?.contains(scenarioID) == true }

    public static func bindingDigest(household: HouseholdProfile, home: HomeModel?, contentVersion: String) -> String {
        let h = (try? DryRunJSON.encoder().encode(household)) ?? Data()
        return StableDigest.of(h + Data((home.map(HomeFingerprint.of) ?? "no-home").utf8) + Data(contentVersion.utf8))
    }

    // MARK: Candidates

    /// The setup events for a hazard at the first decision moment the anchors can assess.
    static func setups(_ scenario: ScenarioDefinition, competency: String, household: HouseholdProfile, home: HomeModel?) -> [[String]] {
        func applies(_ e: AuthoredEvent) -> Bool { Applicability.holds(e.when, household: household, home: home, variants: []) }
        let first = scenario.events.filter { $0.minute == 0 && applies($0) }.sorted { $0.id < $1.id }.first?.id
        func with(_ id: String) -> [String]? {
            guard let first, let event = scenario.events.first(where: { $0.id == id }), applies(event) else { return nil }
            return first == id ? [first] : [first, id]
        }
        switch (competency, scenario.id) {
        case ("adaptation", "home-fire"): return [with("evt.home-fire.fire-origin")].compactMap { $0 }
        case ("continuity", "freeze-power-loss"): return [with("evt.freeze-power-loss.grid-loss")].compactMap { $0 }
        case ("continuity", "heat-grid-strain"): return [with("evt.heat-grid-strain.rotating-outage")].compactMap { $0 }
        case ("continuity", "tornado"): return [with("evt.tornado.grid-down")].compactMap { $0 }
        case ("continuity", "flash-flood"): return [with("evt.flash-flood.power-cut")].compactMap { $0 }
        default: return first.map { [[$0]] } ?? []
        }
    }

    static func session(id: String, household: HouseholdProfile, home: HomeModel?, scenario: ScenarioDefinition, events: [String],
                        contentVersion: String, library: ScenarioLibrary) throws -> SimulationSession {
        let input = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version,
                                   contentVersion: contentVersion, seed: 1)
        var session = try SimulationSession.initialize(id: id, initial: input, library: library)
        for (minute, event) in events.enumerated() {
            try session.commit(SessionCommit(id: "setup-\(id)-\(minute)", actor: "director", baseRevision: session.revision,
                                             commands: [SessionCommand(kind: "schedule", target: event, minute: minute),
                                                        SessionCommand(kind: "advance", minute: minute)]), library: library)
        }
        return session
    }

    /// Previews one answer at the frozen revision: Core's consequence for that branch.
    static func probe(_ command: SessionCommand, competency: String, session: SimulationSession, library: ScenarioLibrary) -> (credit: Double?, digest: String)? {
        var copy = session
        guard let receipt = try? copy.commit(SessionCommit(id: probeID, actor: "user", baseRevision: copy.revision, commands: [command]), library: library)
        else { return nil }
        let credit = try? PracticeEvaluator.evaluate(competencyID: competency, actionID: probeID, session: copy, library: library).credit
        return (credit, receipt.contextDigest)
    }

    static func commands(competency: String, session: SimulationSession, receipt: SessionReceipt, library: ScenarioLibrary) -> [(String, SessionCommand)] {
        let h = session.initial.household
        var out: [(String, SessionCommand)] = []
        func water() {
            guard receipt.snapshot.resources["res.water.stored"] != nil else { return }
            out.append(("water.essential", .init(kind: "useStoredWater", value: "essential")))
            out.append(("water.all", .init(kind: "useStoredWater", value: "all")))
        }
        func contacts() { for c in h.contacts where c.isComplete { out.append(("contact.\(c.id)", .init(kind: "contact", target: c.id))) } }
        func power() {
            for e in h.equipment where e.isEssential && !e.compatibleBackupIDs.isEmpty {
                for b in e.compatibleBackupIDs { out.append(("power.\(e.id).\(b)", .init(kind: "allocatePower", target: e.id, value: b))) }
                out.append(("power.\(e.id).none", .init(kind: "allocatePower", target: e.id, value: "none")))
            }
        }
        switch competency {
        case "initialResponse":
            if session.initial.scenarioID == "home-fire", let choice = library.scenario("home-fire")?.choicePoints.first(where: { $0.id == "choice.home-fire.first-move" }) {
                for o in choice.options { out.append(("choose.\(o.id)", .init(kind: "choose", target: choice.id, value: o.id))) }
            } else { water() }
        case "adaptation":
            guard let home = session.initial.home else { break }
            for route in receipt.routes where !route.request.exclusions.blockedSpaceIDs.isEmpty || !route.request.exclusions.blockedPortalIDs.isEmpty {
                guard let person = route.request.personID else { continue }
                let start = route.request.startSpaceID
                for space in home.spaces where space.id != start {
                    out.append(("move.\(person).\(space.id)", .init(kind: "moveTo", target: person, value: space.id)))
                }
                // Plausible alternatives to moving: shutting a door of the current room, or calling for help.
                for portal in home.portals where portal.kind == .door && [portal.sideA, portal.sideB].contains(.space(start)) {
                    out.append(("door.\(person).\(portal.id)", .init(kind: "closeDoor", target: portal.id, value: person)))
                }
                contacts()
            }
        case "communication": contacts(); water(); power()
        case "continuity": if session.initial.scenarioID == "water-outage" { water() } else { power() }
        default: break
        }
        return out
    }

    /// Every situation Core can set up and score for this household and home, each with its accepted options and
    /// their precomputed consequences.
    public static func candidates(household: HouseholdProfile, home: HomeModel?, contentVersion: String, library: ScenarioLibrary) -> [PracticePlanCandidate] {
        guard home != nil else { return [] }
        var out: [PracticePlanCandidate] = []
        for competency in ScoreCompiler.competencies {
            for scenarioID in scenariosByCompetency[competency] ?? [] {
                guard let scenario = library.scenario(scenarioID) else { continue }
                for events in setups(scenario, competency: competency, household: household, home: home) {
                    guard let session = try? session(id: "practice-plan", household: household, home: home, scenario: scenario, events: events,
                                                     contentVersion: contentVersion, library: library),
                          let receipt = try? session.query(library: library), !receipt.finished else { continue }
                    var options: [PracticePlanOption] = []
                    for (id, command) in commands(competency: competency, session: session, receipt: receipt, library: library) {
                        guard let result = probe(command, competency: competency, session: session, library: library) else { continue }
                        options.append(.init(id: id, command: command, credit: result.credit, consequenceDigest: result.digest))
                    }
                    // Moves: keep the person's assessed moves only, at most a few per person.
                    if competency == "adaptation" {
                        let people = Set(options.filter { $0.command.kind == "moveTo" }.compactMap(\.command.target)).sorted()
                        for person in people {
                            let moves = options.filter { $0.command.kind == "moveTo" && $0.command.target == person }
                            let others = options.filter { ($0.command.kind == "closeDoor" && $0.command.value == person) || $0.command.kind == "contact" }
                            let picked = Array(moves.filter { $0.credit == 1 }.prefix(2) + moves.filter { $0.credit == 0 }.prefix(2)
                                               + others.prefix(2))
                            if picked.count >= minOptions, picked.contains(where: { $0.credit == 1 }) {
                                out.append(.init(id: "adaptation.home-fire.\(person)", competency: competency, scenarioID: scenarioID,
                                                 setupEventIDs: events, options: picked))
                            }
                        }
                        continue
                    }
                    options = Array(options.prefix(maxOptions))
                    guard options.count >= minOptions, options.contains(where: { $0.credit == 1 }) else { continue }
                    out.append(.init(id: "\(competency).\(scenarioID)", competency: competency, scenarioID: scenarioID,
                                     setupEventIDs: events, options: options))
                }
            }
        }
        return out
    }

    // MARK: Deterministic generator

    static func mix(_ text: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// A varied deterministic plan (different per attempt index and per household/home binding). Nil when Core cannot
    /// set up all four competencies; the caller then uses the legacy practice-phases/2 sources.
    public static func deterministicPlan(attemptIndex: Int, household: HouseholdProfile, home: HomeModel?, contentVersion: String,
                                         library: ScenarioLibrary, candidates given: [PracticePlanCandidate]? = nil) -> PracticeSetPlan? {
        let pool = given ?? candidates(household: household, home: home, contentVersion: contentVersion, library: library)
        let binding = bindingDigest(household: household, home: home, contentVersion: contentVersion)
        let variant = variant(attemptIndex: attemptIndex)
        var used: Set<String> = []
        var situations: [PracticePlanSituation] = []
        for competency in IntegratedAIState.practiceOrder(variant) {
            let mine = pool.filter { $0.competency == competency }
            guard !mine.isEmpty else { return nil }
            let fresh = mine.filter { !used.contains($0.scenarioID) }
            let choices = fresh.isEmpty ? mine : fresh
            let seed = mix("\(binding)|\(attemptIndex)|\(competency)")
            let candidate = choices[Int(seed % UInt64(choices.count))]
            used.insert(candidate.scenarioID)
            var options = candidate.options.sorted { mix("\(seed)|\($0.id)") < mix("\(seed)|\($1.id)") }
            if options.count > 4, let right = options.first(where: { $0.credit == 1 }) {
                options = Array(([right] + options.filter { $0.id != right.id }.prefix(3))
                    .sorted { mix("\(seed)|\($0.id)") < mix("\(seed)|\($1.id)") })
            }
            situations.append(.init(competency: competency, candidateID: candidate.id, scenarioID: candidate.scenarioID,
                                    setupEventIDs: candidate.setupEventIDs, prompt: nil, options: options))
        }
        return PracticeSetPlan(variantID: variant, attemptIndex: attemptIndex, bindingDigest: binding, servedBy: "core", situations: situations)
    }

    // MARK: Host validation of an AI proposal

    static func clean(_ text: String, max: Int) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= max, !t.contains("evt."), !t.contains("choice."), t.range(of: "\\b(eq|bk|contact|person|room)-[A-Za-z0-9]", options: .regularExpression) == nil
        else { return nil }
        return t
    }

    /// Adopts a proposal only when every situation is a Core candidate for its competency (in variant order, distinct
    /// candidates), every option ID belongs to that candidate (2-6, distinct, at least one credited), and every text is
    /// short plain copy. Commands, credit and consequences are always Core's. Throws on any violation.
    public static func adopt(_ proposal: PracticePlanProposal, attemptIndex: Int, servedBy: String, household: HouseholdProfile, home: HomeModel?,
                             contentVersion: String, library: ScenarioLibrary, candidates given: [PracticePlanCandidate]? = nil) throws -> PracticeSetPlan {
        let pool = given ?? candidates(household: household, home: home, contentVersion: contentVersion, library: library)
        let variant = variant(attemptIndex: attemptIndex)
        let order = IntegratedAIState.practiceOrder(variant)
        guard proposal.situations.map(\.competency) == order,
              Set(proposal.situations.map(\.candidateID)).count == order.count else { throw SessionError.invalidCommand }
        var situations: [PracticePlanSituation] = []
        for s in proposal.situations {
            guard let candidate = pool.first(where: { $0.id == s.candidateID && $0.competency == s.competency }),
                  (minOptions...maxOptions).contains(s.options.count), Set(s.options.map(\.id)).count == s.options.count,
                  let prompt = clean(s.prompt, max: 240) else { throw SessionError.invalidCommand }
            let options = try s.options.map { o -> PracticePlanOption in
                guard var core = candidate.options.first(where: { $0.id == o.id }),
                      let label = clean(o.label, max: 120), let feedback = clean(o.feedback, max: 280) else { throw SessionError.invalidCommand }
                core.label = label; core.feedback = feedback
                return core
            }
            guard options.contains(where: { $0.credit == 1 }) else { throw SessionError.invalidCommand }
            situations.append(.init(competency: s.competency, candidateID: candidate.id, scenarioID: candidate.scenarioID,
                                    setupEventIDs: candidate.setupEventIDs, prompt: prompt, options: options))
        }
        return PracticeSetPlan(variantID: variant, attemptIndex: attemptIndex,
                               bindingDigest: bindingDigest(household: household, home: home, contentVersion: contentVersion),
                               servedBy: servedBy, situations: situations)
    }

    /// Re-verifies a cached plan against the current household/home: same binding, every situation a current candidate
    /// and every option's command and consequence recomputed identically by Core.
    public static func verify(_ plan: PracticeSetPlan, household: HouseholdProfile, home: HomeModel?, contentVersion: String,
                              library: ScenarioLibrary) throws {
        guard plan.contractVersion == PracticeSetPlan.contractVersion, variants.contains(plan.variantID),
              plan.bindingDigest == bindingDigest(household: household, home: home, contentVersion: contentVersion),
              plan.situations.map(\.competency) == IntegratedAIState.practiceOrder(plan.variantID) else { throw SessionError.stale }
        for s in plan.situations {
            guard allows(competency: s.competency, scenarioID: s.scenarioID), let scenario = library.scenario(s.scenarioID),
                  setups(scenario, competency: s.competency, household: household, home: home).contains(s.setupEventIDs),
                  (minOptions...maxOptions).contains(s.options.count), Set(s.options.map(\.id)).count == s.options.count,
                  s.options.contains(where: { $0.credit == 1 }) else { throw SessionError.invalidCommand }
            let session = try session(id: "practice-plan", household: household, home: home, scenario: scenario, events: s.setupEventIDs,
                                      contentVersion: contentVersion, library: library)
            for o in s.options {
                guard let result = probe(o.command, competency: s.competency, session: session, library: library),
                      result.credit == o.credit, result.digest == o.consequenceDigest else { throw SessionError.invalidCommand }
            }
        }
    }

    /// Builds the four frozen sources for a verified plan (director setup commits only).
    public static func prepare(_ plan: PracticeSetPlan, attemptID: String, household: HouseholdProfile, home: HomeModel?,
                               contentVersion: String, library: ScenarioLibrary) throws -> [SimulationSession] {
        try plan.situations.map { s in
            guard let scenario = library.scenario(s.scenarioID) else { throw SessionError.invalidCommand }
            return try session(id: "\(attemptID)-\(s.competency)", household: household, home: home, scenario: scenario,
                               events: s.setupEventIDs, contentVersion: contentVersion, library: library)
        }
    }
}
