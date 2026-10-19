import Foundation

public enum SessionError: String, Error, Codable, Sendable { case stale, duplicate, invalidCommand, budget, finished, persistence }

/// Flat transport command. Actor permissions are enforced by the reducer, never by presentation.
public struct SessionCommand: Codable, Hashable, Sendable {
    public var kind: String
    public var target: String?
    public var value: String?
    public var minute: Int?
    public init(kind: String, target: String? = nil, value: String? = nil, minute: Int? = nil) {
        self.kind = kind; self.target = target; self.value = value; self.minute = minute
    }
}
public struct SessionCommit: Codable, Hashable, Sendable {
    public var id: String
    public var actor: String
    public var baseRevision: Int
    public var commands: [SessionCommand]
    public init(id: String, actor: String, baseRevision: Int, commands: [SessionCommand]) {
        self.id = id; self.actor = actor; self.baseRevision = baseRevision; self.commands = commands
    }
}
public struct SessionReceipt: Codable, Sendable, Equatable {
    public var sessionID: String
    public var revision: Int
    public var eventSequence: Int
    public var contextDigest: String
    public var snapshot: SimulationSnapshot
    public var routes: [RouteResult]
    public var events: [SimulationEvent]
    public var pending: [SessionCommand]
    public var finished: Bool
    public var inventory:ExerciseInventory?
}

