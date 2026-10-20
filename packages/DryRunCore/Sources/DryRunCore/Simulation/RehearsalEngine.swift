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
    public static let engineVersion = "cascade-engine/2"
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
        try SimulationSession.authoredResult(input,library:library,planner:planner,actions:actions)
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
    public var home: HomeModel?
    public var unmetEver: Set<String>
    public var unknowns: Set<String>
    public var flags: Set<String>
    /// Event IDs that caused each unmet requirement (first occurrence).
    public var causes: [String: [String]]
    public var finalServices: [String: ServiceState]
    public var everUnavailable: Set<String>
    public var variants: [String]
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
    var input: RehearsalInput
    var household: HouseholdProfile
    let home: HomeModel?
    let planner: EgressPlanning
    var model: DependencyModel
    let allocator = BackupAllocator()

    var hazardProgress: HazardProgress?
    var minute = 0
    var external = Svc.externalDefaults
    var services: [String: ServiceState] = [:]
    var advisory: WaterAdvisory?
    var relocated = false
    var boilingTapWater = false
    /// 1 = drinking/cooking planning baseline; 2 = stored water also used for hygiene (authored choice).
    var waterDrawMultiplier = 1.0

    // Resources (nil = unknown; never invented)
    var storedWater: Double?
    var tracksFood=false
    var foodDays:Double?
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
    var spatialState: SpatialExerciseState?
    var onBackup: Set<String> = []
    var phaseID: String
    /// Choice overrides carried by "Try this change" interventions (parameter keys that are choice-point IDs).
    var interventionChoices: [String: String]

    init(scenario: ScenarioDefinition, input: RehearsalInput, household: HouseholdProfile, home: HomeModel?, planner: EgressPlanning) {
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
        var overrides: [String: String] = [:]
        for i in input.interventions { for (k, v) in i.parameters where k.hasPrefix("choice.") { overrides[k] = v } }
        self.interventionChoices = overrides
    }

    // MARK: Execution

    /// Explicit spatial options and the native variant path select the same authored exercise.
    var effectiveVariants: [String] {
        var variants = input.variants.filter { $0 != "householdLeak" }
        if hazardProgress != nil {variants.append("adaptive-mechanics")}
        if scenario.hazard == .flashFlood && input.effectiveSpatialOptions.floodIsHouseholdLeak { variants.append("householdLeak") }
        return variants
    }

    func summary() -> RunSummary {
        RunSummary(scenario: scenario, household: household, home: home, unmetEver: unmetEver, unknowns: unknowns,
                   flags: flags, causes: causes, finalServices: services, everUnavailable: everUnavailable,
                   variants: effectiveVariants)
    }

    // MARK: Time and resources

    var tapWaterUsable: Bool {
        // Reduced pressure (degraded) still delivers water; only unavailable/unknown supply forces storage use.
        let supplyOK = services[Svc.waterSupply] == .operational || services[Svc.waterSupply] == .degraded
        let safety = services[Svc.waterSafety] ?? .unknown
        return supplyOK && (safety == .operational || (safety == .degraded && boilingTapWater))
    }

    /// Home circuits deliver power (grid strain = degraded still powers loads; only outages stop them).
    var homePowerUp: Bool { services[Svc.homePower] == .operational || services[Svc.homePower] == .degraded }

    /// Water drawn from storage per minute: CDC storage-planning baseline of 1 gal/person/day [S26],
    /// an exercise assumption, not a prescribed drinking volume. Pets' extra needs are not modelled (unknown).
    var waterDrawPerMinute: Double {
        guard !tapWaterUsable, !relocated else { return 0 }
        return Double(household.people.count) * waterDrawMultiplier / 1440.0
    }

    /// Recorded whole-household coverage days, not calories, nutrition or inferred package counts.
    /// Once relocated, this bounded home-stock exercise makes no claim about external food access.
    var foodDrawPerMinute:Double {tracksFood && !relocated ? 1.0/1440.0:0}

    var handsetDrawPerMinute: Double { (homePowerUp || relocated) ? 0 : 1.0 / 60.0 }

    func nextDepletion() -> (minute: Int, resource: String)? { depletionSchedule().first }

    func depletionSchedule() -> [(minute: Int, resource: String)] {
        var candidates: [(Int, String)] = []
        func consider(_ amount: Double?, _ rate: Double, _ id: String) {
            guard let a = amount, a.isFinite, a > 0, rate.isFinite, rate > 0, minute<=scenario.durationMinutes else { return }
            let delay=(a/rate).rounded(.up)
            // Extremely large confirmed quantities cannot overflow integer time or create a boundary
            // beyond this exercise. No resource amount is clamped or silently replenished here.
            guard delay.isFinite,delay<=Double(scenario.durationMinutes-minute),delay<Double(Int.max) else {return}
            candidates.append((minute+Int(delay), id))
        }
        consider(storedWater, waterDrawPerMinute, "res.water.stored")
        if tracksFood {consider(foodDays,foodDrawPerMinute,"res.food.days")}
        consider(handsetHours, handsetDrawPerMinute, "res.handset.hours")
        for (sid, d) in drain.sorted(by: { $0.key < $1.key }) {
            if let rate = d, let e = backupEnergy[sid] ?? nil { consider(e, rate / 60.0, "res.backup.\(sid)") }
        }
        for (eid, r) in deviceRuntime.sorted(by: { $0.key < $1.key }) {
            guard let hours = r, assignments[Load.equipment(eid)]?.state == .operational, !homePowerUp, !relocated else { continue }
            consider(hours, 1.0 / 60.0, "res.device.\(eid).runtime")
        }
        return candidates.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { (minute: $0.0, resource: $0.1) }
    }

    mutating func advance(to t: Int) {
        let dt = Double(max(0, t - minute))
        guard dt > 0 else { minute = max(minute, t); return }
        advanceHazardTemperature(minutes:dt)
        if let w = storedWater { storedWater = max(0, w - waterDrawPerMinute * dt) }
        if tracksFood,let days=foodDays {foodDays=max(0,days-foodDrawPerMinute*dt)}
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
        case "res.food.days":
            foodDays=0
            emit("evt.\(scenario.id).res.food-depleted",title:"scenario.common.res.food-depleted",severity:.caution,
                 rule:"rule.resource.food/1",facts:["inventory.food.householdDays"],causedBy:causeID,sources:["S64"])
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
                guard old != new, Self.isReportable(node.id, state: new, previous: old, ambient: scenario.ambient) else { continue }
                emitServiceChange(node: node, state: new, trigger: trigger)
            }
            // Running on backup is a distinct, explained state (not just "operational").
            for eq in household.equipment.sorted(by: { $0.id < $1.id }) where eq.requiresElectricalPower {
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

    /// Keeps the timeline readable: every state is still in snapshots, but heating changes are not narrated
    /// in a heat wave (and vice versa), and "degraded" is narrated only where it changes what the household can do.
    static func isReportable(_ svc: String, state: ServiceState, previous: ServiceState, ambient: String) -> Bool {
        if svc == Svc.heat && ambient == "hot" { return false }
        if svc == Svc.cooling && ambient == "cold" { return false }
        if state == .degraded || (previous == .degraded && state == .operational) {
            return svc == Svc.cooling || svc == Svc.transport || svc == Svc.alerts || svc == Svc.homePower || svc == Svc.waterSafety || svc.hasPrefix("svc.device.")
        }
        return true
    }

    static func sources(for svc: String) -> [String] {
        switch svc {
        case Svc.heat, Svc.homePower, Svc.refrigeration, Svc.wifi: return ["S20"]
        case Svc.cooling: return ["S21"]
        case Svc.wellPump, Svc.waterSupply, Svc.waterSafety: return ["S24", "S26"]
        case Svc.transport: return ["S23"]
        case Svc.alerts: return ["S17", "S22"]
        default: return svc.hasPrefix("svc.device.") ? ["S25"] : []
        }
    }

    mutating func noteStaticUnknowns() {
        if home == nil && [.homeFire, .flashFlood, .tornado].contains(scenario.hazard) {
            unknowns.insert("home")
            flags.insert("spatial.layoutUnavailable")
        }
        let h = household
        if [.naturalGas, .propane].contains(h.housing.heatingFuel), !h.housing.heatingNeedsElectricity.isConfirmed {
            unknowns.insert("housing.heatingNeedsElectricity")
        }
        if h.housing.waterSource == .privateWell {
            if !h.housing.wellPumpElectric.isConfirmed { unknowns.insert("housing.wellPumpElectric") }
            if !h.housing.wellPressureTankGallons.isConfirmed { unknowns.insert("housing.wellPressureTankGallons") }
        }
        if !h.supplies.storedWaterGallons.isConfirmed { unknowns.insert("supplies.storedWaterGallons") }
        for eq in h.equipment where eq.isEssential && eq.requiresElectricalPower {
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
                if eq.requiresColdStorage { unmet.insert("req.refrigeration.\(eq.id)") }
                if eq.requiresElectricalPower { unmet.insert("req.power.\(eq.id)") }
            } else if s == .degraded, eq.requiresColdStorage {
                unmet.insert("req.refrigeration.\(eq.id)")
            }
        }
        if scenario.ambient == "cold", !relocated, services[Svc.heat] != .operational { unmet.insert("req.heat") }
        if scenario.ambient == "hot", !relocated, services[Svc.cooling] != .operational { unmet.insert("req.cooling") }
        if !tapWaterUsable, !relocated, (storedWater ?? 0) <= 0 { unmet.insert("req.water") }
        if tracksFood,!relocated,foodDays.map({$0<=0})==true {unmet.insert("req.food")}
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
        if tracksFood {res["res.food.days"]=ResourceQuantity(amount:foodDays.map(Fmt.round2),unit:"day")}
        for (sid, e) in backupEnergy { res["res.backup.\(sid)"] = ResourceQuantity(amount: e.map(Fmt.round2), unit: "Wh") }
        for (eid, r) in deviceRuntime where household.equipment.contains(where: { $0.id == eid && $0.requiresElectricalPower }) {
            res["res.device.\(eid).runtime"] = ResourceQuantity(amount: r.map(Fmt.round2), unit: "h")
        }
        let fired = events.filter { $0.simMinute == minute }.map(\.id)
        let sceneTriggerCount: Int
        if let scene = spatialState, scene != snapshots.last?.spatialState,
           let trigger = events.firstIndex(where: { $0.id == scene.stageID }) { sceneTriggerCount = trigger + 1 }
        else { sceneTriggerCount = events.count }
        let snap = SimulationSnapshot(simMinute: minute, services: services, resources: res, unmetRequirements: currentUnmet.sorted(),
                                      unknowns: unknowns.sorted(), firedEventIDs: fired, spatialState: spatialState, revealedEventCount: sceneTriggerCount)
        snapshots.append(snap)
    }

    // MARK: Emission

    @discardableResult
    mutating func emit(_ baseID: String, title: String, detail: String? = nil, values: [String: String] = [:], severity: EventSeverity,
                       rule: String, facts: [String] = [], causedBy: String?, sources: [String], changes: [String: ServiceState] = [:],
                       priority: Int = 0) -> String {
        // Machine codes in template values are never spliced into prose: they are surfaced as localized detail keys.
        var detail = detail
        if detail == nil {
            if let r = values["reason"] { detail = "reason.\(r)" }
            else if let i = values["independence"] { detail = "independence.\(i)" }
            else if let a = values["advisory"] { detail = "advisory.\(a)" }
        }
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
    public static func holds(_ preds: [String], household h: HouseholdProfile, home: HomeModel?, variants: [String]) -> Bool {
        preds.allSatisfy { holds($0, h, home, variants) }
    }

    static func holds(_ p: String, _ h: HouseholdProfile, _ home: HomeModel?, _ variants: [String]) -> Bool {
        // Absence is not evidence of "no stairs", even under a negated predicate.
        if home == nil && p.drop(while: { $0 == "!" }) == "hasStairs" { return false }
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
        case "hasStairs": return home.map { !$0.connectors.isEmpty } ?? false
        default: return false
        }
    }
}
