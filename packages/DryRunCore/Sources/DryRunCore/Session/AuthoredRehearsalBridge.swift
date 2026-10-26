import Foundation

/// Native scene playback is a projection of accepted commands. The saved session is
/// authoritative; authored default answers are never inserted into its command trace.
public enum AuthoredRehearsalBridge {
    public static let sessionPrefix = "native-rehearsal-v1/"

    public static func initialize(id: String, input: RehearsalInput, library: ScenarioLibrary) throws -> SimulationSession {
        guard input.choices.isEmpty else { throw SessionError.invalidCommand }
        guard let scenario = library.scenario(input.scenarioID), scenario.version == input.scenarioVersion else { throw SessionError.invalidCommand }
        // Compatibility playback has authored decision effects. Adaptive sessions use
        // the donor's versioned hazard commands and never inherit authored defaults.
        var session = SimulationSession(id: id, initial: input, directorPolicy: .reviewed(scenario))
        try advance(&session, to: 0, beforeChoice: false, library: library)
        return session
    }

    public static func choose(_ option: String, at decisionID: String, in session: inout SimulationSession,
                              library: ScenarioLibrary) throws -> SessionReceipt {
        guard let scenario = library.scenario(session.initial.scenarioID),
              let choice = scenario.choicePoints.first(where: { $0.id == decisionID }),
              choice.options.contains(where: { $0.id == option }),
              acceptedInput(session).choices[decisionID] == nil else { throw SessionError.invalidCommand }
        let applicable = scenario.choicePoints.filter {
            Applicability.holds($0.when, household: session.initial.household, home: session.initial.home,
                                variants: effectiveVariants(session.initial, hazard: scenario.hazard))
        }.sorted { ($0.minute, $0.id) < ($1.minute, $1.id) }
        guard applicable.first(where: { acceptedInput(session).choices[$0.id] == nil })?.id == decisionID else {
            throw SessionError.invalidCommand
        }
        var candidate = session
        try advance(&candidate, to: choice.minute, beforeChoice: true, library: library)
        let result = try candidate.commit(.init(id: "native-choice/\(decisionID)", actor: "user", baseRevision: candidate.revision,
            commands: [.init(kind: "choose", target: decisionID, value: option)]), library: library)
        session = candidate
        return result
    }

    public static func acceptedInput(_ session: SimulationSession) -> RehearsalInput {
        var input = session.initial
        input.choices = [:]
        for commit in session.commits where commit.actor == "user" {
            for command in commit.commands where command.kind == "choose" {
                if let target = command.target, let value = command.value { input.choices[target] = value }
            }
        }
        return input
    }

    /// Put each committed receipt at its visible choice boundary. Future authored
    /// snapshots remain teaching projections and cannot reveal a future arrival early.
    public static func projection(_ session: SimulationSession, engine: RehearsalEngine,
                                  library: ScenarioLibrary) throws -> RehearsalResult {
        var result = try engine.run(acceptedInput(session))
        var replay = SimulationSession(id: session.id, initial: session.initial, inventory: session.inventory,
            directorPolicy: session.directorPolicy, concernSeed: session.concernSeed, dependencyPolicy: session.dependencyPolicy)
        for commit in session.commits {
            let receipt = try replay.commit(commit, library: library)
            guard commit.actor == "user", let decision = commit.commands.first(where: { $0.kind == "choose" })?.target,
                  let event = result.events.firstIndex(where: { $0.id == "evt.\(decision)" }) else { continue }
            let boundary = event + 1
            var snapshot = receipt.snapshot
            snapshot.revealedEventCount = boundary
            result.snapshots.removeAll { $0.revealedEventCount == boundary }
            let insertion = result.snapshots.firstIndex { ($0.revealedEventCount ?? 0) > boundary } ?? result.snapshots.endIndex
            result.snapshots.insert(snapshot, at: insertion)
        }
        return result
    }

    private static func effectiveVariants(_ input: RehearsalInput, hazard: HazardKind) -> [String] {
        var variants = input.variants.filter { $0 != "householdLeak" }
        if hazard == .flashFlood && input.effectiveSpatialOptions.floodIsHouseholdLeak { variants.append("householdLeak") }
        return variants
    }

    private static func advance(_ session: inout SimulationSession, to minute: Int, beforeChoice: Bool,
                                library: ScenarioLibrary) throws {
        guard let scenario = library.scenario(session.initial.scenarioID) else { throw SessionError.invalidCommand }
        let variants = effectiveVariants(session.initial, hazard: scenario.hazard)
        let alreadyScheduled = Set(session.commits.flatMap(\.commands).filter {
            ["schedule", "startIncident", "advanceIncident"].contains($0.kind)
        }.compactMap(\.target))
        let events = scenario.events.filter {
            !alreadyScheduled.contains($0.id) && ($0.minute < minute || $0.minute == minute && (!beforeChoice || $0.priority < 100)) &&
            Applicability.holds($0.when, household: session.initial.household, home: session.initial.home, variants: variants)
        }.sorted { ($0.minute, $0.priority, $0.id) < ($1.minute, $1.priority, $1.id) }
        for event in events {
            try session.commit(.init(id: "native-event/\(event.id)", actor: "director", baseRevision: session.revision,
                commands: [.init(kind: "schedule", target: event.id, minute: event.minute)]), library: library)
            try advanceClock(&session, to: event.minute, library: library)
        }
        try advanceClock(&session, to: minute, library: library)
    }

    private static func advanceClock(_ session: inout SimulationSession, to minute: Int, library: ScenarioLibrary) throws {
        for _ in 0..<256 {
            let receipt = try session.query(library: library)
            let due = receipt.pending.contains { ($0.minute ?? Int.max) <= minute }
            if receipt.snapshot.simMinute == minute && !due { return }
            guard receipt.snapshot.simMinute <= minute else { throw SessionError.stale }
            try session.commit(.init(id: "native-clock/\(session.revision)", actor: "director", baseRevision: session.revision,
                commands: [.init(kind: "advance", minute: minute)]), library: library)
        }
        throw SessionError.budget
    }
}
