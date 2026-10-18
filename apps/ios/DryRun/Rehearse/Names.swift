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
        return UnknownNames.fallback(id)
    }

    /// "1 charge", "2 charges", "5 gal": a resource amount with a unit that agrees with the number.
    static func quantity(_ amount: Double, unit: String) -> String {
        let n = PlanFormatting.number(amount)
        let singular = ["charges": "charge", "days": "day", "people": "person"]
        let u = amount == 1 ? (singular[unit] ?? unit) : unit
        return u.isEmpty ? n : "\(n) \(u)"
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
    static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
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
            if !value.isMissing { return value.text }
        }
        func fact(_ key: String, _ name: String, _ fallback: String) -> String {
            localizer?("spatial.fact." + key, ["name": name]) ?? fallback
        }
        if let n = names[id] { return n }
        let parts = id.split(separator: ".", maxSplits: 2).map(String.init)
        if parts.count >= 2, parts[0] == "equipment" {
            let device = HouseholdLabels.equipment(parts[1], in: household, localizer: localizer)
            switch parts.count > 2 ? parts[2] : "" {
            case "backup": return fact("equipment.backup", device, "A backup that works with \(device)")
            case "runtime", "documentedBackupRuntimeHours": return fact("equipment.runtime", device, "How long \(device) runs on its backup")
            case "backupOutcome": return fact("equipment.backupOutcome", device, "Whether \(device)'s backup lasts through the outage")
            default: return device
            }
        }
        if parts.count >= 2, parts[0] == "backup" {
            let backup = HouseholdLabels.backup(parts[1], in: household, localizer: localizer)
            switch parts.count > 2 ? parts[2] : "" {
            case "setupConfirmed": return fact("backup.setup", backup, "Whether \(backup) is set up and tested")
            case "usableEnergyWh": return fact("backup.energy", backup, "How much energy \(backup) holds")
            case "safeOutdoorPlacementConfirmed": return fact("backup.outdoor", backup, "A safe outdoor spot for \(backup)")
            default: return backup
            }
        }
        if parts.count >= 2, parts[0] == "person" {
            let name = household?.people.first { $0.id == parts[1] }?.alias ?? "A household member"
            switch parts.count > 2 ? parts[2] : "" {
            case "sleepingSpaceID": return fact("person.start", name, "Where \(name) sleeps")
            case "helperPersonID": return fact("person.helper", name, "Who helps \(name)")
            case "needs": return fact("person.needs", name, "What \(name) needs")
            default: return name
            }
        }
        return ServiceNames.names[id] ?? fallback(id)
    }

    /// Last resort for an ID with no name yet: the final segment, de-camel-cased ("routerOnBackup" → "router on backup").
    static func fallback(_ id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        let spaced = last.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}
