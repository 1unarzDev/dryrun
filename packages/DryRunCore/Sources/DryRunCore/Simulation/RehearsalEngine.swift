import Foundation

public enum RehearsalError: Error, Equatable, Sendable {
    case unknownScenario(String)
    case scenarioVersionMismatch(expected: String, actual: String)
    case invalidChoice(choiceID: String, optionID: String)
    case nonConvergentDependencies
    case eventLimitExceeded
}

/// Deterministic discrete-event rehearsal engine.
///
/// Ordering: simulated minute, then declared priority, then stable event ID. Resource depletion
/// events (computed from current draw) are processed before authored events at the same minute.
/// After every event the dependency model is re-evaluated to a fixed point and service changes are
/// emitted as derived events with their evidence chain. No wall-clock time, randomness, or hashing
/// order affects results; `seed` is carried for future authored variation and recorded in the input.
public struct RehearsalEngine: Sendable {
    public static let engineVersion = "cascade-engine/1"
    public static let maxEvents = 5_000

    public let library: ScenarioLibrary
    public let planner: EgressPlanning
    public let actions: ActionCatalog

    public init(library: ScenarioLibrary, planner: EgressPlanning, actions: ActionCatalog = .builtIn) {
        self.library = library
        self.planner = planner
        self.actions = actions
    }

    public func run(_ input: RehearsalInput) throws -> RehearsalResult {
        guard let scenario = library.scenario(input.scenarioID) else { throw RehearsalError.unknownScenario(input.scenarioID) }
        guard scenario.version == input.scenarioVersion else {
            throw RehearsalError.scenarioVersionMismatch(expected: scenario.version, actual: input.scenarioVersion)
        }
        // Interventions apply to a simulation COPY. `input` is a value and is never mutated.
        let (household, home) = InterventionApplier.apply(input.interventions, household: input.household, home: input.home)
        var run = RunState(scenario: scenario, input: input, household: household, home: home, planner: planner)
        try run.execute()
        let recs = RecommendationRanker.rank(ActionRules.evaluate(run.summary(), catalog: actions))
        return RehearsalResult(input: input, events: run.events, snapshots: run.snapshots, decisions: run.decisions,
                               routes: run.routes, recommendations: recs, unknowns: run.unknowns.sorted(),
                               engineVersion: Self.engineVersion)
    }

    /// Counterfactual replay: same seed, scenario/content versions, choices, variants, and schedule;
    /// only `intervention` is added. The baseline input is not modified.
    public func compare(_ baseline: RehearsalInput, applying intervention: Intervention) throws -> RehearsalComparison {
        var modifiedInput = baseline
        if !modifiedInput.interventions.contains(intervention) { modifiedInput.interventions.append(intervention) }
        let base = try run(baseline)
        let mod = try run(modifiedInput)
        return RehearsalComparison(baseline: base, modified: mod, intervention: intervention, diff: RehearsalDiffer.diff(base, mod))
    }
}

// MARK: - Run state

/// Facts gathered during a run, consumed by `ActionRules`.
public struct RunSummary: Sendable {
    public var scenario: ScenarioDefinition
    public var household: HouseholdProfile
    public var home: HomeModel
    public var unmetEver: Set<String>
    public var unknowns: Set<String>
    public var flags: Set<String>
    /// Event IDs that caused each unmet requirement (first occurrence).
    public var causes: [String: [String]]
    public var finalServices: [String: ServiceState]
    public var everUnavailable: Set<String>
}

struct ScheduledItem {
    enum Kind { case event(AuthoredEvent), choice(ChoicePoint) }
    var minute: Int
    var priority: Int
    var id: String
    var kind: Kind
}

struct RunState {
    let scenario: ScenarioDefinition
    let input: RehearsalInput
    let household: HouseholdProfile
    let home: HomeModel
    let planner: EgressPlanning
    let model: DependencyModel
    let allocator = BackupAllocator()

    var minute = 0
    var external = Svc.externalDefaults
    var services: [String: ServiceState] = [:]
    var advisory: WaterAdvisory?
    var relocated = false
    var boilingTapWater = false

