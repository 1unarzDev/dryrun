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
    public var quantityLiters:Double?
    public init(kind: String, target: String? = nil, value: String? = nil, minute: Int? = nil, hazard:HazardKind?=nil,durationMinutes:Int?=nil,quantityLiters:Double?=nil) {
        self.kind = kind; self.target = target; self.value = value; self.minute = minute;self.hazard=hazard;self.durationMinutes=durationMinutes;self.quantityLiters=quantityLiters
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
    public var assistance:[ExerciseAssistance]?
    public var experience:HazardExperience?
}

/// Serializable event-sourced session. Replay executes existing RunState, allocator, hazard and route rules.
/// Replay is deliberately local and bounded (128 commits); no provider call or speculative default choice.
public enum DependencyInspectionPolicy:String,Codable,Sendable {case recordedAccess = "dryrun.dependencies/2"}

public struct SimulationSession: Codable, Sendable {
    public let contractVersion: String
    public let id: String
    public let initial: RehearsalInput
    public let inventory:SessionInventorySeed?
    public let concernSeed:ConcernExerciseSeed?
    public let dependencyPolicy:DependencyInspectionPolicy?
    public let directorPolicy:DirectorPolicy?
    public let mechanicsVersion:String?
    public private(set) var commits: [SessionCommit]
    public init(id: String, initial: RehearsalInput, inventory:SessionInventorySeed?=nil,directorPolicy:DirectorPolicy?=nil,concernSeed:ConcernExerciseSeed?=nil,dependencyPolicy:DependencyInspectionPolicy? = .recordedAccess,mechanicsVersion:String?=nil) {
        self.mechanicsVersion=mechanicsVersion
        self.contractVersion = "dryrun.ai/1"; self.id = id; self.initial = initial; self.inventory=inventory;self.directorPolicy=directorPolicy;self.concernSeed=concernSeed; self.dependencyPolicy=dependencyPolicy; self.commits = []
    }
    /// New native exercises freeze an explicit policy. The initializer also decodes legacy snapshots
    /// whose absent policy must keep their historical replay behavior.
    public static func initialize(id:String,initial:RehearsalInput,library:ScenarioLibrary,inventory:SessionInventorySeed?=nil,concernSeed:ConcernExerciseSeed?=nil)throws->SimulationSession {
        guard let scenario=library.scenario(initial.scenarioID),scenario.version==initial.scenarioVersion else {throw SessionError.invalidCommand}
        let session=SimulationSession(id:id,initial:initial,inventory:inventory,directorPolicy:.reviewed(scenario),concernSeed:concernSeed,mechanicsVersion:HazardExperience.version)
        _=try session.query(library:library)
        return session
    }
    public var effectiveVariants:[String] {initial.variants + (mechanicsVersion == nil ? []:["adaptive-mechanics"])}
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
    /// Call only on an authoritatively reloaded durable session after a lost acknowledgement.
    /// An absent result is not permission to retry if durable storage itself was unavailable.
    public func reconcileDurableCommit(_ proposal: SessionCommit, library: ScenarioLibrary) throws -> DurableCommitResolution {
        let current = try query(library: library)
        guard let recorded = commits.first(where: { $0.id == proposal.id }) else {
            return .init(status: .absent, commitID: proposal.id, acceptedRevision: nil, current: current)
        }
        guard recorded == proposal else { throw SessionError.duplicate }
        return .init(status: .committed, commitID: proposal.id, acceptedRevision: recorded.baseRevision + 1, current: current)
    }
    public func query(library: ScenarioLibrary) throws -> SessionReceipt {
        guard commits.count<=128, let scenario = library.scenario(initial.scenarioID), scenario.version == initial.scenarioVersion else { throw SessionError.invalidCommand }
        guard mechanicsVersion.map({HazardExperience.supportedVersions.contains($0)}) ?? true else {throw SessionError.invalidCommand}
        try directorPolicy?.validate(in:scenario)
        try concernSeed?.validate(home:initial.home,scenarioID:initial.scenarioID)
        let horizon=min(scenario.durationMinutes,directorPolicy?.schedulingHorizonMinutes ?? scenario.durationMinutes)
        var directorState=directorPolicy.map{_ in DirectorRuntimeState(activeIncidentCount:0)}
        let prepared = InterventionApplier.apply(initial.interventions, household: initial.household, home: initial.home)
        var run = RunState(scenario: scenario, input: initial, household: prepared.0, home: prepared.1, planner:ConcernRoutePlanner(portalIDs:concernSeed?.selectedPortalIDs ?? []))
        if let mechanicsVersion {run.hazardProgress=HazardProgress(scenario.hazard,version:mechanicsVersion,roomIDs:run.home?.spaces.map(\.id) ?? [],roomCoverageUnknown:[.windowOrPortableAC,.evaporative].contains(run.household.housing.cooling))}
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
                    case "accompanyEscape","accompanyShelter", "identifyGap", "escape", "accountOutside", "reachHigherRefuge","reachShelter", "leaveEarly", "heatedAlternative", "cooledAlternative", "warmLayers", "reduceSolarGain":
                        try run.applyHazardAction(command)
                    case "useWater":
                        guard mechanicsVersion != nil,scenario.hazard == .waterOutage else {throw SessionError.invalidCommand}
                        if command.target == "tap" {try run.useTapWater(command)}
                        else if supplies != nil {try supplies!.consumeWater(command,run:&run)}
                        else {try run.useRecordedWater(command)}
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
                              Applicability.holds(point.when, household: run.household, home: run.home, variants: run.effectiveVariants),
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
                        guard !((run.hazardProgress?.outside.contains(command.target ?? "")) ?? false) else {throw SessionError.invalidCommand}
                        guard let personID = command.target, let p = run.household.people.firstIndex(where: { $0.id == personID }),
                              let dest = command.value, let home = run.home, !run.isOutside(personID) else { throw SessionError.invalidCommand }
                        let person = run.household.people[p]
                        let currentObjective=run.currentRoutes[personID]?.request
                        let objective=(currentObjective?.purpose == .interiorShelter || currentObjective?.purpose == .higherRefuge) ? currentObjective : nil
                        let route = run.planner.plan(RouteRequest(personID: personID, startSpaceID: run.startSpace(for: person), mobility: run.mobility(for: person),
                            exclusions: ScenarioExclusions(blockedSpaceIDs: run.spatialState?.affectedSpaceIDs ?? [], blockedPortalIDs: run.spatialState?.affectedPortalIDs ?? []), purpose: .helperReach, destinationSpaceID: dest), in: home)
                        run.currentRoutes[personID] = route
                        if mechanicsVersion != nil,route.primary == nil {throw SessionError.invalidCommand}
                        if route.primary != nil {
                            run.household.people[p].sleepingSpaceID = dest
                            var options = run.input.effectiveSpatialOptions
                            options.startingSpaceIDs[personID] = dest
                            run.input.spatialOptions = options
                            run.occupants[personID] = .init(personID: personID, currentSpaceID: dest,
                                shelteredSpaceID: objective?.purpose == .interiorShelter && objective?.destinationSpaceID == dest ? dest : nil)
                            run.currentRoutes[personID] = run.planner.plan(RouteRequest(personID:personID,startSpaceID:dest,mobility:run.mobility(for:person),exclusions:route.request.exclusions,
                                purpose:objective?.purpose ?? .outdoorEgress,destinationSpaceID:objective?.destinationSpaceID),in:home)
                        } else if let objective {
                            // An infeasible move does not turn a recorded shelter/refuge objective
                            // into the attempted helper-reach route or an exterior escape overlay.
                            run.currentRoutes[personID]=run.planner.plan(objective,in:home)
                        }
                    default: throw SessionError.invalidCommand
                    }
                    try supplies?.synchronize(&run)
                    let actionEventID=run.emit("user.\(commit.id)", title: "simulation.user.\(command.kind)", severity: .info, rule: "session.user/1", causedBy: nil, sources: [])
                    run.hazardProgress?.trace.append(.init(kind:command.kind,subjectIDs:[command.target,command.value].compactMap{$0},eventID:actionEventID))
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
        if let concernSeed,var scene=run.spatialState {
            scene.affectedPortalIDs=Array(Set(scene.affectedPortalIDs+concernSeed.selectedPortalIDs)).sorted()
            scene.assumption += " Additional user-selected opening exclusions come from a reviewed concern; this exercise does not project image pixels or certify the obstruction."
            run.spatialState=scene
        }
        if directorPolicy != nil {run.spatialState?.routes=run.currentRoutes.keys.sorted().compactMap{run.currentRoutes[$0]}}
        let assistance=directorPolicy != nil && (commits.contains(where:{$0.commands.contains(where:{$0.kind=="assignHelper"})}) || (run.scenario.hazard == .homeFire && run.hazardProgress?.supportsEscapeAccompaniment==true)) ? run.sessionAssistance() : nil
        run.snapshot()
        let snapshot = run.snapshots.last!
        let routes = run.currentRoutes.keys.sorted().compactMap { run.currentRoutes[$0] }
        let digest = StableDigest.of(try DryRunJSON.encoder().encode(DigestState(initial: initial, commits: commits, snapshot: snapshot, routes: routes, inventory:supplies?.state, inventorySeed:inventory,directorPolicy:directorPolicy,closedPortalIDs:closedPortals.isEmpty ? nil : closedPortals.sorted(),assistance:assistance,concernSeed:concernSeed,mechanicsVersion:mechanicsVersion)))
        var experience=run.experience()
        if ["dryrun.hazard-mechanics/4","dryrun.hazard-mechanics/5"].contains(mechanicsVersion ?? ""),let ledger=supplies,scenario.hazard == .flashFlood,!run.relocated {
            // Export the actual item/person/location combinations, not a generic
            // retrieve-supplies label that teleports stock from another room.
            // Timing consequence from the same ledger: stock left in an excluded space versus stock
            // a household member committed to carry or move before that stage.
            let affected=Set(run.spatialState?.affectedSpaceIDs ?? [])
            let lost=ledger.state.items.filter{$0.accessible==false && $0.carrierPersonID==nil && $0.locationID.map(affected.contains)==true}.map(\.id).sorted()
            let kept=ledger.state.items.filter{$0.accessible==true && ($0.carrierPersonID != nil || $0.locationID != ledger.sources[$0.id]?.locationID)}.map(\.id).sorted()
            if mechanicsVersion == HazardExperience.version,let next=experience?.debrief.first?.nextActionID {
                if !lost.isEmpty {experience?.debrief.append(.init(kind:"floodSupplyAccessLost",subjectIDs:Array(lost.prefix(20)),eventIDs:[],nextActionID:"prep.floodPlan"))}
                if !kept.isEmpty {experience?.debrief.append(.init(kind:"floodSupplyKeptAccessible",subjectIDs:Array(kept.prefix(20)),eventIDs:[],nextActionID:next))}
            }
            for item in ledger.state.items {
                for person in run.household.people {
                    let take=SessionCommand(kind:"takeSupply",target:item.id,value:person.id)
                    var probe=ledger
                    if (try? probe.apply(take,run:run)) != nil {experience?.feasibleCommands?.append(take)}
                }
                if let carrier=item.carrierPersonID,let person=run.household.people.first(where:{$0.id==carrier}) {
                    let transfer=SessionCommand(kind:"transferSupply",target:item.id,value:run.startSpace(for:person))
                    var probe=ledger
                    if (try? probe.apply(transfer,run:run)) != nil {experience?.feasibleCommands?.append(transfer)}
                }
            }
        }
        if let ledger=supplies, scenario.hazard == .waterOutage {
            experience?.feasibleCommands?.removeAll{$0.kind=="useWater" && $0.target=="recordedStored"}
            for item in ledger.state.items where item.category=="water" && item.accessible==true {
                for activity in ["drink","prepareFood","hygiene"] {
                    let command=SessionCommand(kind:"useWater",target:item.id,value:activity,quantityLiters:0.25)
                    var probe=ledger,probeRun=run
                    if (try? probe.consumeWater(command,run:&probeRun)) != nil {experience?.feasibleCommands?.append(command)}
                }
            }
        }
        if let current=experience {experience=Self.annotateSupportedActions(current,run:run)}
        return SessionReceipt(sessionID: id, revision: revision, eventSequence: run.events.count, contextDigest: digest,
                              snapshot: snapshot, routes: routes, events: run.events, pending: pending, finished: ended, inventory:supplies?.state,directorState:directorState,closedPortalIDs:closedPortals.isEmpty ? nil : closedPortals.sorted(),assistance:assistance,experience:experience)
    }
    /// Explicit limitation when the current state supports no hazard action, distinct from a
    /// completed educational objective. Never offers an unsupported action to fill the gap.
    static func annotateSupportedActions(_ experience:HazardExperience,run:RunState)->HazardExperience {
        // State-derived, so a director finish does not change the final debrief facts.
        guard experience.mechanicsVersion == HazardExperience.version else {return experience}
        var result=experience
        let people=Set(run.household.people.map(\.id))
        let complete:Bool
        switch run.scenario.hazard {
        case .homeFire:complete = !people.isEmpty && people.isSubset(of:Set(experience.outsidePersonIDs)) && people.isSubset(of:Set(experience.accountedPersonIDs))
        case .tornado:complete = !people.isEmpty && people.isSubset(of:Set(experience.shelteredPersonIDs))
        case .flashFlood,.freezePowerLoss,.heatGridStrain:complete=experience.relocated
        case .waterOutage:complete=false
        }
        let next=experience.debrief.first?.nextActionID ?? "prep.plan"
        let actionable=(experience.feasibleCommands ?? []).contains{$0.kind != "identifyGap"}
        if complete {result.debrief.append(.init(kind:"objectiveReached",subjectIDs:Array(people.sorted().prefix(20)),eventIDs:[],nextActionID:next))}
        else if !actionable {result.debrief.append(.init(kind:"noSupportedHazardAction",subjectIDs:Array(experience.openGapIDs.prefix(20)),eventIDs:[],nextActionID:next))}
        return result
    }
    /// State-preserving offline continuation. No default user action, resource reset or authored restart.
    public func fallback(library:ScenarioLibrary)throws->SessionCommit {
        let receipt=try query(library:library)
        guard !receipt.finished,let scenario=library.scenario(initial.scenarioID) else {throw SessionError.finished}
        // A committed departure ended this modeled home boundary. Losing the
        // provider must not manufacture a trapped-home sequel or advance queued
        // home events at an unmodeled destination. Historical commits still replay
        // unchanged; this selects only the next explicit fallback proposal.
        if ["dryrun.hazard-mechanics/4","dryrun.hazard-mechanics/5"].contains(mechanicsVersion ?? ""),
           receipt.experience?.relocated == true,
           [.flashFlood,.freezePowerLoss,.heatGridStrain].contains(scenario.hazard) {
            return SessionCommit(id:"fallback-\(revision)",actor:"director",baseRevision:revision,commands:[.init(kind:"finish")])
        }
        if mechanicsVersion == "dryrun.hazard-mechanics/5",let experience=receipt.experience,!initial.household.people.isEmpty {
            let people=Set(initial.household.people.map(\.id))
            let escapedAndAccounted=scenario.hazard == .homeFire && people.isSubset(of:Set(experience.outsidePersonIDs)) && people.isSubset(of:Set(experience.accountedPersonIDs))
            let arrivedAtShelter=scenario.hazard == .tornado && people.isSubset(of:Set(experience.shelteredPersonIDs))
            // End the educational objective, never declare an official all-clear,
            // structural safety or post-arrival equipment continuity. Continuing
            // every completed objective into the outage schedule erases its lesson.
            if escapedAndAccounted || arrivedAtShelter {
                return SessionCommit(id:"fallback-\(revision)",actor:"director",baseRevision:revision,commands:[.init(kind:"finish")])
            }
        }
        if mechanicsVersion == nil || receipt.directorState?.awaitingUserAction == true {return fallback()}
        var commands:[SessionCommand]=[]
        if let next=receipt.pending.first?.minute {
            commands=[.init(kind:"advance",minute:next)]
        } else {
            let used=Set(commits.flatMap(\.commands).filter{["schedule","startIncident","advanceIncident"].contains($0.kind)}.compactMap(\.target))
            let candidates=scenario.events.filter{!used.contains($0.id) && $0.rule != RuleID.checkpoint && $0.rule != RuleID.note && Applicability.holds($0.when,household:initial.household,home:initial.home,variants:effectiveVariants)}.sorted{($0.minute,$0.priority,$0.id)<($1.minute,$1.priority,$1.id)}
            for profile in candidates {
                let minute=max(receipt.snapshot.simMinute,profile.minute)
                let proposal=SessionCommit(id:"fallback-\(revision)",actor:"director",baseRevision:revision,commands:[.init(kind:"schedule",target:profile.id,minute:minute),.init(kind:"advance",minute:minute),.init(kind:"requestDecision")])
                if (try? preview(proposal,library:library)) != nil {return proposal}
            }
        }
        commands.append(.init(kind:"requestDecision"))
        return SessionCommit(id:"fallback-\(revision)",actor:"director",baseRevision:revision,commands:commands)
    }
    public func fallback() -> SessionCommit {
        SessionCommit(id: "fallback-\(revision)", actor: "director", baseRevision: revision, commands: [SessionCommand(kind: "requestDecision")])
    }
}
private struct DigestState: Encodable { var initial: RehearsalInput; var commits: [SessionCommit]; var snapshot: SimulationSnapshot; var routes: [RouteResult];var inventory:ExerciseInventory?;var inventorySeed:SessionInventorySeed?;var directorPolicy:DirectorPolicy?;var closedPortalIDs:[String]?;var assistance:[ExerciseAssistance]?;var concernSeed:ConcernExerciseSeed?;var mechanicsVersion:String? }
public enum StableDigest {
    /// Stable non-cryptographic replay identity; gateway uses SHA-256 for authorization/token binding.
    public static func of(_ data: Data) -> String {
        var h: UInt64 = 14695981039346656037
        for b in data { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}

public struct DurableCommitResolution: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case committed, absent }
    public var status: Status
    public var commitID: String
    public var acceptedRevision: Int?
    public var current: SessionReceipt
}
