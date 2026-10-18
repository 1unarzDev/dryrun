import Foundation
import DryRunCore

enum ServiceNames {
    static let names = [
        "svc.grid": "Grid power", "svc.heat": "Heat", "svc.cooling": "Cooling", "svc.refrigeration": "Refrigeration",
        "svc.wellPump": "Well pump", "svc.water.supply": "Water supply", "svc.water.safety": "Water safety",
        "svc.wifi": "Home Wi-Fi", "svc.cellular": "Cell service", "svc.handset": "Phone battery", "svc.roads": "Roads",
        "svc.transport": "Transport", "res.water.stored": "Stored water", "res.handset.charge": "Phone charge",
        "res.food.days": "Food", "res.handset.hours": "Phone battery time",
        "res.handset.powerBankCharges": "Power bank charges", "svc.power.home": "Home power", "svc.alerts": "Warnings received",
        "svc.destination": "Place to go", "svc.relocated": "Relocated", "svc.water.municipal": "City water supply",
        "svc.water.utilitySafety": "Utility water safety", "svc.water.wellSafety": "Well water safety",
        "svc.wellPump.mechanical": "Well pump (equipment)", "svc.internet": "Internet",
    ]
    /// Device and backup IDs become the labels the household gave them; raw IDs never reach the screen.
    static func name(_ id: String, household: HouseholdProfile?, localizer: Localizer? = nil) -> String {
        if let localizer {
            let value = localizer.text("spatial.service." + id)
            if !value.isMissing { return value.text }
        }
        if let n = names[id] { return n }
        if id.hasPrefix("svc.device.") { return HouseholdLabels.equipment(String(id.dropFirst("svc.device.".count)), in: household, localizer: localizer) }
        if id.hasPrefix("res.backup.") {
            let name = HouseholdLabels.backup(String(id.dropFirst("res.backup.".count)), in: household, localizer: localizer)
            return localizer?("spatial.backup-energy", ["name": name]) ?? "Backup energy: \(name)"
        }
        if id.hasPrefix("res.device."), id.hasSuffix(".runtime") {
            let eid = String(id.dropFirst("res.device.".count).dropLast(".runtime".count))
            let name = HouseholdLabels.equipment(eid, in: household, localizer: localizer)
            return localizer?("spatial.device-runtime", ["name": name]) ?? "\(name) runtime"
        }
        return UnknownNames.fallback(id, localizer: localizer)
    }

    /// Localized presentation only. Evidence keeps its original stable unit string.
    static func quantity(_ amount: Double, unit: String, localizer: Localizer) -> String {
        guard amount.isFinite else { return localizer("common.status.unknown") }
        let number = PlanFormatting.number(amount, locale: localizer.locale)
        if unit.isEmpty { return number }
        let key: String?
        switch unit {
        case "gal": key = "gallons"
        case "h", "hours": key = "hours"
        case "charges": key = "charges"
        case "days": key = "days"
        case "people": key = "people"
        case "Wh": key = "watt-hours"
        case "L": key = "litres"
        default: key = nil
        }
        guard let key else { return localizer("spatial.quantity.unspecified", ["number": number]) }
        return localizer("spatial.quantity.\(key).\(amount == 1 ? "one" : "other")", ["number": number])
    }
}

/// Household-given names for equipment and backup sources, looked up by ID.
enum HouseholdLabels {
    static func equipment(_ id: String, in household: HouseholdProfile?, localizer: Localizer? = nil) -> String {
        guard let equipment = household?.equipment.first(where: { $0.id == id }) else { return localizer?("family.equipment") ?? "Essential device" }
        if !equipment.label.isEmpty { return equipment.label }
        return localizer.map { DisplayNames.name(equipment.purpose.rawValue, localizer: $0) } ?? equipment.purpose.displayName
    }
    static func backup(_ id: String, in household: HouseholdProfile?, localizer: Localizer? = nil) -> String {
        guard let backup = household?.backupPower.first(where: { $0.id == id }) else { return localizer?("family.backup") ?? "backup power source" }
        if !backup.label.isEmpty { return backup.label }
        return localizer.map { DisplayNames.name(backup.kind.rawValue, localizer: $0) } ?? backup.kind.displayName
    }
}

enum PlanFormatting {
    static func number(_ v: Double, locale: String? = nil) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: locale ?? "en")))
    }
}

