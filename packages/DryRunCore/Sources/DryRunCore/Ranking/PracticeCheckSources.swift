import Foundation

/// Builds the four frozen situations of the non-device practice check (practice-phases/2) from the household's
/// actual facts and home, with the same incident setup the reviewed evaluation uses. Only director setup commits
/// are made; no user action, preset choice or intervention enters a source. Situations the household cannot support
/// (no home for the fire situations) make the check unavailable rather than substituting a sample layout.
///
/// Set A (home fire + water outage) and set B (tornado + winter power loss) ask different questions against the
/// same deterministic anchors. A scanned home starts on set B, so a family that first tried the fictional sample
/// home does not meet the same four situations again.
public enum PracticeCheckSources {
    public static let secondSetVariant = "practice-check-b/3"

    /// The A and B sets alternate across checks; neither is "easier".
    public static func variant(previousChecks: Int, scannedHome: Bool = false) -> String {
        (previousChecks + (scannedHome ? 1 : 0)) % 2 == 0 ? "practice-check-a/2" : secondSetVariant
    }

    /// Scenario for each competency. Set B's continuity situation needs essential equipment to power;
    /// without it the household gets the stored-water continuity situation instead of an unassessable one.
    static func scenario(_ competency: String, variantID: String, household: HouseholdProfile) -> String {
        if variantID == secondSetVariant {
            switch competency {
            case "initialResponse", "communication": return "tornado"
            case "continuity": return household.equipment.contains { $0.isEssential } ? "freeze-power-loss" : "water-outage"
            default: return "freeze-power-loss"
            }
        }
        return ["initialResponse", "adaptation"].contains(competency) ? "home-fire" : "water-outage"
    }

    public static func prepare(attemptID: String, variantID: String, household: HouseholdProfile, home: HomeModel?,
                               contentVersion: String, library: ScenarioLibrary) throws -> [SimulationSession] {
        let order = IntegratedAIState.practiceOrder(variantID)
        guard order.count == 4, variantID.hasSuffix("/2") || variantID == secondSetVariant, home != nil,
              let water = library.scenario("water-outage") else { throw SessionError.invalidCommand }
        func applies(_ e: AuthoredEvent) -> Bool { Applicability.holds(e.when, household: household, home: home, variants: []) }
        // Water is lost at the start: the applicable supply failure (municipal main break or private well pump).
        guard let outage = water.events.filter({ $0.minute == 0 && applies($0) }).sorted(by: { $0.id < $1.id }).first
        else { throw SessionError.invalidCommand }
        let gridLoss = ["evt.freeze-power-loss.cold-arrives", "evt.freeze-power-loss.grid-loss"]
        let setups: [String: [String]] = variantID == secondSetVariant ? [
            "initialResponse": ["evt.tornado.warning"],
            "communication": ["evt.tornado.watch"],
            "adaptation": gridLoss,
            "continuity": scenario("continuity", variantID: variantID, household: household) == "water-outage" ? [outage.id] : gridLoss,
        ] : [
            "initialResponse": ["evt.home-fire.alarm"],
            "adaptation": ["evt.home-fire.alarm", "evt.home-fire.fire-origin"],
            "communication": [outage.id],
            "continuity": [outage.id],
        ]
        return try order.map { competency in
            guard let events = setups[competency],
                  let scenario = library.scenario(Self.scenario(competency, variantID: variantID, household: household))
            else { throw SessionError.invalidCommand }
            let input = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version,
                                       contentVersion: contentVersion, seed: 1)
            var session = try SimulationSession.initialize(id: "\(attemptID)-\(competency)", initial: input, library: library)
            for (index, eventID) in events.enumerated() {
                // Set A keeps its reviewed timing; set B uses each event's authored minute.
                guard let event = scenario.events.first(where: { $0.id == eventID }) else { throw SessionError.invalidCommand }
                let minute = variantID == secondSetVariant ? event.minute : index
                try session.commit(SessionCommit(id: "setup-\(competency)-\(index)", actor: "director", baseRevision: session.revision,
                                                 commands: [SessionCommand(kind: "schedule", target: eventID, minute: minute),
                                                            SessionCommand(kind: "advance", minute: minute)]), library: library)
            }
            return session
        }
    }

    static let authoredChoices = ["initialResponse/home-fire": "choice.home-fire.first-move",
                                  "initialResponse/tornado": "choice.tornado.warning",
                                  "adaptation/freeze-power-loss": "choice.freeze-power-loss.keep-warm"]

    /// The authored question for a situation, when the competency is answered with an authored choice
    /// (the fire or tornado first move, or keeping warm once the power is out).
    public static func authoredChoice(_ session: SimulationSession, competency: String, library: ScenarioLibrary) -> ChoicePoint? {
        guard let id = authoredChoices["\(competency)/\(session.initial.scenarioID)"] else { return nil }
        return library.scenario(session.initial.scenarioID)?.choicePoints.first { $0.id == id }
    }
}
