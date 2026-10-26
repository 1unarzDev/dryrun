import Foundation

public enum SessionError: String, Error, Codable, Sendable { case stale, duplicate, invalidCommand, budget, finished, persistence }

/// Flat transport command. Actor permissions are enforced by the reducer, never by presentation.
public struct SessionCommand: Codable, Hashable, Sendable {
    public var kind: String
    public var target: String?
    public var value: String?
    public var minute: Int?
    public var hazard:HazardKind?
    public var durationMinutes:Int?
    public init(kind: String, target: String? = nil, value: String? = nil, minute: Int? = nil, hazard:HazardKind?=nil,durationMinutes:Int?=nil) {
        self.kind = kind; self.target = target; self.value = value; self.minute = minute;self.hazard=hazard;self.durationMinutes=durationMinutes
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
    public var directorState:DirectorRuntimeState?
    public var closedPortalIDs:[String]?
}

/// Serializable event-sourced session. Replay executes existing RunState, allocator, hazard and route rules.
/// Replay is deliberately local and bounded (128 commits); no provider call or speculative default choice.
public struct SimulationSession: Codable, Sendable {
    public let contractVersion: String
    public let id: String
    public let initial: RehearsalInput
    public let inventory:SessionInventorySeed?
    public let directorPolicy:DirectorPolicy?
    public private(set) var commits: [SessionCommit]
    public init(id: String, initial: RehearsalInput, inventory:SessionInventorySeed?=nil,directorPolicy:DirectorPolicy?=nil) {
        self.contractVersion = "dryrun.ai/1"; self.id = id; self.initial = initial; self.inventory=inventory;self.directorPolicy=directorPolicy; self.commits = []
    }
    /// New native exercises freeze an explicit policy. The initializer also decodes legacy snapshots
    /// whose absent policy must keep their historical replay behavior.
    public static func initialize(id:String,initial:RehearsalInput,library:ScenarioLibrary,inventory:SessionInventorySeed?=nil)throws->SimulationSession {
        guard let scenario=library.scenario(initial.scenarioID),scenario.version==initial.scenarioVersion else {throw SessionError.invalidCommand}
        let session=SimulationSession(id:id,initial:initial,inventory:inventory,directorPolicy:.reviewed(scenario))
        _=try session.query(library:library)
        return session
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
        try directorPolicy?.validate(in:scenario)
        let horizon=min(scenario.durationMinutes,directorPolicy?.schedulingHorizonMinutes ?? scenario.durationMinutes)
        var directorState=directorPolicy.map{_ in DirectorRuntimeState(activeIncidentCount:0)}
        let prepared = InterventionApplier.apply(initial.interventions, household: initial.household, home: initial.home)
        var run = RunState(scenario: scenario, input: initial, household: prepared.0, home: prepared.1, planner: EgressPlanner())
        var supplies=try inventory.map(SessionSupplyLedger.init)
        try supplies?.synchronize(&run)
        try SessionTransitionReducer.initialize(&run)
        var pending: [SessionCommand] = [], ended = false, scheduled = 0
        var scheduledIDs=Set<String>()
        var chosenIDs=Set<String>()
        var inputIDs=Set<String>()
        var closedPortals=Set<String>()
        for (index, commit) in commits.enumerated() {
            guard !commit.id.isEmpty,!commit.commands.isEmpty,commit.commands.count<=8,inputIDs.insert(commit.id).inserted, commit.actor == "user" || commit.actor == "director" else {throw SessionError.invalidCommand}
            guard commit.baseRevision == index, !ended else { throw SessionError.finished }
            for (commandIndex,command) in commit.commands.enumerated() {
                guard !ended else {throw SessionError.finished}
                if commit.actor == "user" {
                    directorState?.awaitingUserAction=false
                    switch command.kind {
                    case "finish":
                        ended=true;directorState?.activeIncidentCount=0
                    case "takeSupply", "transferSupply":
                        guard supplies != nil else {throw SessionError.invalidCommand}
                        try supplies!.apply(command,run:run)
                    case "closeDoor":
                        guard let portalID=command.target,let portal=run.home?.portal(portalID),portal.kind == .door,
                              portal.verification == .verified,portal.operable.confirmedValue==true,
                              let person=run.household.people.first(where:{$0.id==command.value}) else {throw SessionError.invalidCommand}
                        let start=run.startSpace(for:person)
                        guard (portal.sideA == .space(start) || portal.sideB == .space(start)),
                              run.spatialState?.affectedSpaceIDs.contains(start) != true,
                              run.spatialState?.affectedPortalIDs.contains(portalID) != true else {throw SessionError.invalidCommand}
                        // An operable closed door remains passable. No unvalidated spread-delay credit.
                        closedPortals.insert(portalID)
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
                        run.interventionChoices.removeValue(forKey:point.id)
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
                    guard directorState?.awaitingUserAction != true || command.kind=="requestDecision" else {throw SessionError.invalidCommand}
                    switch command.kind {
                    case "schedule", "startIncident", "advanceIncident":
                        guard let profileID=command.target,let profile=scenario.events.first(where:{$0.id==profileID}),let t=command.minute,
                              t>=run.minute,t<=horizon,scheduled<(directorPolicy?.eventBudget ?? 32),pending.count<(directorPolicy?.maximumPendingEvents ?? 8),!scheduledIDs.contains(profileID) else {throw SessionError.budget}
                        if let policy=directorPolicy {
                            guard policy.permittedHazardFamilies.contains(scenario.hazard),Applicability.holds(profile.when,household:run.household,home:run.home,variants:run.effectiveVariants) else {throw SessionError.invalidCommand}
                            try policy.validateQueue(pending+[command],after:directorState?.stageID,scenario:scenario)
                            if command.kind=="startIncident" {
                                try SessionTransitionReducer.validateIncidentOrigin(command,profile:profile,run:run)
                            } else if command.value != nil || command.hazard != nil && command.hazard != scenario.hazard {throw SessionError.invalidCommand}
                        } else if command.kind != "schedule" || command.hazard != nil {throw SessionError.invalidCommand}
                        pending.append(command);scheduled += 1;scheduledIDs.insert(profileID);directorState?.scheduledEventCount=scheduled
                    case "advance", "waitUntil":
                        try SessionTransitionReducer.advance(command,run:&run,pending:&pending,supplies:&supplies,
                            directorState:&directorState,horizon:horizon,policyEnabled:directorPolicy != nil)
                    case "requestDecision":
                        guard directorPolicy==nil || commandIndex==commit.commands.count-1 else {throw SessionError.invalidCommand}
                        directorState?.awaitingUserAction=true
                    case "finish": ended = true;directorState?.activeIncidentCount=0
                    default: throw SessionError.invalidCommand
                    }
                }
            }
        }
        if directorPolicy != nil {run.spatialState?.routes=run.currentRoutes.keys.sorted().compactMap{run.currentRoutes[$0]}}
        run.snapshot()
        let snapshot = run.snapshots.last!
        let routes = run.currentRoutes.keys.sorted().compactMap { run.currentRoutes[$0] }
        let digest = StableDigest.of(try DryRunJSON.encoder().encode(DigestState(initial: initial, commits: commits, snapshot: snapshot, routes: routes, inventory:supplies?.state, inventorySeed:inventory,directorPolicy:directorPolicy,closedPortalIDs:closedPortals.isEmpty ? nil : closedPortals.sorted())))
        return SessionReceipt(sessionID: id, revision: revision, eventSequence: run.events.count, contextDigest: digest,
                              snapshot: snapshot, routes: routes, events: run.events, pending: pending, finished: ended, inventory:supplies?.state,directorState:directorState,closedPortalIDs:closedPortals.isEmpty ? nil : closedPortals.sorted())
    }
    public func fallback() -> SessionCommit {
        SessionCommit(id: "fallback-\(revision)", actor: "director", baseRevision: revision, commands: [SessionCommand(kind: "requestDecision")])
    }
}
private struct DigestState: Encodable { var initial: RehearsalInput; var commits: [SessionCommit]; var snapshot: SimulationSnapshot; var routes: [RouteResult];var inventory:ExerciseInventory?;var inventorySeed:SessionInventorySeed?;var directorPolicy:DirectorPolicy?;var closedPortalIDs:[String]? }
public enum StableDigest {
    /// Stable non-cryptographic replay identity; gateway uses SHA-256 for authorization/token binding.
    public static func of(_ data: Data) -> String {
        var h: UInt64 = 14695981039346656037
        for b in data { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}