    // Resources (nil = unknown; never invented)
    var storedWater: Double?
    let initialStoredWater: Double?
    var backupEnergy: [String: Double?] = [:]
    let initialBackupEnergy: [String: Double?]
    var deviceRuntime: [String: Double?] = [:]   // hours of documented runtime remaining, on backup
    var handsetHours: Double?
    let fullHandsetHours: Double?
    var powerBankCharges: Double?
    var drain: [String: Double?] = [:]
    var assignments: [String: BackupAssignment] = [:]

    var events: [SimulationEvent] = []
    var snapshots: [SimulationSnapshot] = []
    var decisions: [DecisionPoint] = []
    var routes: [RouteResult] = []
    var unknowns: Set<String> = []
    var unmetEver: Set<String> = []
    var causes: [String: [String]] = [:]
    var flags: Set<String> = []
    var everUnavailable: Set<String> = []
    var currentUnmet: Set<String> = []
    var stickyUnmet: Set<String> = []
    var idCounts: [String: Int] = [:]
    var currentRoutes: [String: RouteResult] = [:]
    var onBackup: Set<String> = []
    var phaseID: String

    init(scenario: ScenarioDefinition, input: RehearsalInput, household: HouseholdProfile, home: HomeModel, planner: EgressPlanning) {
        self.scenario = scenario; self.input = input; self.household = household; self.home = home; self.planner = planner
        self.model = DependencyModel.build(household: household)
        self.storedWater = household.supplies.storedWaterGallons.confirmedValue
        self.initialStoredWater = storedWater
        for b in household.backupPower { backupEnergy[b.id] = .some(b.usableEnergyWh.confirmedValue) }
        self.initialBackupEnergy = backupEnergy
        for eq in household.equipment { deviceRuntime[eq.id] = .some(eq.documentedBackupRuntimeHours.confirmedValue) }
        let c = household.communications
        self.handsetHours = c.handsetRuntimeHours.value
        self.fullHandsetHours = c.handsetRuntimeHours.value
        self.powerBankCharges = c.powerBankCharges.confirmedValue
        self.phaseID = scenario.phases.first?.id ?? "main"
    }

    // MARK: Execution

    mutating func execute() throws {
        noteStaticUnknowns()
        try reevaluate(trigger: nil, emit: false)
        snapshot()

        var schedule: [ScheduledItem] = []
        for e in scenario.events where Applicability.holds(e.when, household: household, home: home, variants: input.variants) {
            schedule.append(ScheduledItem(minute: e.minute, priority: e.priority, id: e.id, kind: .event(e)))
        }
        for c in scenario.choicePoints where Applicability.holds(c.when, household: household, home: home, variants: input.variants) {
            schedule.append(ScheduledItem(minute: c.minute, priority: 100, id: c.id, kind: .choice(c)))
        }
        schedule.sort { ($0.minute, $0.priority, $0.id) < ($1.minute, $1.priority, $1.id) }

        var idx = 0
        var guardCount = 0
        while true {
            guardCount += 1
            if guardCount > RehearsalEngine.maxEvents { throw RehearsalError.eventLimitExceeded }
            let next = idx < schedule.count ? schedule[idx] : nil
            if let dep = nextDepletion(), dep.minute <= scenario.durationMinutes, next == nil || dep.minute <= next!.minute {
                advance(to: dep.minute)
                try handleDepletion(dep.resource)
                snapshot()
                continue
            }
            guard let item = next else { break }
            idx += 1
            advance(to: item.minute)
            switch item.kind {
            case .event(let e): try apply(e)
            case .choice(let c): try choose(c)
            }
            snapshot()
        }
        advance(to: max(minute, scenario.durationMinutes))
    }

    func summary() -> RunSummary {
        RunSummary(scenario: scenario, household: household, home: home, unmetEver: unmetEver, unknowns: unknowns,
                   flags: flags, causes: causes, finalServices: services, everUnavailable: everUnavailable)
    }

    // MARK: Time and resources

    var tapWaterUsable: Bool {
        let supplyOK = services[Svc.waterSupply] == .operational
        let safety = services[Svc.waterSafety] ?? .unknown
        return supplyOK && (safety == .operational || (safety == .degraded && boilingTapWater))
    }

    var homePowerUp: Bool { services[Svc.homePower] == .operational }