/// Serializable event-sourced session. Replay executes existing RunState, allocator, hazard and route rules.
/// Replay is deliberately local and bounded (128 commits); no provider call or speculative default choice.
public struct SimulationSession: Codable, Sendable {
    public let contractVersion: String
    public let id: String
    public let initial: RehearsalInput
    public let inventory:SessionInventorySeed?
    public private(set) var commits: [SessionCommit]
    public init(id: String, initial: RehearsalInput, inventory:SessionInventorySeed?=nil) {
        self.contractVersion = "dryrun.ai/1"; self.id = id; self.initial = initial; self.inventory=inventory; self.commits = []
    }
    public var revision: Int { commits.count }
    public func preview(_ commit: SessionCommit, library: ScenarioLibrary) throws -> SessionReceipt {
        var copy = self
        return try copy.commit(commit, library: library)
    }
    /// Persistence receives the entire candidate before self is published. Throwing leaves self unchanged.
    @discardableResult public mutating func commit(_ proposal: SessionCommit, library: ScenarioLibrary,
        persist: (SimulationSession) throws -> Void = { _ in }) throws -> SessionReceipt {
        guard !commits.contains(where: { $0.id == proposal.id }) else { throw SessionError.duplicate }
        guard proposal.baseRevision == revision else { throw SessionError.stale }
        guard commits.count < 128, !proposal.commands.isEmpty, proposal.commands.count <= 8 else { throw SessionError.budget }
        guard proposal.actor == "user" || proposal.actor == "director" else { throw SessionError.invalidCommand }
        var copy = self; copy.commits.append(proposal)
        let receipt = try copy.query(library: library)
        try persist(copy)
        self = copy
        return receipt
    }
    public func query(library: ScenarioLibrary) throws -> SessionReceipt {
        guard commits.count<=128, let scenario = library.scenario(initial.scenarioID), scenario.version == initial.scenarioVersion else { throw SessionError.invalidCommand }
        let prepared = InterventionApplier.apply(initial.interventions, household: initial.household, home: initial.home)
        var run = RunState(scenario: scenario, input: initial, household: prepared.0, home: prepared.1, planner: EgressPlanner())
        var supplies=try inventory.map(SessionSupplyLedger.init)
        try supplies?.synchronize(&run)
        run.noteStaticUnknowns(); try run.reevaluate(trigger: nil, emit: false)
        var pending: [SessionCommand] = [], ended = false, scheduled = 0
        var scheduledIDs=Set<String>()
        var chosenIDs=Set<String>()
        var inputIDs=Set<String>()
        for (index, commit) in commits.enumerated() {
            guard !commit.id.isEmpty,!commit.commands.isEmpty,commit.commands.count<=8,inputIDs.insert(commit.id).inserted, commit.actor == "user" || commit.actor == "director" else {throw SessionError.invalidCommand}
            guard commit.baseRevision == index, !ended else { throw SessionError.finished }
            for command in commit.commands {
                guard !ended else {throw SessionError.finished}
                if commit.actor == "user" {
                    switch command.kind {
                    case "takeSupply", "transferSupply":
                        guard supplies != nil else {throw SessionError.invalidCommand}
                        try supplies!.apply(command,run:run)
                    case "allocatePower":
                        guard let eqID = command.target, let eq = run.household.equipment.firstIndex(where: { $0.id == eqID }),
                            let source = command.value,
                            source == "none" || initial.household.equipment.first(where: { $0.id == eqID })?.compatibleBackupIDs.contains(source) == true else { throw SessionError.invalidCommand }
                        run.household.equipment[eq].compatibleBackupIDs = source == "none" ? [] : [source]
                        run.model = DependencyModel.build(household: run.household)
                    case "useStoredWater":
                        guard command.value == "essential" || command.value == "all" else { throw SessionError.invalidCommand }
                        run.waterDrawMultiplier = command.value == "all" ? 2 : 1
                    case "choose":
                        guard let choiceID = command.target, chosenIDs.insert(choiceID).inserted, let point = scenario.choicePoints.first(where: { $0.id == command.target }),
                              let option = point.options.first(where: { $0.id == command.value }) else { throw SessionError.invalidCommand }
                        // Use the same reviewed choice semantics, with the actual submitted option.
                        var chosen = point; chosen.defaultOptionID = option.id
                        run.input.choices[point.id] = option.id
                        try run.choose(chosen)
                    case "assignHelper":
                        guard let personID=command.target,let person=run.household.people.firstIndex(where:{$0.id==personID}),let helperID=command.value,
                            helperID != personID,run.household.people.contains(where:{$0.id==helperID}) else {throw SessionError.invalidCommand}
                        run.household.people[person].helperPersonID=helperID
                    case "contact":
                        guard let contactID=command.target,run.household.contacts.contains(where:{$0.id==contactID && $0.isComplete}) else {throw SessionError.invalidCommand}
                        run.flags.insert("simulatedContact.\(contactID)")
                    case "unsupported":
                        run.flags.insert("unsupportedAction.\(commit.id)")
                    case "moveTo":
                        guard let personID = command.target, let p = run.household.people.firstIndex(where: { $0.id == personID }),
                              let dest = command.value, let home = run.home else { throw SessionError.invalidCommand }
                        let person = run.household.people[p]
                        let route = EgressPlanner().plan(RouteRequest(personID: personID, startSpaceID: run.startSpace(for: person), mobility: run.mobility(for: person),
                            exclusions: ScenarioExclusions(blockedSpaceIDs: run.spatialState?.affectedSpaceIDs ?? [], blockedPortalIDs: run.spatialState?.affectedPortalIDs ?? []), purpose: .helperReach, destinationSpaceID: dest), in: home)
                        run.currentRoutes[personID] = route
                        if route.primary != nil {
                            run.household.people[p].sleepingSpaceID = dest
                            var options = run.input.effectiveSpatialOptions
                            options.startingSpaceIDs[personID] = dest
                            run.input.spatialOptions = options
                            run.currentRoutes[personID] = EgressPlanner().plan(RouteRequest(personID:personID,startSpaceID:dest,mobility:run.mobility(for:person),exclusions:route.request.exclusions),in:home)
                        }
                    default: throw SessionError.invalidCommand
                    }
                    try supplies?.synchronize(&run)
                    run.emit("user.\(commit.id)", title: "simulation.user.\(command.kind)", severity: .info, rule: "session.user/1", causedBy: nil, sources: [])
                    try run.reevaluate(trigger: run.events.last?.id, emit: true)
                } else {
                    switch command.kind {
                    case "schedule":
                        guard let profile = command.target, scenario.events.contains(where: { $0.id == profile }), let t = command.minute,
                              t >= run.minute, t <= scenario.durationMinutes, scheduled < 32, pending.count < 8, !scheduledIDs.contains(profile) else { throw SessionError.budget }
                        pending.append(command); scheduled += 1; scheduledIDs.insert(profile)
                    case "advance":
                        guard let until = command.minute, until >= run.minute, until <= scenario.durationMinutes else { throw SessionError.invalidCommand }
                        let priorities=Dictionary(uniqueKeysWithValues:scenario.events.map{($0.id,$0.priority)})
                        pending.sort { a,b in
                            let left:(Int,Int,String)=(a.minute ?? 0,priorities[a.target ?? ""] ?? 0,a.target ?? "")
                            let right:(Int,Int,String)=(b.minute ?? 0,priorities[b.target ?? ""] ?? 0,b.target ?? "")
                            return left<right
                        }
                        var boundary = min(until,supplies?.nextExpiryMinute(after:run.minute) ?? until)
                        var depletion = run.nextDepletion()
                        if let dep = depletion, dep.minute <= boundary { boundary = dep.minute }
                        while let event = pending.first, let t = event.minute, t <= boundary {
                            if let dep=depletion,dep.minute<=t {break}
                            pending.removeFirst(); run.advance(to: t)
                            try supplies?.synchronize(&run)
                            guard var authored = scenario.events.first(where: { $0.id == event.target }) else { throw SessionError.invalidCommand }
                            authored.minute = t
                            guard Applicability.holds(authored.when, household: run.household, home: run.home, variants: run.effectiveVariants) else { throw SessionError.invalidCommand }
                            try run.apply(authored)
                            try supplies?.synchronize(&run)
                            if supplies != nil {try run.reevaluate(trigger:run.events.last?.id,emit:true)}
                            depletion = run.nextDepletion()
                            if let dep = depletion, dep.minute < boundary { boundary = dep.minute }
                        }
                        let simultaneous = run.depletionSchedule().filter { $0.minute == boundary }
                        run.advance(to: boundary)
                        try supplies?.synchronize(&run)
                        // Depletion at the boundary is computed from the same ledger, never set by the director.
                        for dep in simultaneous { try run.handleDepletion(dep.resource) }
                        try run.reevaluate(trigger: run.events.last?.id, emit: true)
                    case "requestDecision": break
                    case "finish": ended = true
                    default: throw SessionError.invalidCommand
                    }
                }
            }
        }
        run.snapshot()
        let snapshot = run.snapshots.last!
        let routes = run.currentRoutes.keys.sorted().compactMap { run.currentRoutes[$0] }
        let digest = StableDigest.of(try DryRunJSON.encoder().encode(DigestState(initial: initial, commits: commits, snapshot: snapshot, routes: routes, inventory:supplies?.state, inventorySeed:inventory)))
        return SessionReceipt(sessionID: id, revision: revision, eventSequence: run.events.count, contextDigest: digest,
                              snapshot: snapshot, routes: routes, events: run.events, pending: pending, finished: ended, inventory:supplies?.state)
    }
    public func fallback() -> SessionCommit {
        SessionCommit(id: "fallback-\(revision)", actor: "director", baseRevision: revision, commands: [SessionCommand(kind: "requestDecision")])
    }
}
private struct DigestState: Encodable { var initial: RehearsalInput; var commits: [SessionCommit]; var snapshot: SimulationSnapshot; var routes: [RouteResult];var inventory:ExerciseInventory?;var inventorySeed:SessionInventorySeed? }
public enum StableDigest {
    /// Stable non-cryptographic replay identity; gateway uses SHA-256 for authorization/token binding.
    public static func of(_ data: Data) -> String {
        var h: UInt64 = 14695981039346656037
        for b in data { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}
