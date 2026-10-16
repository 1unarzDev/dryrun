import Foundation

// Semantics for authored rule IDs and choice effects. Packs choose timing and parameters;
// they cannot add behaviour that has not been written and reviewed here.

extension RunState {
    mutating func apply(_ e: AuthoredEvent) throws {
        if let p = scenario.phases.last(where: { $0.startMinute <= e.minute }) { phaseID = e.phaseID.isEmpty ? p.id : e.phaseID } else { phaseID = e.phaseID }
        var changes: [String: ServiceState] = [:]
        var facts: [String] = []
        var values: [String: String] = [:]

        switch e.rule {
        case RuleID.setExternal:
            if let svc = e.params["service"], let st = e.params["state"].flatMap(ServiceState.init(rawValue:)) {
                external[svc] = st
                changes[svc] = st
            }
        case RuleID.waterAdvisory:
            let adv = e.params["advisory"].flatMap(WaterAdvisory.init(rawValue:)) ?? .unknownQuality
            advisory = adv
            values["advisory"] = adv.rawValue
            switch adv {
            case .quantityUnavailable: external[Svc.municipalSupply] = .unavailable; changes[Svc.municipalSupply] = .unavailable
            case .unknownQuality: external[Svc.utilitySafety] = .unknown; changes[Svc.utilitySafety] = .unknown
            case .boilWater: external[Svc.utilitySafety] = .degraded; changes[Svc.utilitySafety] = .degraded
            case .doNotDrink, .doNotUse:
                external[Svc.utilitySafety] = .unavailable; changes[Svc.utilitySafety] = .unavailable
                boilingTapWater = false
                flags.insert("advisory.chemical")
            }
            if adv == .doNotUse { flags.insert("advisory.doNotUse") }
            flags.insert("advisory.\(adv.rawValue)")
            facts.append("housing.waterSource")
        case RuleID.recoveryPowerRestored:
            external[Svc.grid] = .operational
            changes[Svc.grid] = .operational
        case RuleID.floodWarning:
            external[Svc.roads] = .degraded
            changes[Svc.roads] = .degraded
            flags.insert("flood.warning")
        default: break
        }

        let id = emit(e.id, title: e.titleKey, detail: e.detailKey, values: values, severity: e.severity, rule: e.rule, facts: facts,
                      causedBy: nil, sources: e.sourceIDs, changes: changes, priority: e.priority)
        try reevaluate(trigger: id, emit: true)

        switch e.rule {
        case RuleID.checkpoint: checkpoint(e, cause: id)
        case RuleID.recoveryPowerRestored: recoveryNotes(cause: id)
        case RuleID.fireIgnition: fireIgnition(cause: id)
        case RuleID.fireBlockPrimary: fireBlock(e: e, cause: id)
        case RuleID.tornadoWarning: tornadoWarning(cause: id)
        case RuleID.recoveryDisplacement: displacement(cause: id)
        case RuleID.floodWarning: floodWarning(cause: id)
        case RuleID.waterAdvisory:
            if flags.contains("advisory.chemical") {
                emit("evt.\(scenario.id).advisory.boil-not-remedy", title: "scenario.common.advisory.boil-not-remedy", severity: .critical,
                     rule: "rule.water.chemical-no-boil", facts: [], causedBy: id, sources: ["S24"])
            }
        default: break
        }
        updateUnmet()
    }

    // MARK: Checkpoints and recovery

