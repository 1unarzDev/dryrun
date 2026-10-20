import Foundation

/// Offline director for an incremental session: the reviewed authored timeline, applied one key moment at a time
/// through the same validated director commits a Gemini proposal uses. It never answers a choice for the family and
/// never schedules anything the reducer rejects; every returned commit has already been previewed.
public enum LocalDirector {
    public static let version = "dryrun.local-director/1"

    /// The authored choice the family should answer now: applicable, unanswered and due at the current minute.
    /// Only while the session awaits a submitted action, whoever (local or Gemini) requested the decision.
    public static func dueChoice(session: SimulationSession, receipt: SessionReceipt, library: ScenarioLibrary) -> ChoicePoint? {
        guard receipt.directorState?.awaitingUserAction == true, !receipt.finished,
              let scenario = library.scenario(session.initial.scenarioID) else { return nil }
        let chosen = answeredChoiceIDs(session)
        return scenario.choicePoints
            .filter { applies($0.when, session) && !chosen.contains($0.id) && $0.minute <= receipt.snapshot.simMinute }
            .min { ($0.minute, $0.id) < ($1.minute, $1.id) }
    }

    /// The next director commit, or nil when the session is finished or waiting for the family.
    public static func nextCommit(session: SimulationSession, receipt: SessionReceipt, library: ScenarioLibrary) -> SessionCommit? {
        guard !receipt.finished, receipt.directorState?.awaitingUserAction != true,
              let scenario = library.scenario(session.initial.scenarioID) else { return nil }
        let now = receipt.snapshot.simMinute
        let horizon = min(scenario.durationMinutes, session.directorPolicy?.schedulingHorizonMinutes ?? scenario.durationMinutes)
        let scheduled = scheduledProfileIDs(session)
        let chosen = answeredChoiceIDs(session)
        let unscheduled = scenario.events
            .filter { applies($0.when, session) && !scheduled.contains($0.id) && $0.minute <= horizon }
            .sorted { ($0.minute, $0.priority, $0.id) < ($1.minute, $1.priority, $1.id) }
        let choices = scenario.choicePoints
            .filter { applies($0.when, session) && !chosen.contains($0.id) && $0.minute <= horizon }
            .sorted { ($0.minute, $0.id) < ($1.minute, $1.id) }
        let pendingMinute = receipt.pending.compactMap(\.minute).min()
        let eventMinute = [unscheduled.first.map { max($0.minute, now) }, pendingMinute].compactMap { $0 }.min()
        let id = "local-\(session.revision)"
        func commit(_ commands: [SessionCommand]) -> SessionCommit {
            SessionCommit(id: id, actor: "director", baseRevision: session.revision, commands: commands)
        }
        var candidates: [SessionCommit] = []
        if let choice = choices.first, choice.minute <= now {
            // Already due (minute 0, or a depletion boundary stopped the clock after its minute). Events due by now
            // still happen first, as in the authored order (choices after same-minute events).
            let due = unscheduled.filter { $0.minute <= now }.prefix(6)
            if !due.isEmpty {
                let schedules = due.map { SessionCommand(kind: "schedule", target: $0.id, minute: now) }
                candidates.append(commit(schedules + [SessionCommand(kind: "advance", minute: now), SessionCommand(kind: "requestDecision")]))
            }
            candidates.append(commit([SessionCommand(kind: "requestDecision")]))
        } else if let choice = choices.first, eventMinute.map({ choice.minute <= $0 }) ?? true {
            // Events at or before the choice happen first, as in the authored order (choices after same-minute events).
            let due = unscheduled.filter { $0.minute <= choice.minute }.prefix(6)
            let schedules = due.map { SessionCommand(kind: "schedule", target: $0.id, minute: max($0.minute, now)) }
            let advance = SessionCommand(kind: "advance", minute: max(choice.minute, now))
            candidates.append(commit(schedules + [advance, SessionCommand(kind: "requestDecision")]))
            candidates.append(commit([advance, SessionCommand(kind: "requestDecision")]))
        } else if let minute = eventMinute {
            // One key moment: every unscheduled event due at that minute, then advance to it.
            let due = unscheduled.filter { max($0.minute, now) == minute }.prefix(7)
            let schedules = due.map { SessionCommand(kind: "schedule", target: $0.id, minute: minute) }
            candidates.append(commit(schedules + [SessionCommand(kind: "advance", minute: minute)]))
            if !schedules.isEmpty { candidates.append(commit([SessionCommand(kind: "advance", minute: minute)])) }
        } else if now < horizon {
            // Nothing left to schedule: let resources run to the horizon (mandatory boundaries still stop it).
            candidates.append(commit([SessionCommand(kind: "advance", minute: horizon)]))
        }
        candidates.append(commit([SessionCommand(kind: "finish")]))
        // A rejected composition degrades to a simpler valid one; nothing unvalidated is returned.
        for candidate in candidates {
            guard let preview = try? session.preview(candidate, library: library) else { continue }
            // A depletion boundary can stop the clock before the choice's minute. Pause only when the authored choice
            // is actually due, so the family is never asked to decide with nothing to decide.
            if candidate.commands.last?.kind == "requestDecision",
               choices.first.map({ $0.minute > preview.snapshot.simMinute }) == true {
                let advanceOnly = commit(Array(candidate.commands.dropLast()))
                if !advanceOnly.commands.isEmpty, (try? session.preview(advanceOnly, library: library)) != nil { return advanceOnly }
                continue
            }
            return candidate
        }
        return nil
    }

    static func applies(_ when: [String], _ session: SimulationSession) -> Bool {
        let input = session.initial
        var variants = input.variants.filter { $0 != "householdLeak" }
        if input.effectiveSpatialOptions.floodIsHouseholdLeak { variants.append("householdLeak") }
        return Applicability.holds(when, household: input.household, home: input.home, variants: variants)
    }

    static func scheduledProfileIDs(_ session: SimulationSession) -> Set<String> {
        Set(session.commits.filter { $0.actor == "director" }.flatMap(\.commands)
            .filter { ["schedule", "startIncident", "advanceIncident"].contains($0.kind) }.compactMap(\.target))
    }

    static func answeredChoiceIDs(_ session: SimulationSession) -> Set<String> {
        Set(session.commits.filter { $0.actor == "user" }.flatMap(\.commands).filter { $0.kind == "choose" }.compactMap(\.target))
    }
}