    /// Water drawn from storage per minute: CDC storage-planning baseline of 1 gal/person/day [S26],
    /// an exercise assumption, not a prescribed drinking volume. Pets' extra needs are not modelled (unknown).
    var waterDrawPerMinute: Double {
        guard !tapWaterUsable, !relocated else { return 0 }
        return Double(household.people.count) / 1440.0
    }

    var handsetDrawPerMinute: Double { (homePowerUp || relocated) ? 0 : 1.0 / 60.0 }

    func nextDepletion() -> (minute: Int, resource: String)? {
        var best: (Int, String)?
        func consider(_ amount: Double?, _ rate: Double, _ id: String) {
            guard let a = amount, a > 0, rate > 0 else { return }
            let t = minute + Int((a / rate).rounded(.up))
            if best == nil || (t, id) < (best!.0, best!.1) { best = (t, id) }
        }
        consider(storedWater, waterDrawPerMinute, "res.water.stored")
        consider(handsetHours, handsetDrawPerMinute, "res.handset.hours")
        for (sid, d) in drain.sorted(by: { $0.key < $1.key }) {
            if let rate = d, let e = backupEnergy[sid] ?? nil { consider(e, rate / 60.0, "res.backup.\(sid)") }
        }
        for (eid, r) in deviceRuntime.sorted(by: { $0.key < $1.key }) {
            guard let hours = r, assignments[Load.equipment(eid)]?.state == .operational, !homePowerUp, !relocated else { continue }
            consider(hours, 1.0 / 60.0, "res.device.\(eid).runtime")
        }
        return best.map { (minute: $0.0, resource: $0.1) }
    }

    mutating func advance(to t: Int) {
        let dt = Double(max(0, t - minute))
        guard dt > 0 else { minute = max(minute, t); return }
        if let w = storedWater { storedWater = max(0, w - waterDrawPerMinute * dt) }
        if let hh = handsetHours { handsetHours = max(0, hh - handsetDrawPerMinute * dt) }
        for (sid, d) in drain { if let rate = d, let e = backupEnergy[sid] ?? nil { backupEnergy[sid] = .some(max(0, e - rate / 60.0 * dt)) } }
        if !homePowerUp && !relocated {
            for (eid, r) in deviceRuntime where assignments[Load.equipment(eid)]?.state == .operational {
                if let hours = r { deviceRuntime[eid] = .some(max(0, hours - dt / 60.0)) }
            }
        }
        minute = t
    }

    mutating func handleDepletion(_ resource: String) throws {
        let causeID = events.last?.id
        switch resource {
        case "res.water.stored":
            storedWater = 0
            emit("evt.\(scenario.id).res.water-depleted", title: "scenario.common.res.water-depleted", severity: .critical,
                 rule: "rule.resource.water", facts: ["supplies.storedWaterGallons"], causedBy: causeID, sources: ["S26"])
        case "res.handset.hours":
            handsetHours = 0
            if let c = powerBankCharges, c >= 1, let full = fullHandsetHours {
                powerBankCharges = c - 1
                handsetHours = full
                emit("evt.\(scenario.id).res.handset-recharged", title: "scenario.common.res.handset-recharged",
                     values: ["charges": Fmt.num(c - 1)], severity: .info, rule: "rule.resource.handset",
                     facts: ["communications.powerBankCharges"], causedBy: causeID, sources: ["S20"])
            } else {
                flags.insert("handset.depleted")
                // The fictional household's phone is dead. The real app's controls and debrief are unaffected.
                emit("evt.\(scenario.id).res.handset-depleted", title: "scenario.common.res.handset-depleted", severity: .caution,
                     rule: "rule.resource.handset", facts: ["communications.handsetRuntimeHours", "communications.powerBankCharges"],
                     causedBy: causeID, sources: ["S20"])
            }
        case let r where r.hasPrefix("res.backup."):
            let sid = String(r.dropFirst("res.backup.".count))
            backupEnergy[sid] = .some(0)
            emit("evt.\(scenario.id).res.backup-depleted.\(sid)", title: "scenario.common.res.backup-depleted",
                 values: ["backup": household.backupPower.first { $0.id == sid }?.label ?? sid], severity: .caution,
                 rule: "rule.resource.backup", facts: ["backup.\(sid).usableEnergyWh"], causedBy: causeID, sources: ["S25"])
        case let r where r.hasPrefix("res.device."):
            let eid = String(r.dropFirst("res.device.".count).dropLast(".runtime".count))
            deviceRuntime[eid] = .some(0)
            // Documented runtime reached: the backup may no longer be relied on for this device.
            if let sid = assignments[Load.equipment(eid)]?.sourceID { backupEnergy[sid] = .some(0) }
            emit("evt.\(scenario.id).res.device-runtime-reached.\(eid)", title: "scenario.common.res.device-runtime-reached",
                 values: ["device": label(eid)], severity: .critical, rule: "rule.resource.device-runtime",
                 facts: ["equipment.\(eid).documentedBackupRuntimeHours"], causedBy: causeID, sources: ["S25"])
        default: break
        }
        try reevaluate(trigger: events.last?.id, emit: true)
    }

