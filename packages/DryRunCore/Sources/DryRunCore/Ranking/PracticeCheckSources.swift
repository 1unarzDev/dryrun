import Foundation

/// Builds the four frozen situations of the non-device practice check (practice-phases/2) from the household's
/// actual facts and home, with the same incident setup the reviewed evaluation uses. Only director setup commits
/// are made; no user action, preset choice or intervention enters a source. Situations the household cannot support
/// (no home for the fire situations) make the check unavailable rather than substituting a sample layout.
public enum PracticeCheckSources {
    /// The A and B orders alternate across attempts; neither is "easier".
    public static func variant(previousAttempts: Int) -> String {
        previousAttempts % 2 == 0 ? "practice-check-a/2" : "practice-check-b/2"
    }

    public static func prepare(attemptID: String, variantID: String, household: HouseholdProfile, home: HomeModel?,
                               contentVersion: String, library: ScenarioLibrary) throws -> [SimulationSession] {
        let order = IntegratedAIState.practiceOrder(variantID)
        guard order.count == 4, variantID.hasSuffix("/2"), home != nil,
              let fire = library.scenario("home-fire"), let water = library.scenario("water-outage") else { throw SessionError.invalidCommand }
        func applies(_ e: AuthoredEvent) -> Bool { Applicability.holds(e.when, household: household, home: home, variants: []) }
        // Water is lost at the start: the applicable supply failure (municipal main break or private well pump).
        guard let outage = water.events.filter({ $0.minute == 0 && applies($0) }).sorted(by: { $0.id < $1.id }).first
        else { throw SessionError.invalidCommand }
        let setups: [String: (ScenarioDefinition, [String])] = [
            "initialResponse": (fire, ["evt.home-fire.alarm"]),
            "adaptation": (fire, ["evt.home-fire.alarm", "evt.home-fire.fire-origin"]),
            "communication": (water, [outage.id]),
            "continuity": (water, [outage.id]),
        ]
        return try order.map { competency in
            guard let (scenario, events) = setups[competency] else { throw SessionError.invalidCommand }
            let input = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version,
                                       contentVersion: contentVersion, seed: 1)
            var session = try SimulationSession.initialize(id: "\(attemptID)-\(competency)", initial: input, library: library)
            for (minute, event) in events.enumerated() {
                try session.commit(SessionCommit(id: "setup-\(competency)-\(minute)", actor: "director", baseRevision: session.revision,
                                                 commands: [SessionCommand(kind: "schedule", target: event, minute: minute),
                                                            SessionCommand(kind: "advance", minute: minute)]), library: library)
            }
            return session
        }
    }

    /// The authored question for a situation, when the competency is answered with an authored choice (initial response).
    public static func authoredChoice(_ session: SimulationSession, competency: String, library: ScenarioLibrary) -> ChoicePoint? {
        guard competency == "initialResponse" else { return nil }
        return library.scenario(session.initial.scenarioID)?.choicePoints.first { $0.id == "choice.home-fire.first-move" }
    }
}