    mutating func checkpoint(_ e: AuthoredEvent, cause: String) {
        let people = household.people.count
        let target = Double(people) * 3.0
        emit("evt.\(scenario.id).checkpoint.water-target",
             title: initialStoredWater == nil ? "scenario.common.checkpoint.water-target-unknown" : "scenario.common.checkpoint.water-target",
             values: ["people": String(people), "target": Fmt.num(target), "stored": Fmt.opt(storedWater),
                      "initial": Fmt.opt(initialStoredWater)],
             severity: (initialStoredWater ?? 0) < target ? .caution : .info, rule: "rule.resource.water-storage-target",
             facts: ["supplies.storedWaterGallons", "people"], causedBy: cause, sources: ["S26"])
        if (initialStoredWater ?? 0) < target { flags.insert("water.belowTarget") }
        if !household.pets.isEmpty {
            emit("evt.\(scenario.id).checkpoint.pets-water", title: "scenario.common.checkpoint.pets-water", severity: .info,
                 rule: "rule.resource.water-storage-target", facts: ["pets"], causedBy: cause, sources: ["S26"])
        }
        if services[Svc.cellular] != .operational, services[Svc.wifi] != .operational, (handsetHours ?? 0) > 0 {
            // A powered handset keeps the offline plan even with no connectivity.
            flags.insert("offlinePlanAvailable")
            emit("evt.\(scenario.id).checkpoint.offline-plan", title: "scenario.common.checkpoint.offline-plan", severity: .info,
                 rule: "rule.comms.offline-plan", facts: ["communications.handsetRuntimeHours"], causedBy: cause, sources: [])
        }
    }

    mutating func recoveryNotes(cause: String) {
        // Restoration does not refill batteries or stored water, clear advisories, or certify devices.
        for b in household.backupPower.sorted(by: { $0.id < $1.id }) {
            if let start = initialBackupEnergy[b.id] ?? nil, let now = backupEnergy[b.id] ?? nil, now < start {
                emit("evt.\(scenario.id).recovery.backup-not-refilled.\(b.id)", title: "scenario.common.recovery.backup-not-refilled",
                     values: ["backup": b.label], severity: .info, rule: "rule.recovery.no-auto-refill", facts: ["backup.\(b.id)"],
                     causedBy: cause, sources: ["S25"])
            }
        }
        if let start = initialStoredWater, let now = storedWater, now < start {
            emit("evt.\(scenario.id).recovery.water-not-refilled", title: "scenario.common.recovery.water-not-refilled",
                 values: ["stored": Fmt.num(Fmt.round2(now))], severity: .info, rule: "rule.recovery.no-auto-refill",
                 facts: ["supplies.storedWaterGallons"], causedBy: cause, sources: ["S26"])
        }
        if let a = advisory {
            emit("evt.\(scenario.id).recovery.advisory-remains", title: "scenario.common.recovery.advisory-remains",
                 values: ["advisory": a.rawValue], severity: .caution, rule: "rule.recovery.advisory-persists", facts: [],
                 causedBy: cause, sources: ["S24"])
        }
        for eq in household.equipment.sorted(by: { $0.id < $1.id }) where eq.isEssential && everUnavailable.contains(Svc.device(eq.id)) {
            emit("evt.\(scenario.id).recovery.check-device.\(eq.id)", title: "scenario.common.recovery.check-device",
                 values: ["device": eq.label], severity: .caution, rule: "rule.recovery.device-not-certified",
                 facts: ["equipment.\(eq.id)"], causedBy: cause, sources: ["S25"])
        }
        // Handsets can be recharged once power is back (stated rule; backups are not).
        if let full = fullHandsetHours, (handsetHours ?? full) < full {
            handsetHours = full
            emit("evt.\(scenario.id).recovery.handset-recharge", title: "scenario.common.recovery.handset-recharge", severity: .info,
                 rule: "rule.recovery.handset-recharge-on-grid", facts: ["communications.handsetRuntimeHours"], causedBy: cause, sources: [])
            try? reevaluate(trigger: cause, emit: true)
        }
        resolveSticky("req.comms.handset")
    }

