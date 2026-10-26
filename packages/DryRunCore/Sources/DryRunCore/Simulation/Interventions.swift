import Foundation

/// Applies "Try this change" interventions to SIMULATION COPIES of the household and home.
/// Hypothetical values are marked `origin: .scenarioAssumption` with status `.confirmed` so they satisfy
/// requirements inside the rehearsal while remaining distinguishable from real, user-confirmed facts.
/// "Mark preparation completed" is a separate operation on the real profile and is not done here.
public enum InterventionApplier {
    static func hypothetical<T>(_ v: T, unit: String? = nil) -> EvidenceValue<T> {
        EvidenceValue(value: v, origin: .scenarioAssumption, status: .confirmed, unit: unit)
    }

    public static func apply(_ interventions: [Intervention], household: HouseholdProfile, home: HomeModel?) -> (HouseholdProfile, HomeModel?) {
        var h = household
        var m = home
        for i in interventions { apply(i, &h, &m) }
        return (h, m)
    }

    /// Preserve source compatibility for geometry-backed callers while the optional overload serves no-layout runs.
    public static func apply(_ interventions: [Intervention], household: HouseholdProfile, home: HomeModel) -> (HouseholdProfile, HomeModel) {
        let (household, revisedHome) = apply(interventions, household: household, home: Optional(home))
        return (household, revisedHome ?? home)
    }

    static func apply(_ i: Intervention, _ h: inout HouseholdProfile, _ home: inout HomeModel?) {
        switch i.actionID {
        case "act.backup.confirm-medical-backup":
            let targets = h.equipment.indices.filter { idx in
                let eq = h.equipment[idx]
                return eq.isEssential && eq.requiresElectricalPower && (i.parameters["equipment"].map { $0 == eq.id } ?? true)
            }
            for idx in targets {
                // Prefer an existing battery station the household owns; otherwise a hypothetical compatible one.
                let existing = h.backupPower.first { [.portableBatteryStation, .solarWithBattery].contains($0.kind) }
                let bid: String
                if let b = existing { bid = b.id } else {
                    bid = "bk-try-\(h.equipment[idx].id)"
                    if !h.backupPower.contains(where: { $0.id == bid }) {
                        h.backupPower.append(BackupPowerSource(id: bid, kind: .portableBatteryStation, label: "Compatible backup (tried)",
                                                               setupConfirmed: hypothetical(true)))
                    }
                }
                if let bi = h.backupPower.firstIndex(where: { $0.id == bid }) { h.backupPower[bi].setupConfirmed = hypothetical(true) }
                if !h.equipment[idx].compatibleBackupIDs.contains(bid) { h.equipment[idx].compatibleBackupIDs.append(bid) }
            }
        case "act.water.store-3day":
            let target = Double(h.people.count) * 3.0
            let current = h.supplies.storedWaterGallons.confirmedValue ?? 0
            h.supplies.storedWaterGallons = hypothetical(max(current, target), unit: "gal")
        case "act.relocation.arrange", "act.tornado.sturdy-building-plan":
            if h.transport.destinations.allSatisfy({ $0.conditionsConfirmed.confirmedValue != true }) {
                h.transport.destinations.append(RelocationDestination(id: "dest-try", kind: .friendOrFamilyHome, label: "Agreed destination (tried)",
                                                                      conditionsConfirmed: hypothetical(true), acceptsPets: .unknown,
                                                                      stepFreeAccess: .unknown))
            }
            let wheelchair = h.people.contains { $0.needs.contains(.usesWheelchair) }
            let hasSuitableVehicle = h.transport.vehicles.contains { !wheelchair || $0.wheelchairAccessible.confirmedValue == true }
            let hasAgreed = h.transport.alternatives.contains { $0.agreed.confirmedValue == true && (!wheelchair || $0.wheelchairAccessible.confirmedValue == true) }
            if !hasSuitableVehicle && !hasAgreed {
                h.transport.alternatives.append(TransportAlternative(id: "ta-try", kind: .friendOrFamily, contactID: nil,
                                                                     wheelchairAccessible: wheelchair ? hypothetical(true) : .unknown,
                                                                     agreed: hypothetical(true)))
            }
        case "act.comms.power-bank":
            let c = h.communications.powerBankCharges.confirmedValue ?? 0
            h.communications.powerBankCharges = hypothetical(c + 2, unit: "charges")
        case "act.comms.weather-radio":
            h.communications.batteryOrCrankRadio = hypothetical(true)
        case "act.refrigeration.cooler-plan":
            h.supplies.coolerAndIcePacks = hypothetical(true)
        case "act.tornado.choose-shelter":
            guard var m = home else { return }
            let preferred: [SpaceKind] = [.closet, .bathroom, .hallway]
            for kind in preferred {
                if let idx = m.spaces.indices.sorted(by: { m.spaces[$0].id < m.spaces[$1].id })
                    .first(where: { m.spaces[$0].kind == kind && ShelterSuitability.canConfirm(roomID: m.spaces[$0].id, in: m) }) {
                    // Both the room answer and selection are hypothetical, confined to this simulation copy.
                    // Recorded windows, unknown floors and unreviewed corrections still cannot be overridden.
                    m.spaces[idx].interiorNoWindowsConfirmed = hypothetical(true)
                    m.annotations.removeAll { $0.kind == .tornadoShelterCandidate }
                    m.annotations.append(Annotation(id: "an-hypothetical-tornado-shelter-\(m.spaces[idx].id)",
                        kind: .tornadoShelterCandidate, floorID: m.spaces[idx].floorID, spaceID: m.spaces[idx].id,
                        label: m.spaces[idx].label, verification: .verified,
                        note: "Hypothetical exercise selection only; not a recorded household confirmation or an engineered safe room."))
                    break
                }
            }
            home = m
        case "act.assist.assign-helper":
            for idx in h.people.indices {
                let p = h.people[idx]
                let needs = p.needs.contains(.needsHelperToEvacuate) || p.needs.contains(.usesWheelchair) || p.needs.contains(.cannotUseStairs)
                    || p.ageBand == .infant || p.ageBand == .child || p.needs.contains(.deafOrHardOfHearing)
                if needs, p.helperPersonID == nil,
                   let helper = h.people.first(where: { $0.id != p.id && ($0.ageBand == .adult) && !$0.requiresStepFreeRoute }) {
                    h.people[idx].helperPersonID = helper.id
                }
            }
        default:
            break // Not modelable: the recommendation has no tryIntervention.
        }
    }
}
