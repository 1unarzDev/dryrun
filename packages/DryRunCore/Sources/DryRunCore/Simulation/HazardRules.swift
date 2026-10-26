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
        case RuleID.householdLeak: householdLeak(cause: id)
        case RuleID.setExternal:
            if scenario.hazard == .flashFlood && e.params["service"] == Svc.roads && e.params["state"] == ServiceState.unavailable.rawValue {
                advanceFloodScene(cause: id)
            }
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
        guard let s = input.effectiveSpatialOptions.startingSpaceIDs[p.id] ?? p.sleepingSpaceID, home?.space(s) != nil else { return "unknown" }
        return s
    }

    /// Human label for an exit: the room it leaves from (household-entered label), never the raw portal ID.
    func exitRoomLabel(_ portalID: String) -> String {
        guard let home, let pt = home.portal(portalID) else { return "" }
        for side in [pt.sideA, pt.sideB] { if case .space(let sid) = side, let sp = home.space(sid) { return sp.label } }
        return pt.note ?? ""
    }

    func mobility(for p: Person) -> MobilityProfile { p.requiresStepFreeRoute ? .wheelchair : .walking }

    mutating func fireIgnition(cause: String) {
        flags.insert("fire")
        if !BaselinePreparedness.hasRecordedAlarmReadiness("smokeAlarms", household: household) {
            unknowns.insert("home.smokeAlarms")
            flags.insert("fire.smokeAlarmsUnverified")
        }
        // Household coordination still applies without a scan; no geometry or room assignment is fabricated.
        guard let home else {
            assistanceCheck(cause: cause, rule: "rule.fire.assistance", sources: ["S19"])
            if !household.pets.isEmpty { flags.insert("fire.pets") }
            return
        }
        // Usual (practised) routes with no exercise exclusions. Version 6 adaptive sessions: an explicit
        // incident origin is already known at the alarm, so no route may pass through that room.
        let explicitOrigin = hazardProgress?.supportsOriginExclusion == true ? input.effectiveSpatialOptions.originSpaceID.flatMap { home.space($0)?.id } : nil
        let alarmExclusions = explicitOrigin.map { ScenarioExclusions(blockedSpaceIDs: [$0]) } ?? .none
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            let r = planner.plan(RouteRequest(personID: p.id, startSpaceID: startSpace(for: p), mobility: mobility(for: p), exclusions: alarmExclusions), in: home)
            currentRoutes[p.id] = r
            routes.append(r)
            if r.primary == nil {
                emit("evt.home-fire.route.no-usual.\(p.id)", title: "scenario.home-fire.route.no-usual",
                     values: ["person": p.alias, "reason": r.noRouteReason?.rawValue ?? "unknown"], severity: .critical,
                     rule: "rule.fire.route", facts: ["person.\(p.id)", "home.portals"], causedBy: cause, sources: ["S19"])
                if !isOutside(p.id) { requireSticky("req.egress.\(p.id)", cause: cause) }
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
        if !household.pets.isEmpty { flags.insert("fire.pets") }
        if let explicitOrigin {
            updateSpatialScene(stage: cause, affected: [explicitOrigin], assumption: "Exercise: the selected fire origin room is excluded from every route from the alarm onward. An occupied origin room remains exposed; no supported departure is assumed.")
            spatialState?.originSpaceID = explicitOrigin
            return
        }
        updateSpatialScene(stage: cause, affected: [], assumption: "Exercise: routes before the authored smoke blockage. Starting rooms are recorded household assignments.")
    }

    /// Applies authored blockage. `originKind` proposes one actual room as the authored origin;
    /// `mode == "currentRoutes"` additionally blocks the exits of everyone's current practice route.
    /// If a scanned home has no space of `originKind`, preserve the missing authored input as an
    /// unknown instead of relabelling an unrelated room as the fire origin.
    mutating func fireBlock(e: AuthoredEvent, cause: String) {
        guard let home else { return }
        var blockedSpaces = Set<String>(), blockedPortals = Set<String>()
        for (_, r) in currentRoutes {
            blockedSpaces.formUnion(r.request.exclusions.blockedSpaceIDs)
            blockedPortals.formUnion(r.request.exclusions.blockedPortalIDs)
        }
        if let kindRaw = e.params["originKind"], let kind = SpaceKind(rawValue: kindRaw) {
            // One actual origin, selected explicitly or by a stable seeded choice among matching rooms.
            var neighbors: Set<String> = []
            for portal in home.portals where portal.verification == .verified {
                if case .space(let a) = portal.sideA, case .space(let b) = portal.sideB {
                    if blockedSpaces.contains(a) { neighbors.insert(b) }
                    if blockedSpaces.contains(b) { neighbors.insert(a) }
                }
            }
            let candidates = home.spaces.filter { $0.kind == kind && (blockedSpaces.isEmpty || neighbors.contains($0.id)) }.sorted { $0.id < $1.id }
            let explicit = input.effectiveSpatialOptions.originSpaceID.flatMap(home.space)
            // Version 6 already excluded that explicit origin at the alarm; it is still the origin here.
            let alreadyExcluded = hazardProgress?.supportsOriginExclusion == true && explicit.map { blockedSpaces == [$0.id] } == true
            let selected = blockedSpaces.isEmpty || alreadyExcluded ? explicit : nil
            let origin = selected ?? (candidates.isEmpty ? nil : candidates[Int(input.seed % UInt64(candidates.count))])
            if let origin {
                blockedSpaces.insert(origin.id)
                if spatialState?.originSpaceID == nil { spatialState?.originSpaceID = origin.id }
            } else {
                unknowns.insert("home.fireOrigin.\(kindRaw)")
                flags.insert("fire.originUnresolved")
            }
        }
        if e.params["mode"] == "currentRoutes" {
            for (_, r) in currentRoutes { if let p = r.primary { blockedPortals.insert(p.exitPortalID) } }
        }
        let ex = ScenarioExclusions(blockedSpaceIDs: blockedSpaces.sorted(), blockedPortalIDs: blockedPortals.sorted())
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            let previous = currentRoutes[p.id]?.primary
            // A person who starts in a blocked room keeps that start; nobody is ever routed back in (no re-entry).
            let r = planner.plan(RouteRequest(personID: p.id, startSpaceID: startSpace(for: p), mobility: mobility(for: p), exclusions: ex), in: home)
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
                if !isOutside(p.id) { requireSticky("req.egress.\(p.id)", cause: cause) }
                flags.insert("fire.noRoute")
            }
            if r.primary != nil, r.alternativeStatus != .independent { flags.insert("fire.noIndependentSecondExit") }
        }
        updateSpatialScene(stage: cause, affected: blockedSpaces.sorted(), portals: blockedPortals.sorted(), assumption: "Exercise: authored smoke or blockage excludes these rooms and openings. An affected starting room remains exposed; no supported departure is assumed.")
        helperReachCheck(blockedSpaces: blockedSpaces, blockedPortals: blockedPortals, cause: cause)
    }

    /// Can each assigned helper reach the person they help without entering an authored blocked space?
    /// Uses the same portal attachment, geometry, clearance and mobility contract as every practice route.
    /// A helper is never sent into a blocked room (no entry into the fire area, no re-entry).
    /// If unreachable, the plan must not rely on that helper: we say so instead of "assigned".
    mutating func helperReachCheck(blockedSpaces: Set<String>, blockedPortals: Set<String>, cause: String) {
        guard let home else { return }
        for p in household.people.sorted(by: { $0.id < $1.id }) {
            if isOutside(p.id) { continue }
            guard let hid = p.helperPersonID, let helper = household.people.first(where: { $0.id == hid }),
                  !flags.contains("fire.helperBlocked.\(p.id)") else { continue }
            let from = isOutside(helper.id) ? "unknown" : startSpace(for: helper), to = startSpace(for: p)
            let reach = planner.plan(RouteRequest(personID: helper.id, startSpaceID: from,
                mobility: mobility(for: helper),
                exclusions: ScenarioExclusions(blockedSpaceIDs: blockedSpaces.sorted(), blockedPortalIDs: blockedPortals.sorted()),
                purpose: .helperReach, destinationSpaceID: to), in: home)
            if reach.primary != nil { continue }
            flags.insert("fire.helperBlocked.\(p.id)")
            emit("evt.home-fire.assist.helper-blocked.\(p.id)", title: "scenario.common.assist.helper-blocked",
                 detail: "scenario.common.assist.helper-blocked.options",
                 values: ["person": p.alias, "helper": helper.alias], severity: .critical, rule: "rule.fire.helper-reach",
                 facts: ["person.\(p.id).helperPersonID", "person.\(p.id).sleepingSpaceID", "person.\(hid).sleepingSpaceID"],
                 causedBy: cause, sources: ["S19"])
            requireSticky("req.assistance.reach.\(p.id)", cause: cause)
        }
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
        home.flatMap { ShelterSuitability.confirmedRoom(in: $0) }
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
        if household.housing.homeType != .manufacturedHome, let shelter = shelterSpace {
            routeToInterior(shelter, purpose: .interiorShelter, exclusions: .none)
        } else { recordUnavailableInterior(purpose: .interiorShelter, exclusions: .none) }
        updateSpatialScene(stage: cause, affected: [], destination: shelterSpace?.id,
                           assumption: "Exercise: household-chosen interior shelter, not an engineered safe room. Windows indicate exposure; opening windows does not help.")
        assistanceCheck(cause: cause, rule: "rule.tornado.assistance", sources: ["S22"])
    }

    // MARK: Flood

    mutating func householdLeak(cause: String) {
        guard let home else { return }
        let affected = input.effectiveSpatialOptions.floodAffectedSpaceIDs.filter { home.space($0) != nil }.sorted()
        // A household leak does not establish a need to go upstairs, a regional evacuation, a power
        // failure, impassable roads or a contaminated well. Do not borrow those regional-flood effects.
        currentRoutes = [:]
        updateSpatialScene(stage: cause, affected: affected,
            assumption: "Exercise: a local household leak affects only the selected spaces. This is separate from regional flood evacuation guidance. Keep away from water near electrical equipment; no route through the affected space is established.")
    }

    mutating func floodWarning(cause: String) {
        if let home {
            let affected = input.effectiveSpatialOptions.floodAffectedSpaceIDs.filter { home.space($0) != nil }.sorted()
            recordUnavailableInterior(purpose: .higherRefuge, exclusions: ScenarioExclusions(blockedSpaceIDs: affected))
            if let refugeID = input.effectiveSpatialOptions.refugeSpaceID, let refuge = home.space(refugeID),
               let targetFloor = home.floors.first(where: { $0.id == refuge.floorID }), targetFloor.exteriorGrade != .unknown,
               affected.allSatisfy({ id in
                   guard let room = home.space(id), let floor = home.floors.first(where: { $0.id == room.floorID }),
                         floor.exteriorGrade != nil, floor.exteriorGrade != .unknown else { return false }
                   return floor.elevationMeters < targetFloor.elevationMeters
               }), !affected.isEmpty, refuge.kind != .closet {
                routeToInterior(refuge, purpose: .higherRefuge, exclusions: ScenarioExclusions(blockedSpaceIDs: affected))
            }
            updateSpatialScene(stage: cause, affected: affected, destination: input.effectiveSpatialOptions.refugeSpaceID,
                               assumption: input.effectiveSpatialOptions.floodIsHouseholdLeak ? "Exercise: a local household leak affects only the selected spaces. This is separate from regional flood evacuation guidance. Keep away from water near electrical equipment; no route through the affected space is established."
                               : affected.isEmpty ? "Exercise: regional flood warning. Indoor water location is unknown; follow official instructions and act early. No indoor route is established."
                               : "Exercise: selected water-affected spaces are excluded. Higher refuge is considered only with recorded floor relationships; never cross water or enter a closed attic.")
        }
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

    mutating func advanceFloodScene(cause: String) {
        guard let home, var scene = spatialState, !scene.affectedSpaceIDs.isEmpty,
              !input.effectiveSpatialOptions.floodIsHouseholdLeak else { return }
        let affected = Set(scene.affectedSpaceIDs)
        // Adaptive timing evidence: who had a supported refuge approach or was already there
        // before this stage, computed from committed positions (authored playback unaffected).
        let refugeBefore = hazardProgress == nil ? [] : household.people.filter { person in
            guard let route = currentRoutes[person.id], route.request.purpose == .higherRefuge,
                  let destination = route.request.destinationSpaceID else { return false }
            return route.primary != nil || startSpace(for: person) == destination
        }
        var expanded = affected
        for portal in home.portals where portal.verification == .verified {
            guard case .space(let a) = portal.sideA, case .space(let b) = portal.sideB else { continue }
            for (from, to) in [(a,b), (b,a)] where affected.contains(from) {
                guard let source = home.space(from), let target = home.space(to),
                      let sourceFloor = home.floors.first(where: { $0.id == source.floorID }),
                      let targetFloor = home.floors.first(where: { $0.id == target.floorID }),
                      sourceFloor.exteriorGrade != nil, sourceFloor.exteriorGrade != .unknown,
                      targetFloor.exteriorGrade != nil, targetFloor.exteriorGrade != .unknown,
                      targetFloor.elevationMeters <= sourceFloor.elevationMeters else { continue }
                expanded.insert(to)
            }
        }
        let exclusions = ScenarioExclusions(blockedSpaceIDs: expanded.sorted())
        recordUnavailableInterior(purpose: .higherRefuge, exclusions: exclusions)
        if let destinationID = scene.destinationSpaceID, let destination = home.space(destinationID),
           !expanded.contains(destinationID), let targetFloor = home.floors.first(where: { $0.id == destination.floorID }),
           expanded.allSatisfy({ id in
               guard let room = home.space(id), let floor = home.floors.first(where: { $0.id == room.floorID }) else { return false }
               return floor.elevationMeters < targetFloor.elevationMeters
           }) { routeToInterior(destination, purpose: .higherRefuge, exclusions: exclusions) }
        if var progress = hazardProgress {
            for person in refugeBefore {
                let destination = scene.destinationSpaceID
                if startSpace(for: person) == destination, let destination, !expanded.contains(destination) {
                    progress.refugeHeldAtAccessLoss.insert(person.id)
                } else if currentRoutes[person.id]?.primary == nil {
                    progress.refugeLostAtAccessLoss.insert(person.id)
                }
            }
            hazardProgress = progress
        }
        scene.stageID = cause; scene.affectedSpaceIDs = expanded.sorted()
        scene.routes = currentRoutes.keys.sorted().compactMap { currentRoutes[$0] }
        scene.assumption = "Exercise: a later authored stage excludes connected lower spaces. This topology illustration is not a flood depth or arrival-time prediction."
        scene.assumptionKey = "spatial.assumption.flood-later"
        spatialState = scene
    }

    mutating func recordUnavailableInterior(purpose: RoutePurpose, exclusions: ScenarioExclusions) {
        guard let home else { return }
        for person in household.people.sorted(by: { $0.id < $1.id }) {
            currentRoutes[person.id] = planner.plan(RouteRequest(personID: person.id, startSpaceID: startSpace(for: person),
                mobility: mobility(for: person), exclusions: exclusions, purpose: purpose), in: home)
        }
    }

    mutating func routeToInterior(_ destination: Space, purpose: RoutePurpose, exclusions: ScenarioExclusions) {
        guard let home else { return }
        for person in household.people.sorted(by: { $0.id < $1.id }) {
            currentRoutes[person.id] = planner.plan(RouteRequest(personID: person.id, startSpaceID: startSpace(for: person),
                mobility: mobility(for: person), exclusions: exclusions, purpose: purpose, destinationSpaceID: destination.id), in: home)
        }
    }

    mutating func updateSpatialScene(stage: String, affected: [String], portals: [String] = [], destination: String? = nil, assumption: String) {
        guard let home else { spatialState = nil; return }
        let origin = spatialState?.originSpaceID ?? affected.first
        let assumptionKey: String
        switch scenario.hazard {
        case .homeFire: assumptionKey = affected.isEmpty ? "spatial.assumption.fire-before" : "spatial.assumption.fire-blocked"
        case .tornado: assumptionKey = "spatial.assumption.tornado"
        case .flashFlood: assumptionKey = input.effectiveSpatialOptions.floodIsHouseholdLeak ? "spatial.assumption.leak" : affected.isEmpty ? "spatial.assumption.flood-unknown" : "spatial.assumption.flood-selected"
        default: assumptionKey = "spatial.assumption.unknown"
        }
        let exposed = scenario.hazard == .tornado ? home.portals.filter { $0.kind == .window }.flatMap { portal in
            [portal.sideA, portal.sideB].compactMap { side -> String? in if case .space(let id) = side { return id }; return nil }
        } : []
        spatialState = SpatialExerciseState(hazard: scenario.hazard, seed: input.seed, stageID: stage, originSpaceID: origin,
            affectedSpaceIDs: affected, affectedPortalIDs: portals, destinationSpaceID: destination,
            routes: currentRoutes.keys.sorted().compactMap { currentRoutes[$0] }, assumption: assumption, assumptionKey: assumptionKey, exposedSpaceIDs: Array(Set(exposed)).sorted())
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
            guard household.housing.homeType != .manufacturedHome, let home, let shelter = shelterSpace,
                  !household.people.isEmpty else { return false }
            // A suitable room is not an accessible plan. Use the same authoritative graph,
            // mobility constraints and exercise exclusions as movement, for every occupant.
            let exclusions = ScenarioExclusions(blockedSpaceIDs: spatialState?.affectedSpaceIDs ?? [],
                                               blockedPortalIDs: spatialState?.affectedPortalIDs ?? [])
            return household.people.allSatisfy { person in
                planner.plan(RouteRequest(personID: person.id, startSpaceID: startSpace(for: person),
                    mobility: mobility(for: person), exclusions: exclusions, purpose: .interiorShelter,
                    destinationSpaceID: shelter.id), in: home).primary != nil
            }
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
            let outsideAction = c.id == "choice.home-fire.outside" && $0.effect == "takeExit"
            return DecisionPoint.Option(id: $0.id, labelKey: $0.labelKey, feedbackKey: $0.feedbackKey,
                isRecommended: !$0.unsafe && feasible($0.effect) && (!outsideAction || household.people.contains { isOutside($0.id) }))
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
        applySpatialChoice(opt, choice: c, cause: id)
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
        case "shelterInPlace":
            // Adaptive sessions only (authored playback has no HazardProgress): record what the stay
            // committed to. Choosing to stay never manufactures warmth, cooling or device power.
            recordThermalStay(choiceID: c.id, eventID: id)
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