    mutating func displacement(cause: String) {
        let t = services[Svc.transport] ?? .unknown
        let d = services[Svc.destination] ?? .unknown
        if t == .operational, d == .operational {
            emit("evt.\(scenario.id).displacement.ready", title: "scenario.common.displacement.ready", severity: .info,
                 rule: "rule.recovery.displacement", facts: ["transport", "transport.destinations"], causedBy: cause, sources: ["S29"])
        } else {
            let reason = relocationGapReason()
            emit("evt.\(scenario.id).displacement.gap", title: "scenario.common.displacement.gap", values: ["reason": reason],
                 severity: .caution, rule: "rule.recovery.displacement", facts: ["transport.vehicles", "transport.alternatives", "transport.destinations"],
                 causedBy: cause, sources: ["S29"])
            requireSticky("req.relocation", cause: cause)
            flags.insert("relocation.gap.\(reason)")
        }
    }

    /// Why relocation cannot be completed in the model. Order: roads, vehicle, agreed transport, destination.
    func relocationGapReason() -> String {
        if services[Svc.roads] != .operational { return "roadsClosed" }
        if services[Svc.transport] != .operational {
            if !household.transport.hasVehicle { return "noVehicle" }
            if household.people.contains(where: { $0.needs.contains(.usesWheelchair) }) { return "vehicleNotAccessible" }
            return "transportUnconfirmed"
        }
        return "noConfirmedDestination"
    }

    // MARK: Fire (immediate exercise; practice routes under authored assumptions)

    func startSpace(for p: Person) -> String {
        // A missing or stale assignment is an explicit unknown. Never silently start a person in
        // the living room (or the first scanned room), which can make a rehearsal claim a route
        // from the wrong place.
        guard let s = p.sleepingSpaceID, home.space(s) != nil else { return "unknown" }
        return s
    }

    /// Human label for an exit: the room it leaves from (household-entered label), never the raw portal ID.
    func exitRoomLabel(_ portalID: String) -> String {
        guard let pt = home.portal(portalID) else { return "" }
        for side in [pt.sideA, pt.sideB] { if case .space(let sid) = side, let sp = home.space(sid) { return sp.label } }
        return pt.note ?? ""
    }

    func mobility(for p: Person) -> MobilityProfile { p.requiresStepFreeRoute ? .wheelchair : .walking }

