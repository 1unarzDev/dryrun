import Foundation

/// Active National Weather Service alerts (api.weather.gov, source S17) reduced to what Dry Run shows, and the
/// rehearsal each alert type corresponds to. Parsing and mapping are pure; the app's transport fetches the public feed
/// for a fixed county zone and sends nothing about the household.
public struct WeatherAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var event: String
    public var headline: String?
    public var areaDescription: String
    public var severity: String
    public var urgency: String
    public var effective: Date?
    public var expires: Date?
    /// Recorded demo alerts are labelled as such everywhere they appear.
    public var isSample: Bool

    public init(id: String, event: String, headline: String?, areaDescription: String, severity: String, urgency: String,
                effective: Date?, expires: Date?, isSample: Bool = false) {
        self.id = id; self.event = event; self.headline = headline; self.areaDescription = areaDescription
        self.severity = severity; self.urgency = urgency; self.effective = effective; self.expires = expires; self.isSample = isSample
    }
}

public enum WeatherAlerts {
    /// Tarrant County's NWS county zone (UGC listing, source S43).
    public static let tarrantCountyZone = "TXC439"

    public enum Level: Int, Comparable, Sendable {
        case advisory = 1, watch = 2, warning = 3
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// Alert type → rehearsal. Only types whose protective actions a rehearsal actually practices are mapped; any
    /// other alert is still shown, without a "Rehearse this now" button.
    static let scenarios: [String: String] = [
        "Tornado Warning": "tornado", "Tornado Watch": "tornado",
        "Severe Thunderstorm Warning": "tornado", "Severe Thunderstorm Watch": "tornado",
        "Flash Flood Warning": "flash-flood", "Flash Flood Watch": "flash-flood", "Flood Warning": "flash-flood",
        "Flood Watch": "flash-flood", "Flood Advisory": "flash-flood",
        "Extreme Heat Warning": "heat-grid-strain", "Extreme Heat Watch": "heat-grid-strain", "Heat Advisory": "heat-grid-strain",
        "Excessive Heat Warning": "heat-grid-strain", "Excessive Heat Watch": "heat-grid-strain",
        "Winter Storm Warning": "freeze-power-loss", "Winter Storm Watch": "freeze-power-loss", "Ice Storm Warning": "freeze-power-loss",
        "Winter Weather Advisory": "freeze-power-loss", "Extreme Cold Warning": "freeze-power-loss", "Extreme Cold Watch": "freeze-power-loss",
        "Cold Weather Advisory": "freeze-power-loss", "Hard Freeze Warning": "freeze-power-loss", "Freeze Warning": "freeze-power-loss",
        "Wind Chill Warning": "freeze-power-loss", "Wind Chill Advisory": "freeze-power-loss",
    ]

    public static func scenarioID(for event: String) -> String? { scenarios[event] }

    public static func level(of event: String) -> Level {
        if event.hasSuffix("Warning") { return .warning }
        if event.hasSuffix("Watch") { return .watch }
        return .advisory
    }

    private struct Collection: Decodable {
        struct Feature: Decodable { let properties: Properties }
        struct Properties: Decodable {
            let id: String
            let event: String
            let headline: String?
            let areaDesc: String?
            let severity: String?
            let urgency: String?
            let effective: String?
            let expires: String?
            let ends: String?
            let status: String?
            let messageType: String?
        }
        let features: [Feature]
    }

    /// Parses an `application/geo+json` alerts response. Tests, exercises and cancellations are dropped.
    public static func parse(_ data: Data, isSample: Bool = false) throws -> [WeatherAlert] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let collection = try JSONDecoder().decode(Collection.self, from: data)
        return collection.features.compactMap { feature in
            let p = feature.properties
            guard (p.status ?? "Actual") == "Actual" || isSample, p.messageType != "Cancel" else { return nil }
            return WeatherAlert(id: p.id, event: p.event, headline: p.headline, areaDescription: p.areaDesc ?? "",
                                severity: p.severity ?? "Unknown", urgency: p.urgency ?? "Unknown",
                                effective: p.effective.flatMap(formatter.date(from:)),
                                expires: (p.ends ?? p.expires).flatMap(formatter.date(from:)), isSample: isSample)
        }
    }

    /// The alert to put first: unexpired, mapped to a rehearsal when possible, warnings before watches before advisories.
    public static func leading(_ alerts: [WeatherAlert], now: Date) -> WeatherAlert? {
        alerts.filter { $0.isSample || ($0.expires.map { $0 > now } ?? true) }
            .max { a, b in
                let ka = (level(of: a.event), scenarioID(for: a.event) != nil, a.effective ?? .distantPast)
                let kb = (level(of: b.event), scenarioID(for: b.event) != nil, b.effective ?? .distantPast)
                if ka.0 != kb.0 { return ka.0 < kb.0 }
                if ka.1 != kb.1 { return !ka.1 }
                return ka.2 < kb.2
            }
    }
}
