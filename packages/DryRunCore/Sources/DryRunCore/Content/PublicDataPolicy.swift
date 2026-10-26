import Foundation

// Public-data display and request policy. Owner: Agent C.
// Rules: expired or demo alerts never display as current official warnings (online or offline);
// a map POI is never an activated shelter without source evidence; unknown is never "open" or "closed";
// the public network interface accepts only allowlisted public fields.

public enum AlertFreshness: String, Codable, Sendable, Hashable {
    /// Official live alert, within its validity window, fetched recently enough.
    case current
    /// Past `expires`/`ends`. Must not be shown as active, even if the network is down.
    case expired
    /// Still inside its validity window, but our copy is old (offline). Show with the fetch time, not as current.
    case stale
    /// Demo/fixture data. Never shown as a real official warning.
    case demo
    /// Missing/unparseable times: cannot be shown as current.
    case unknown

    public var mayDisplayAsCurrentOfficialWarning: Bool { self == .current }
}

public enum PublicDataPolicy {
    /// An alert copy older than this is "stale" even if the alert has not expired.
    public static let alertStaleAfter: TimeInterval = 30 * 60

    public static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    public static func freshness(of alert: PublicAlert, now: Date) -> AlertFreshness {
        if alert.classification != .live { return .demo }
        // Use the EARLIER of `ends` and `expires`: past either, the message is no longer current.
        let end = [parseDate(alert.ends), parseDate(alert.expires)].compactMap { $0 }.min()
        guard let end, let fetched = parseDate(alert.fetchedAt) else { return .unknown }
        if now >= end { return .expired }
        if now.timeIntervalSince(fetched) > alertStaleAfter { return .stale }
        return .current
    }

    /// Alerts that may be presented as current official warnings, in stable order.
    public static func currentOfficialAlerts(_ alerts: [PublicAlert], now: Date) -> [PublicAlert] {
        alerts.filter { freshness(of: $0, now: now) == .current }.sorted { $0.id < $1.id }
    }

    // MARK: Resource activation

    public enum ActivationDisplay: String, Codable, Sendable, Hashable {
        /// Source evidence says this site is activated now (and not expired).
        case confirmedActive
        case confirmedInactive
        /// No evidence of activation. Show "Check before going - activation not confirmed".
        case unconfirmed
        /// Offices, phone lines, registries: activation is not a concept.
        case notApplicable
    }

    static let siteTypes: Set<ResourceServiceType> = [.shelter, .warmingCenter, .coolingCenter]

    public static func activationDisplay(for r: PublicResource, now: Date) -> ActivationDisplay {
        guard siteTypes.contains(r.serviceType) else { return .notApplicable }
        // Activation needs live/curated source evidence that has not expired. Demo/fixture never counts.
        let hasEvidence = !r.sourceIDs.isEmpty && (r.classification == .live || r.classification == .curated)
        let notExpired = parseDate(r.expiresAt).map { now < $0 } ?? false
        switch r.activation {
        case .active where hasEvidence && notExpired: return .confirmedActive
        case .inactive where hasEvidence && notExpired: return .confirmedInactive
        default: return .unconfirmed
        }
    }

    // MARK: Region IDs

    /// Texas county FIPS (48 + 3 digits) or an explicit named grouping. Never an address or URL.
    public static func isAllowedRegionID(_ id: String) -> Bool {
        if id == "tx-statewide" || id == "tx-25" { return true }
        guard id.count == 5, id.hasPrefix("48") else { return false }
        return id.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// The ONLY way the app builds requests to the Dry Run public API. Accepts typed public fields;
/// there is no way to attach a household value. `validateQuery` is also enforced server-side.
public enum PublicEndpoint: Sendable, Hashable {
    case health
    case manifest
    case regionPack(regionID: String)
    case regionAlerts(regionID: String)
    case content(version: String, locale: String)
    case source(sourceID: String)
}

public enum PublicRequestError: Error, Sendable, Equatable {
    case invalidRegionID
    case invalidParameter(String)
    case unexpectedQueryKey(String)
}

public enum PublicQueryBuilder {
    public static let allowedLocales: Set<String> = ["en", "es", "vi"]
    /// No endpoint currently accepts query parameters.
    public static let allowedQueryKeys: Set<String> = []

    static func isSafeToken(_ s: String, max: Int = 40) -> Bool {
        !s.isEmpty && s.count <= max && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }
    }

    /// Returns a relative path such as "/v1/regions/48143/pack".
    public static func path(for endpoint: PublicEndpoint) throws(PublicRequestError) -> String {
        switch endpoint {
        case .health: return "/v1/health"
        case .manifest: return "/v1/manifest"
        case .regionPack(let id):
            guard PublicDataPolicy.isAllowedRegionID(id) else { throw .invalidRegionID }
            return "/v1/regions/\(id)/pack"
        case .regionAlerts(let id):
            guard PublicDataPolicy.isAllowedRegionID(id) else { throw .invalidRegionID }
            return "/v1/regions/\(id)/alerts"
        case .content(let version, let locale):
            guard isSafeToken(version) else { throw .invalidParameter("version") }
            guard allowedLocales.contains(locale) else { throw .invalidParameter("locale") }
            return "/v1/content/\(version)/\(locale)"
        case .source(let id):
            guard id.count <= 4, id.hasPrefix("S"), id.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw .invalidParameter("sourceID")
            }
            return "/v1/sources/\(id)"
        }
    }

    /// Rejects any query item not on the allowlist (there are none today).
    public static func validateQuery(_ items: [String: String]) throws(PublicRequestError) {
        for key in items.keys.sorted() where !allowedQueryKeys.contains(key) {
            throw .unexpectedQueryKey(key)
        }
    }

    public static func url(base: URL, endpoint: PublicEndpoint) throws(PublicRequestError) -> URL {
        let p = try path(for: endpoint)
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw .invalidParameter("base") }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + p
        comps.queryItems = nil
        guard let url = comps.url else { throw .invalidParameter("base") }
        return url
    }
}
