import Foundation

/// Presentation only. Recorded resource units and indoor metre geometry stay unchanged.
public enum PlanningMeasurements {
    public static func distance(meters: Double, countryCode: String?, localizer: Localizer) -> String {
        guard meters.isFinite, meters >= 0 else { return localizer("common.status.unknown") }
        let usesMiles = ["US", "GB"].contains(countryCode?.uppercased() ?? "")
        let unit: String
        let value: Double
        if usesMiles {
            if meters < 160.9344 { unit = "feet"; value = meters / 0.3048 }
            else { unit = "miles"; value = meters / 1609.344 }
        } else if meters < 1000 {
            unit = "meters"; value = meters
        } else {
            unit = "kilometers"; value = meters / 1000
        }
        let digits = unit == "feet" || unit == "meters" ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: localizer.locale)))
        return localizer("map.distance.\(unit)", ["number": number])
    }

    /// Stored water is canonical US gallons. Unknown country uses metric presentation, never an assumed US location.
    public static func water(gallons: Double, countryCode: String?, localizer: Localizer) -> String {
        waterText(gallons: gallons, countryCode: countryCode, localizer: localizer).text
    }

    static func waterText(gallons: Double, countryCode: String?, localizer: Localizer) -> LocalizedText {
        guard gallons.isFinite, gallons >= 0 else { return localizer.text("common.status.unknown") }
        let usesGallons = countryCode?.uppercased() == "US"
        let amount = usesGallons ? gallons : gallons * 3.785411784
        let number = amount.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: localizer.locale)))
        return localizer.text("spatial.quantity.\(usesGallons ? "gallons" : "litres").\(amount == 1 ? "one" : "other")", ["number": number])
    }

    /// Only known water fields are converted; user notes and unrelated numeric evidence remain exact.
    static func waterValues(_ values: [String: String], keys: [String], countryCode: String?, localizer: Localizer) -> [String: String] {
        var result = values
        for key in keys {
            if let raw = values[key] {
                result[key] = Double(raw).map { water(gallons: $0, countryCode: countryCode, localizer: localizer) }
                    ?? localizer("common.status.unknown")
            }
        }
        return result
    }

    public static func duration(seconds: Double, localizer: Localizer) -> String {
        guard seconds.isFinite, seconds >= 0 else { return localizer("common.status.unknown") }
        let minutes = (seconds / 60).rounded(.up).formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: localizer.locale)))
        return localizer("map.durationMinutes", ["minutes": minutes])
    }
}

extension SimulationEvent {
    /// Exercise facts keep canonical values. Only their displayed water quantities follow the home country.
    public func localizedTemplateValues(household: HouseholdProfile?, localizer: Localizer) -> [String: String] {
        let keys: [String]
        switch titleKey {
        case "scenario.common.checkpoint.water-target", "scenario.common.checkpoint.water-target-unknown":
            keys = ["target", "stored", "initial"]
        case "scenario.common.recovery.water-not-refilled": keys = ["stored"]
        default: keys = []
        }
        var values = PlanningMeasurements.waterValues(templateValues, keys: keys, countryCode: household?.privateLocation?.countryCode, localizer: localizer)
        // A subject can contain dots. Resolve the longest complete ID before interpreting field suffixes.
        func subject(_ prefix: String, _ ids: [String]) -> String? {
            let candidates = ids.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            for fact in evidence.factIDs {
                if let id = candidates.first(where: { fact == prefix + "." + $0 || fact.hasPrefix(prefix + "." + $0 + ".") }) { return id }
            }
            return nil
        }
        if let household {
            // A device event without an equipment fact still names its device service (svc.device.<id>).
            let changedDevice = serviceChanges.keys.sorted().compactMap { key -> String? in
                guard key.hasPrefix("svc.device.") else { return nil }
                let id = String(key.dropFirst("svc.device.".count))
                return household.equipment.contains(where: { $0.id == id }) ? id : nil
            }.first
            if values["device"] != nil, let id = subject("equipment", household.equipment.map(\.id)) ?? changedDevice,
               let device = household.equipment.first(where: { $0.id == id }) {
                values["device"] = device.receiptName(localizer)
            }
            if values["backup"] != nil, let id = subject("backup", household.backupPower.map(\.id)), let backup = household.backupPower.first(where: { $0.id == id }) {
                values["backup"] = backup.receiptName(localizer)
            }
            if values["person"] != nil, let id = subject("person", household.people.map(\.id)), let person = household.people.first(where: { $0.id == id }) {
                values["person"] = person.localizedLabel(localizer)
                if values["helper"] != nil, let helperID = person.helperPersonID, let helper = household.people.first(where: { $0.id == helperID }) {
                    values["helper"] = helper.localizedLabel(localizer)
                }
            }
        }
        for (key, fallback) in [("device", "family.equipment"), ("backup", "card.section.backup"), ("person", "ui.person"), ("helper", "ui.person")] {
            if values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { values[key] = localizer(fallback) }
        }
        if let reason = values["reason"] {
            let key = localizer.has("reason." + reason, in: "en") ? "reason." + reason : "plan.route.reason." + reason
            values["reason"] = localizer.has(key, in: "en") ? localizer(key) : localizer("common.status.unknown")
        }
        return values
    }

    /// The event's title as the family reads it (receipt labels sent with a debrief, timeline rows): household
    /// subjects resolved, device and backup names via `receiptName`, never a blank name.
    public func receiptTitle(household: HouseholdProfile?, localizer: Localizer) -> String {
        localizer(titleKey, localizedTemplateValues(household: household, localizer: localizer))
    }
}
