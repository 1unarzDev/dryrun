import Foundation

/// Readable names for core enums shown in pickers and summaries, so raw case names ("singleFamily") never reach the
/// screen. English only, like the rest of the setup forms; `common.*` locale keys are used where they exist.
enum DisplayNames {
    /// Cases whose de-camel-cased name reads wrong (acronyms, awkward phrasing).
    static let overrides: [String: String] = [
        "centralAC": "Central AC",
        "windowOrPortableAC": "Window or portable AC",
        "cpapOrBipap": "CPAP or BiPAP",
        "fansOnly": "Fans only",
        "municipal": "City water",
        "privateWell": "Private well",
        "septicGravity": "Septic (gravity)",
        "septicWithPump": "Septic with pump",
        "naturalGas": "Natural gas",
        "olderAdult": "Older adult",
        "smallAnimal": "Small animal",
        "singleFamily": "Single-family house",
        "coAlarm": "CO alarm",
        "utilityShutoffWater": "Water shutoff",
        "utilityShutoffGas": "Gas shutoff",
        "utilityShutoffElectric": "Electrical shutoff",
        "tornadoShelterCandidate": "Tornado shelter spot",
        "solarGridTiedOnly": "Solar (grid-tied only)",
        "solarWithBattery": "Solar with battery",
        "deviceInternalBattery": "Device's own battery",
        "friendOrFamilyHome": "Friend or family home",
        "none": "None",
        "unknown": "Not sure",
    ]

    static func name(_ raw: String) -> String {
        if let n = overrides[raw] { return n }
        let spaced = raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}

extension RawRepresentable where RawValue == String {
    var displayName: String { DisplayNames.name(rawValue) }
}