/// Plain-language names for the household facts a rehearsal or preparation depends on (IDs from the core engine).
enum UnknownNames {
    static let names = [
        "housing.heatingNeedsElectricity": "Whether your heating needs electricity",
        "housing.heatingFuel": "What fuel your heating uses",
        "housing.cooling": "How your home is cooled",
        "housing.homeType": "Your type of home",
        "housing.waterSource": "Where your water comes from",
        "housing.wellPumpElectric": "Whether your well pump needs electricity",
        "housing.wellPressureTankGallons": "How much water your well pressure tank holds",
        "supplies.storedWaterGallons": "How much water you have stored",
        "supplies.coolerAndIcePacks": "Whether you have a cooler and ice packs",
        "pets.waterNeeds": "How much water your pets need",
        "home.smokeAlarms": "Whether your smoke alarms work",
        "home.portals": "Your home's doors and windows",
        "home.spaces": "Your home's rooms",
        "home.annotations": "Your meeting point and shelter spot",
        "people.needs.usesWheelchair": "Whether someone uses a wheelchair",
        "communications.batteryOrCrankRadio": "Whether you have a battery or crank radio",
        "communications.handsetRuntimeHours": "How long your phones last on battery",
        "communications.powerBankCharges": "How many phone charges your power banks hold",
        "communications.routerOnBackup": "Whether your internet router has backup power",
    ]

    static func describe(_ id: String, household: HouseholdProfile?, localizer: Localizer? = nil) -> String {
        if let localizer {
            let value = localizer.text("spatial.fact." + id)
            if !value.isMissing && value.unfilledPlaceholders.isEmpty { return value.text }
        }
        func fact(_ key: String, _ name: String, _ fallback: String) -> String {
            localizer?("spatial.fact." + key, ["name": name]) ?? fallback
        }
        if let n = names[id] { return n }
        if let subject = subject(in: id, prefix: "equipment", knownIDs: household?.equipment.map(\.id) ?? []) {
            let device = HouseholdLabels.equipment(subject.id, in: household, localizer: localizer)
            switch subject.suffix {
            case "": return device
            case "backup": return fact("equipment.backup", device, "A backup that works with \(device)")
            case "runtime", "documentedBackupRuntimeHours": return fact("equipment.runtime", device, "How long \(device) runs on its backup")
            case "backupOutcome": return fact("equipment.backupOutcome", device, "Whether \(device)'s backup lasts through the outage")
            default: return fallback(id, localizer: localizer)
            }
        }
        if let subject = subject(in: id, prefix: "backup", knownIDs: household?.backupPower.map(\.id) ?? []) {
            let backup = HouseholdLabels.backup(subject.id, in: household, localizer: localizer)
            switch subject.suffix {
            case "": return backup
            case "setupConfirmed": return fact("backup.setup", backup, "Whether \(backup) is set up and tested")
            case "usableEnergyWh": return fact("backup.energy", backup, "How much energy \(backup) holds")
            case "safeOutdoorPlacementConfirmed": return fact("backup.outdoor", backup, "A safe outdoor spot for \(backup)")
            default: return fallback(id, localizer: localizer)
            }
        }
        if let subject = subject(in: id, prefix: "person", knownIDs: household?.people.map(\.id) ?? []),
           let person = household?.people.first(where: { $0.id == subject.id }) {
            let name = localizer.map { person.localizedLabel($0) }
                ?? (person.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (person.isSelf == true ? "You" : "Person") : person.alias)
            switch subject.suffix {
            case "": return name
            case "sleepingSpaceID": return fact("person.start", name, "Where \(name) starts")
            case "helperPersonID": return fact("person.helper", name, "Who helps \(name)")
            case "needs": return fact("person.needs", name, "What \(name) needs")
            default: return fallback(id, localizer: localizer)
            }
        }
        if ServiceNames.names[id] != nil { return ServiceNames.name(id, household: household, localizer: localizer) }
        return fallback(id, localizer: localizer)
    }

    /// IDs are opaque and may contain dots. Match a complete known subject before interpreting its suffix.
    private static func subject(in factID: String, prefix: String, knownIDs: [String]) -> (id: String, suffix: String)? {
        for subjectID in knownIDs.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }) {
            let base = prefix + "." + subjectID
            if factID == base { return (subjectID, "") }
            if factID.hasPrefix(base + ".") { return (subjectID, String(factID.dropFirst(base.count + 1))) }
        }
        return nil
    }

    /// Unrecognized facts must not expose internal IDs or look like translated advice.
    static func fallback(_ id: String, localizer: Localizer? = nil) -> String {
        localizer?("spatial.information-to-record") ?? "Information still to record"
    }
}