    // MARK: Evaluation

    mutating func reevaluate(trigger: String?, emit shouldEmit: Bool) throws {
        var inputs = external
        inputs[Svc.handset] = handsetHours.map { $0 > 0 ? .operational : .unavailable } ?? .unknown
        inputs[Svc.relocatedPower] = relocated ? .operational : .unavailable
        let gridUp = (external[Svc.grid] ?? .unknown) == .operational || external[Svc.grid] == .degraded
        let alloc = allocator.allocate(household: household, gridAvailable: gridUp, energyRemaining: backupEnergy)
        assignments = alloc.assignments
        drain = alloc.drainWhPerHour
        // Documented device runtime exhausted -> that load is no longer supplied.
        var backupStates: [String: ServiceState] = [:]
        for (load, a) in assignments {
            var s = a.state
            if load.hasPrefix("load.equipment."), s == .operational {
                let eid = String(load.dropFirst("load.equipment.".count))
                if let r = deviceRuntime[eid] ?? nil, r <= 0 { s = .unavailable }
            }
            backupStates[load] = s
        }
        let newServices: [String: ServiceState]
        do { newServices = try model.evaluate(inputs: inputs, backup: backupStates) }
        catch { throw RehearsalError.nonConvergentDependencies }
        var merged = newServices
        merged[Svc.handset] = inputs[Svc.handset]
        for k in [Svc.grid, Svc.cellular, Svc.roads] { merged[k] = external[k] }

        if shouldEmit {
            for node in model.nodes where node.id != Svc.destination {
                let old = services[node.id] ?? .unknown
                let new = merged[node.id] ?? .unknown
                guard old != new else { continue }
                emitServiceChange(node: node, state: new, trigger: trigger)
            }
            // Running on backup is a distinct, explained state (not just "operational").
            for eq in household.equipment.sorted(by: { $0.id < $1.id }) where !eq.needsRefrigeration {
                let a = assignments[Load.equipment(eq.id)]
                let ob = merged[Svc.device(eq.id)] == .operational && merged[Svc.homePower] != .operational && !relocated
                    && a?.state == .operational && a?.sourceID != nil
                if ob && !onBackup.contains(eq.id), let sid = a?.sourceID {
                    emit("evt.\(scenario.id).svc.device.\(eq.id).on-backup", title: "service.device.on-backup",
                         values: ["device": eq.label, "backup": household.backupPower.first { $0.id == sid }?.label ?? sid],
                         severity: .info, rule: "rule.dependency.backup-allocation",
                         facts: ["equipment.\(eq.id)", "backup.\(sid).setupConfirmed"], causedBy: trigger, sources: ["S25"])
                }
                if ob { onBackup.insert(eq.id) } else { onBackup.remove(eq.id) }
            }
        }
        services = merged
        for (k, v) in services where v == .unavailable { everUnavailable.insert(k) }
        noteRuntimeUnknowns()
        updateUnmet()
    }

