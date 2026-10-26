import DryRunCore
import Foundation

public enum PublicPackError: Error, Sendable, Equatable {
    case tooLarge(Int)
    case malformed(String)
    case unsupportedSchema(Int)
    case invalid(String)
    case writeFailed(String)
    /// The response is for a different region than the one requested (server/CDN mix-up).
    case regionMismatch(expected: String, found: String)
}

/// Known-good cache of PUBLIC packs (not encrypted; contains no household data).
/// An update is validated and re-encoded from typed values (unknown keys are dropped) before an
/// atomic replace. A malformed, oversized, or untrusted update leaves the previous good copy in place.
public actor PublicPackStore {
    public static let maxPackBytes = 2 * 1024 * 1024
    public static let maxAlertBytes = 512 * 1024
    public static let supportedSchemaVersion = 1

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Known-good packs are keyed by the region the app ASKED for, so offline lookup needs only the region ID.
    private func packURL(_ regionID: String) -> URL { directory.appendingPathComponent("pack-region-\(regionID).json") }
    private func alertsURL(_ id: String) -> URL { directory.appendingPathComponent("alerts-\(id).json") }

    /// Validates a pack fetched for `expectedRegionID` and makes it the known-good copy for that region.
    @discardableResult
    public func updatePack(_ data: Data, expectedRegionID: String) throws(PublicPackError) -> RegionPack {
        guard PublicDataPolicy.isAllowedRegionID(expectedRegionID) else { throw .invalid("expected regionID") }
        guard data.count <= Self.maxPackBytes else { throw .tooLarge(data.count) }
        let pack: RegionPack
        do { pack = try DryRunJSON.decoder().decode(RegionPack.self, from: data) } catch { throw .malformed("\(error)") }
        try Self.validate(pack)
        guard pack.regions.contains(where: { $0.id == expectedRegionID }) else {
            throw .regionMismatch(expected: expectedRegionID, found: pack.regions.map(\.id).joined(separator: ","))
        }
        try write(pack, to: packURL(expectedRegionID))
        return pack
    }

    public func knownGoodPack(regionID: String) -> RegionPack? {
        guard PublicDataPolicy.isAllowedRegionID(regionID),
              let d = FileManager.default.contents(atPath: packURL(regionID).path) else { return nil }
        return try? DryRunJSON.decoder().decode(RegionPack.self, from: d)
    }

    @discardableResult
    public func updateAlerts(_ data: Data, expectedRegionID: String) throws(PublicPackError) -> AlertsEnvelope {
        guard data.count <= Self.maxAlertBytes else { throw .tooLarge(data.count) }
        let env: AlertsEnvelope
        do { env = try DryRunJSON.decoder().decode(AlertsEnvelope.self, from: data) } catch { throw .malformed("\(error)") }
        guard env.schemaVersion == Self.supportedSchemaVersion else { throw .unsupportedSchema(env.schemaVersion) }
        guard PublicDataPolicy.isAllowedRegionID(env.regionID) else { throw .invalid("regionID") }
        guard env.regionID == expectedRegionID else { throw .regionMismatch(expected: expectedRegionID, found: env.regionID) }
        for a in env.alerts where !Self.isHTTPS(a.sourceURL) { throw .invalid("alert source URL must be https") }
        try write(env, to: alertsURL(env.regionID))
        return env
    }

    /// Cached alerts. Callers MUST pass them through PublicDataPolicy.freshness before display;
    /// an expired cached alert is never current even offline.
    public func cachedAlerts(regionID: String) -> AlertsEnvelope? {
        guard PublicDataPolicy.isAllowedRegionID(regionID),
              let d = FileManager.default.contents(atPath: alertsURL(regionID).path) else { return nil }
        return try? DryRunJSON.decoder().decode(AlertsEnvelope.self, from: d)
    }

    // MARK: Validation

    static func isSafeID(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    static func isHTTPS(_ s: String) -> Bool {
        guard let u = URL(string: s), u.scheme == "https", let host = u.host, !host.isEmpty else { return false }
        return true
    }

    static func validate(_ pack: RegionPack) throws(PublicPackError) {
        guard pack.schemaVersion == supportedSchemaVersion else { throw .unsupportedSchema(pack.schemaVersion) }
        guard isSafeID(pack.packID) else { throw .invalid("packID") }
        guard !pack.contentVersion.isEmpty else { throw .invalid("contentVersion") }
        guard !pack.sources.isEmpty else { throw .invalid("no sources") }
        let sourceIDs = Set(pack.sources.map(\.id))
        for s in pack.sources where !isHTTPS(s.url) { throw .invalid("source \(s.id) url") }
        for r in pack.regions where !PublicDataPolicy.isAllowedRegionID(r.id) { throw .invalid("region \(r.id)") }
        for r in pack.resources {
            guard !r.sourceIDs.isEmpty, r.sourceIDs.allSatisfy(sourceIDs.contains) else {
                throw .invalid("resource \(r.id) cites unknown source")
            }
            if let u = r.contact.url, !isHTTPS(u) { throw .invalid("resource \(r.id) url") }
            // Coordinates are optional for list-only contacts, but a partial,
            // out-of-range, or unproven pair must never become a map marker.
            let hasLatitude = r.latitude != nil
            let hasLongitude = r.longitude != nil
            guard hasLatitude == hasLongitude else { throw .invalid("resource \(r.id) coordinate pair") }
            if let latitude = r.latitude, let longitude = r.longitude {
                guard GeographicCoordinate(latitude: latitude, longitude: longitude) != nil else {
                    throw .invalid("resource \(r.id) coordinate range")
                }
                guard let coordinateSourceIDs = r.coordinateSourceIDs,
                      !coordinateSourceIDs.isEmpty,
                      coordinateSourceIDs.allSatisfy(sourceIDs.contains) else {
                    throw .invalid("resource \(r.id) coordinate source")
                }
            }
            // A pack may not claim activation without an expiry: activation is a time-bound fact.
            if r.activation == .active && r.expiresAt == nil { throw .invalid("resource \(r.id) active without expiry") }
        }
        for region in pack.regions {
            let hasLatitude = region.mapCenterLatitude != nil
            let hasLongitude = region.mapCenterLongitude != nil
            guard hasLatitude == hasLongitude else { throw .invalid("region \(region.id) map center pair") }
            let hasLatitudeSpan = region.mapSpanLatitude != nil
            let hasLongitudeSpan = region.mapSpanLongitude != nil
            guard hasLatitudeSpan == hasLongitudeSpan else { throw .invalid("region \(region.id) map span pair") }
            if let latitude = region.mapCenterLatitude, let longitude = region.mapCenterLongitude {
                guard GeographicCoordinate(latitude: latitude, longitude: longitude) != nil else {
                    throw .invalid("region \(region.id) map center range")
                }
            }
            if let span = region.mapSpanLatitude {
                guard span.isFinite, span > 0, span <= 180 else { throw .invalid("region \(region.id) latitude span") }
            }
            if let span = region.mapSpanLongitude {
                guard span.isFinite, span > 0, span <= 360 else { throw .invalid("region \(region.id) longitude span") }
            }
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws(PublicPackError) {
        do {
            let data = try DryRunJSON.encoder().encode(value)
            try AtomicFile.write(data, to: url, protection: nil)
        } catch { throw .writeFailed("\(error)") }
    }
}