    mutating func fireIgnition(cause: String) {
        flags.insert("fire")
        // Usual (practised) routes with no exercise exclusions.
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            let r = planner.plan(RouteRequest(personID: p.id, startSpaceID: startSpace(for: p), mobility: mobility(for: p)), in: home)
            currentRoutes[p.id] = r
            routes.append(r)
            if r.primary == nil {
                emit("evt.home-fire.route.no-usual.\(p.id)", title: "scenario.home-fire.route.no-usual",
                     values: ["person": p.alias, "reason": r.noRouteReason?.rawValue ?? "unknown"], severity: .critical,
                     rule: "rule.fire.route", facts: ["person.\(p.id)", "home.portals"], causedBy: cause, sources: ["S19"])
                requireSticky("req.egress.\(p.id)", cause: cause)
                flags.insert("fire.noRoute")
            }
        }
        assistanceCheck(cause: cause, rule: "rule.fire.assistance", sources: ["S19"])
        if let m = home.meetingPoint, m.verification == .verified {
            emit("evt.home-fire.meeting-point", title: "scenario.home-fire.meeting-point", values: ["meeting": m.label], severity: .info,
                 rule: "rule.fire.meeting-point", facts: ["home.annotation.\(m.id)"], causedBy: cause, sources: ["S19"])
        } else {
            emit("evt.home-fire.meeting-point-missing", title: "scenario.home-fire.meeting-point-missing", severity: .caution,
                 rule: "rule.fire.meeting-point", facts: ["home.annotations"], causedBy: cause, sources: ["S19"])
            requireSticky("req.meetingPoint", cause: cause)
        }
        let alarms = home.annotations.filter { $0.kind == .smokeAlarm && $0.verification == .verified }
        if alarms.isEmpty {
            unknowns.insert("home.smokeAlarms")
            flags.insert("fire.smokeAlarmsUnverified")
        }
        if !household.pets.isEmpty { flags.insert("fire.pets") }
    }

    /// Applies authored blockage. `originKind` blocks every space of that kind (the authored fire origin);
    /// `mode == "currentRoutes"` additionally blocks the exits of everyone's current practice route.
    /// If a scanned home has no space of `originKind`, preserve the missing authored input as an
    /// unknown instead of relabelling an unrelated room as the fire origin.
    mutating func fireBlock(e: AuthoredEvent, cause: String) {
        var blockedSpaces = Set<String>(), blockedPortals = Set<String>()
        for (_, r) in currentRoutes {
            blockedSpaces.formUnion(r.request.exclusions.blockedSpaceIDs)
            blockedPortals.formUnion(r.request.exclusions.blockedPortalIDs)
        }
        if let kindRaw = e.params["originKind"], let kind = SpaceKind(rawValue: kindRaw) {
            let origin = home.spaces.filter { $0.kind == kind }.map(\.id)
            if origin.isEmpty {
                unknowns.insert("home.fireOrigin.(kindRaw)")
                flags.insert("fire.originUnresolved")
            } else {
                blockedSpaces.formUnion(origin)
            }
        }
        if e.params["mode"] == "currentRoutes" {
            for (_, r) in currentRoutes { if let p = r.primary { blockedPortals.insert(p.exitPortalID) } }
        }
        let ex = ScenarioExclusions(blockedSpaceIDs: blockedSpaces.sorted(), blockedPortalIDs: blockedPortals.sorted())
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            let previous = currentRoutes[p.id]?.primary
            // A person who starts in a blocked room keeps that start; nobody is ever routed back in (no re-entry).
            var exP = ex
            exP.blockedSpaceIDs.removeAll { $0 == startSpace(for: p) }
            let r = planner.plan(RouteRequest(personID: p.id, startSpaceID: startSpace(for: p), mobility: mobility(for: p), exclusions: exP), in: home)
            currentRoutes[p.id] = r
            routes.append(r)
            if let path = r.primary {
                let changed = previous?.exitPortalID != path.exitPortalID || previous?.spaceSequence != path.spaceSequence
                emit("evt.home-fire.route.\(changed ? "alternative" : "still-clear").\(p.id)",
                     title: changed ? "scenario.home-fire.route.alternative" : "scenario.home-fire.route.still-clear",
                     values: ["person": p.alias, "exitRoom": exitRoomLabel(path.exitPortalID), "exitPortalID": path.exitPortalID,
                              "independence": r.alternativeStatus.rawValue],
                     severity: changed ? .caution : .info, rule: "rule.fire.route",
                     facts: ["person.\(p.id)", "home.portal.\(path.exitPortalID)"], causedBy: cause, sources: ["S19"])
                resolveSticky("req.egress.\(p.id)")
            } else {
                emit("evt.home-fire.route.none.\(p.id)", title: "scenario.home-fire.route.none",
                     values: ["person": p.alias, "reason": r.noRouteReason?.rawValue ?? "unknown"], severity: .critical,
                     rule: "rule.fire.route", facts: ["person.\(p.id)", "home.portals"], causedBy: cause, sources: ["S19"])
                requireSticky("req.egress.\(p.id)", cause: cause)
                flags.insert("fire.noRoute")
            }
            if r.primary != nil, r.alternativeStatus != .independent { flags.insert("fire.noIndependentSecondExit") }
        }
        helperReachCheck(blockedSpaces: blockedSpaces, blockedPortals: blockedPortals, cause: cause)
    }

    /// Can each assigned helper reach the person they help without entering an authored blocked space?
    /// Conservative room-level reachability over VERIFIED, operable, non-window interior connections and verified
    /// stairs; a helper is never sent into a blocked room (no entry into the fire area, no re-entry).
    /// If unreachable, the plan must not rely on that helper: we say so instead of "assigned".
    mutating func helperReachCheck(blockedSpaces: Set<String>, blockedPortals: Set<String>, cause: String) {
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            guard let hid = p.helperPersonID, let helper = household.people.first(where: { $0.id == hid }),
                  !flags.contains("fire.helperBlocked.\(p.id)") else { continue }
            let from = startSpace(for: helper), to = startSpace(for: p)
            if Self.reachable(from: from, to: to, home: home, blockedSpaces: blockedSpaces, blockedPortals: blockedPortals) { continue }
            flags.insert("fire.helperBlocked.\(p.id)")
            emit("evt.home-fire.assist.helper-blocked.\(p.id)", title: "scenario.common.assist.helper-blocked",
                 detail: "scenario.common.assist.helper-blocked.options",
                 values: ["person": p.alias, "helper": helper.alias], severity: .critical, rule: "rule.fire.helper-reach",
                 facts: ["person.\(p.id).helperPersonID", "person.\(p.id).sleepingSpaceID", "person.\(hid).sleepingSpaceID"],
                 causedBy: cause, sources: ["S19"])
            requireSticky("req.assistance.reach.\(p.id)", cause: cause)
        }
    }

    static func reachable(from: String, to: String, home: HomeModel, blockedSpaces: Set<String>, blockedPortals: Set<String>) -> Bool {
        if from == to { return true }
        if blockedSpaces.contains(to) { return false }
        var adj: [String: Set<String>] = [:]
        for pt in home.portals where pt.verification == .verified && pt.kind != .window && !blockedPortals.contains(pt.id) {
            guard case .space(let a) = pt.sideA, case .space(let b) = pt.sideB else { continue }
            if pt.kind != .opening && pt.operable.confirmedValue != true { continue }
            adj[a, default: []].insert(b); adj[b, default: []].insert(a)
        }
        for c in home.connectors where c.verification == .verified && c.kind != .elevator {
            adj[c.fromSpaceID, default: []].insert(c.toSpaceID); adj[c.toSpaceID, default: []].insert(c.fromSpaceID)
        }
        var seen: Set<String> = [from], queue = [from]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for n in (adj[cur] ?? []).sorted() where !seen.contains(n) && !blockedSpaces.contains(n) {
                if n == to { return true }
                seen.insert(n); queue.append(n)
            }
        }
        return false
    }

    mutating func assistanceCheck(cause: String, rule: String, sources: [String]) {
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            let needsHelp = p.needs.contains(.needsHelperToEvacuate) || p.needs.contains(.usesWheelchair)
                || p.needs.contains(.cannotUseStairs) || p.ageBand == .infant || p.ageBand == .child
                || p.needs.contains(.deafOrHardOfHearing)
            guard needsHelp else { continue }
            if let hid = p.helperPersonID, let helper = household.people.first(where: { $0.id == hid }) {
                emit("evt.\(scenario.id).assist.assigned.\(p.id)", title: "scenario.common.assist.assigned",
                     values: ["person": p.alias, "helper": helper.alias], severity: .info, rule: rule,
                     facts: ["person.\(p.id).helperPersonID"], causedBy: cause, sources: sources)
            } else {
                emit("evt.\(scenario.id).assist.missing.\(p.id)", title: "scenario.common.assist.missing", values: ["person": p.alias],
                     severity: .critical, rule: rule, facts: ["person.\(p.id).needs"], causedBy: cause, sources: sources)
                requireSticky("req.assistance.\(p.id)", cause: cause)
            }
        }
    }

    // MARK: Tornado

    var shelterSpace: Space? {
        let lowest = home.floors.map(\.level).min() ?? 0
        let lowestFloors = Set(home.floors.filter { $0.level == lowest }.map(\.id))
        let annotated = home.annotations.filter { $0.kind == .tornadoShelterCandidate && $0.verification == .verified }.compactMap(\.spaceID)
        return home.spaces.sorted { $0.id < $1.id }.first { s in
            lowestFloors.contains(s.floorID) && (annotated.contains(s.id) || s.interiorNoWindowsConfirmed.confirmedValue == true)
        }
    }

    mutating func tornadoWarning(cause: String) {
        flags.insert("tornado.warning")
        if household.housing.homeType == .manufacturedHome {
            // Manufactured homes do not provide adequate tornado protection [S22].
            emit("evt.tornado.manufactured-home", title: "scenario.tornado.manufactured-home", severity: .critical,
                 rule: "rule.tornado.manufactured-home", facts: ["housing.homeType"], causedBy: cause, sources: ["S22"])
            if !relocated { requireSticky("req.shelter.sturdyBuilding", cause: cause) }
        } else if let s = shelterSpace {
            emit("evt.tornado.shelter-preselected", title: "scenario.tornado.shelter-preselected", values: ["room": s.label],
                 severity: .info, rule: "rule.tornado.shelter", facts: ["home.space.\(s.id)"], causedBy: cause, sources: ["S22"])
        } else {
            emit("evt.tornado.shelter-not-chosen", title: "scenario.tornado.shelter-not-chosen", severity: .critical,
                 rule: "rule.tornado.shelter", facts: ["home.spaces"], causedBy: cause, sources: ["S22"])
            requireSticky("req.shelter", cause: cause)
        }
        if input.variants.contains("night") {
            let radio = household.communications.batteryOrCrankRadio.confirmedValue == true
            if services[Svc.alerts] == .operational {
                emit("evt.tornado.night-alert-received", title: "scenario.tornado.night-alert-received",
                     detail: radio ? "scenario.tornado.night-alert-via.radio" : "scenario.tornado.night-alert-via.phone",
                     severity: .info, rule: "rule.tornado.night-alerting",
                     facts: ["communications.batteryOrCrankRadio", "communications.handsetRuntimeHours"], causedBy: cause, sources: ["S22"])
            } else {
                emit("evt.tornado.night-alert-uncertain", title: "scenario.tornado.night-alert-uncertain", severity: .critical,
                     rule: "rule.tornado.night-alerting", facts: ["communications.batteryOrCrankRadio"], causedBy: cause, sources: ["S22"])
                requireSticky("req.alerts.night", cause: cause)
            }
        }
        assistanceCheck(cause: cause, rule: "rule.tornado.assistance", sources: ["S22"])
    }

    // MARK: Flood

    mutating func floodWarning(cause: String) {
        // Mapped hazard or map directions never establish that a road is passable.
        emit("evt.flash-flood.no-crossing", title: "scenario.flash-flood.no-crossing", severity: .critical,
             rule: "rule.flood.never-through-water", facts: [], causedBy: cause, sources: ["S23"])
        if household.housing.waterSource == .privateWell {
            external[Svc.wellSafety] = .unknown
            try? reevaluate(trigger: cause, emit: true)
            emit("evt.flash-flood.well-quality-unknown", title: "scenario.flash-flood.well-quality-unknown", severity: .caution,
                 rule: "rule.flood.well-quality", facts: ["housing.waterSource"], causedBy: cause, sources: ["S24"])
        }
    }

    // MARK: Choices

    func feasible(_ effect: String) -> Bool {
        switch effect {
        case "relocate", "leaveEarly":
            return services[Svc.transport] == .operational && services[Svc.destination] == .operational
        case "boilTapWater":
            // Boiling only addresses a boil-water advisory, and needs a working heat source.
            return advisory == .boilWater && homePowerUp
        case "goToShelter":
            return household.housing.homeType != .manufacturedHome && shelterSpace != nil
        case "useStoredWater":
            return (storedWater ?? 0) > 0
        case "tapForHygiene":
            // Follow the utility's advisory. Under a boil-water advisory, utilities commonly allow handwashing
            // with soap and tap water; under do-not-use (or unknown quality) tap water is not used at all.
            return advisory == .boilWater && services[Svc.waterSupply] != .unavailable
        default: return true
        }
    }

    mutating func choose(_ c: ChoicePoint) throws {
        phaseID = c.phaseID
        // A tried preparation that includes using it (e.g. relocation) overrides the choice in the replay only.
        let chosenID = interventionChoices[c.id] ?? input.choices[c.id] ?? c.defaultOptionID
        guard let opt = c.options.first(where: { $0.id == chosenID }) else {
            throw RehearsalError.invalidChoice(choiceID: c.id, optionID: chosenID)
        }
        decisions.append(DecisionPoint(id: c.id, simMinute: minute, promptKey: c.promptKey, options: c.options.map {
            DecisionPoint.Option(id: $0.id, labelKey: $0.labelKey, feedbackKey: $0.feedbackKey, isRecommended: !$0.unsafe && feasible($0.effect))
        }))
        let id = emit("evt.\(c.id)", title: opt.labelKey, detail: opt.feedbackKey, values: ["option": opt.id],
                      severity: opt.unsafe ? .critical : .info, rule: "rule.choice.\(opt.effect)", facts: [], causedBy: nil,
                      sources: c.sourceIDs, priority: 100)
        if opt.unsafe {
            // Unsafe options are never rewarded: no state improves, and the debrief explains why.
            flags.insert("unsafeChoice.\(c.id)")
            try reevaluate(trigger: id, emit: true)
            return
        }
        switch opt.effect {
        case "relocate", "leaveEarly":
            if feasible(opt.effect) {
                relocated = true
                resolveSticky("req.shelter.sturdyBuilding")
                emit("evt.\(scenario.id).relocation.done", title: "scenario.common.relocation.done", severity: .info,
                     rule: "rule.relocation", facts: ["transport", "transport.destinations"], causedBy: id, sources: c.sourceIDs)
            } else {
                let reason = relocationGapReason()
                emit("evt.\(scenario.id).relocation.blocked", title: "scenario.common.relocation.blocked", values: ["reason": reason],
                     severity: .critical, rule: "rule.relocation", facts: ["transport.vehicles", "transport.alternatives", "transport.destinations"],
                     causedBy: id, sources: c.sourceIDs)
                requireSticky("req.relocation", cause: id)
                flags.insert("relocation.gap.\(reason)")
            }
        case "boilTapWater":
            if feasible("boilTapWater") {
                boilingTapWater = true
            } else {
                let why = advisory == .boilWater ? "noHeatSource" : "notRemedyForAdvisory"
                emit("evt.\(scenario.id).boil.not-feasible", title: "scenario.water-outage.boil.not-feasible", values: ["reason": why],
                     severity: .critical, rule: "rule.water.boil-feasibility", facts: ["housing"], causedBy: id, sources: ["S24"])
                flags.insert("boil.notFeasible.\(why)")
            }
        case "goToShelter":
            if !feasible("goToShelter") { flags.insert("tornado.shelterNotAdequate") }
        case "prioritizeStored":
            waterDrawMultiplier = 1
        case "useStoredForAll":
            // Exercise assumption: using stored drinking water for flushing/washing too doubles the draw.
            waterDrawMultiplier = 2
            flags.insert("water.storedUsedForAll")
        case "tapForHygiene":
            if !feasible("tapForHygiene") {
                emit("evt.\(scenario.id).tap-hygiene.not-allowed", title: "scenario.water-outage.tap-hygiene.not-allowed",
                     detail: advisory.map { "advisory.\($0.rawValue)" }, severity: .critical, rule: "rule.water.advisory-scope",
                     facts: ["housing.waterSource"], causedBy: id, sources: ["S24"])
                flags.insert("water.tapHygieneAgainstAdvisory")
            }
        default: break
        }
        try reevaluate(trigger: id, emit: true)
    }
}