    mutating func emitServiceChange(node: DependencyNode, state: ServiceState, trigger: String?) {
        let isDevice = node.id.hasPrefix("svc.device.")
        let key = isDevice ? "device" : String(node.id.dropFirst(4))
        var values: [String: String] = [:]
        var facts = node.factIDs
        var severity: EventSeverity = state == .operational ? .info : .caution
        if isDevice {
            let eid = String(node.id.dropFirst("svc.device.".count))
            values["device"] = label(eid)
            if state == .unavailable { severity = .critical }
            if let a = assignments[Load.equipment(eid)], state != .operational || a.sourceID != nil {
                values["reason"] = a.reason
                if let s = a.sourceID { values["backup"] = household.backupPower.first { $0.id == s }?.label ?? s; facts.append("backup.\(s)") }
            }
        }
        if state == .unavailable, (node.id == Svc.heat && scenario.ambient == "cold") || (node.id == Svc.cooling && scenario.ambient == "hot")
            || node.id == Svc.waterSupply { severity = .critical }
        emit("evt.\(scenario.id).\(node.id).\(state.rawValue)", title: "service.\(key).\(state.rawValue)", values: values,
             severity: severity, rule: node.ruleID, facts: facts, causedBy: trigger, sources: Self.sources(for: node.id),
             changes: [node.id: state])
    }

    static func sources(for svc: String) -> [String] {
        switch svc {
        case Svc.heat, Svc.homePower, Svc.refrigeration, Svc.wifi: return ["S20"]
        case Svc.cooling: return ["S21"]
        case Svc.wellPump, Svc.waterSupply, Svc.waterSafety: return ["S24", "S26"]
        case Svc.transport: return ["S23"]
        default: return svc.hasPrefix("svc.device.") ? ["S25"] : []
        }
    }

    mutating func noteStaticUnknowns() {
        let h = household
        if [.naturalGas, .propane].contains(h.housing.heatingFuel), !h.housing.heatingNeedsElectricity.isConfirmed {
            unknowns.insert("housing.heatingNeedsElectricity")
        }
        if h.housing.waterSource == .privateWell {
            if !h.housing.wellPumpElectric.isConfirmed { unknowns.insert("housing.wellPumpElectric") }
            if !h.housing.wellPressureTankGallons.isConfirmed { unknowns.insert("housing.wellPressureTankGallons") }
        }
        if !h.supplies.storedWaterGallons.isConfirmed { unknowns.insert("supplies.storedWaterGallons") }
        for eq in h.equipment where eq.isEssential && !eq.needsRefrigeration {
            if eq.compatibleBackupIDs.isEmpty { unknowns.insert("equipment.\(eq.id).backup") }
        }
        for b in h.backupPower where !b.setupConfirmed.isConfirmed { unknowns.insert("backup.\(b.id).setupConfirmed") }
        if !h.pets.isEmpty { unknowns.insert("pets.waterNeeds") }
    }

    mutating func noteRuntimeUnknowns() {
        for eq in household.equipment where eq.isEssential {
            let a = assignments[Load.equipment(eq.id)]
            if a?.state == .operational, deviceRuntime[eq.id] ?? nil == nil {
                // Running on backup with no documented runtime: unknown stays unknown.
                if let sid = a?.sourceID, drain[sid] ?? nil == nil || eq.powerWatts.confirmedValue == nil {
                    unknowns.insert("equipment.\(eq.id).runtime")
                }
            }
            if a?.state == .unknown { unknowns.insert("equipment.\(eq.id).backupOutcome") }
        }
    }

    mutating func updateUnmet() {
        var unmet = stickyUnmet
        let trigger = events.last?.id
        for eq in household.equipment where eq.isEssential {
            let s = services[Svc.device(eq.id)] ?? .unknown
            if s == .unavailable || s == .unknown {
                unmet.insert(eq.needsRefrigeration ? "req.refrigeration.\(eq.id)" : "req.power.\(eq.id)")
            } else if s == .degraded, eq.needsRefrigeration {
                unmet.insert("req.refrigeration.\(eq.id)")
            }
        }
        if scenario.ambient == "cold", !relocated, services[Svc.heat] != .operational { unmet.insert("req.heat") }
        if scenario.ambient == "hot", !relocated, services[Svc.cooling] != .operational { unmet.insert("req.cooling") }
        if !tapWaterUsable, !relocated, (storedWater ?? 0) <= 0 { unmet.insert("req.water") }
        if services[Svc.handset] == .unavailable { unmet.insert("req.comms.handset") }
        currentUnmet = unmet
        for u in unmet where !unmetEver.contains(u) {
            unmetEver.insert(u)
            if let t = trigger { causes[u] = [t] }
        }
    }

    mutating func snapshot() {
        var res: [String: ResourceQuantity] = [
            "res.water.stored": ResourceQuantity(amount: storedWater.map(Fmt.round2), unit: "gal"),
            "res.handset.hours": ResourceQuantity(amount: handsetHours.map(Fmt.round2), unit: "h"),
            "res.handset.powerBankCharges": ResourceQuantity(amount: powerBankCharges, unit: "charges"),
        ]
        for (sid, e) in backupEnergy { res["res.backup.\(sid)"] = ResourceQuantity(amount: e.map(Fmt.round2), unit: "Wh") }
        for (eid, r) in deviceRuntime where household.equipment.contains(where: { $0.id == eid && !$0.needsRefrigeration }) {
            res["res.device.\(eid).runtime"] = ResourceQuantity(amount: r.map(Fmt.round2), unit: "h")
        }
        let fired = events.filter { $0.simMinute == minute }.map(\.id)
        let snap = SimulationSnapshot(simMinute: minute, services: services, resources: res, unmetRequirements: currentUnmet.sorted(),
                                      unknowns: unknowns.sorted(), firedEventIDs: fired)
        if let last = snapshots.last, last.simMinute == minute { snapshots[snapshots.count - 1] = snap } else { snapshots.append(snap) }
    }

    // MARK: Emission

    @discardableResult
    mutating func emit(_ baseID: String, title: String, detail: String? = nil, values: [String: String] = [:], severity: EventSeverity,
                       rule: String, facts: [String] = [], causedBy: String?, sources: [String], changes: [String: ServiceState] = [:],
                       priority: Int = 0) -> String {
        let n = idCounts[baseID, default: 0] + 1
        idCounts[baseID] = n
        let id = n == 1 ? baseID : "\(baseID).\(n)"
        events.append(SimulationEvent(id: id, simMinute: minute, priority: priority, phaseID: phaseID, titleKey: title, detailKey: detail,
                                      templateValues: values, severity: severity, serviceChanges: changes,
                                      evidence: EvidenceLink(ruleID: rule, factIDs: facts, causedByEventIDs: causedBy.map { [$0] } ?? [],
                                                             sourceIDs: sources)))
        return id
    }

    func label(_ equipmentID: String) -> String { household.equipment.first { $0.id == equipmentID }?.label ?? equipmentID }

    mutating func requireSticky(_ req: String, cause: String?) {
        stickyUnmet.insert(req)
        currentUnmet.insert(req)
        if !unmetEver.contains(req) { unmetEver.insert(req); if let c = cause { causes[req] = [c] } }
    }

    mutating func resolveSticky(_ req: String) { stickyUnmet.remove(req); currentUnmet.remove(req) }
}

enum Fmt {
    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func num(_ x: Double) -> String {
        if x == x.rounded() { return String(Int(x)) }
        return String(format: "%.1f", x)
    }
    static func opt(_ x: Double?) -> String { x.map(num) ?? "unknown" }
}

/// Applicability predicates for authored events/choices.
public enum Applicability {
    public static func holds(_ preds: [String], household h: HouseholdProfile, home: HomeModel, variants: [String]) -> Bool {
        preds.allSatisfy { holds($0, h, home, variants) }
    }

    static func holds(_ p: String, _ h: HouseholdProfile, _ home: HomeModel, _ variants: [String]) -> Bool {
        if p.hasPrefix("!") { return !holds(String(p.dropFirst()), h, home, variants) }
        let parts = p.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts[0], val = parts.count > 1 ? parts[1] : ""
        switch key {
        case "variant": return variants.contains(val)
        case "waterSource": return h.housing.waterSource.rawValue == val
        case "homeType": return h.housing.homeType.rawValue == val
        case "hasPets": return !h.pets.isEmpty
        case "noVehicle": return !h.transport.hasVehicle
        case "hasEssentialEquipment": return h.equipment.contains { $0.isEssential }
        case "heatingFuel": return h.housing.heatingFuel.rawValue == val
        case "hasStairs": return !home.connectors.isEmpty
        default: return false
        }
    }
}
