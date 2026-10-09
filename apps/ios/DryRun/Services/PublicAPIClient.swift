import DryRunCore
import DryRunVault
import Foundation

/// Typed client for the Dry Run PUBLIC API. Requests are built only by `PublicQueryBuilder`
/// from allowlisted public values (region ID, locale, content version, source ID). There is no
/// API that accepts a household value. Offline or failed updates fall back to the known-good cache.
public actor PublicAPIClient {
    public enum Freshness: Sendable, Equatable {
        case updated
        /// Network unavailable/failed; showing the cached pack from this date (if any).
        case cached(generatedAt: String?)
        case unavailable
    }

    private let baseURL: URL?
    private let session: URLSession
    private let store: PublicPackStore

    /// `baseURL == nil` (the default build) means: no deployed backend; bundled packs only.
    public init(baseURL: URL?, store: PublicPackStore) {
        self.baseURL = baseURL
        self.store = store
        let config = URLSessionConfiguration.ephemeral // no cookies, no URL cache on disk
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    private func get(_ endpoint: PublicEndpoint, maxBytes: Int) async throws -> Data {
        guard let baseURL else { throw URLError(.notConnectedToInternet) }
        let url = try PublicQueryBuilder.url(base: baseURL, endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    /// Fetches and validates a region pack; on any failure the previous known-good pack stays in use.
    public func refreshRegionPack(regionID: String, cachedPackID: String) async -> (RegionPack?, Freshness) {
        do {
            let data = try await get(.regionPack(regionID: regionID), maxBytes: PublicPackStore.maxPackBytes)
            let pack = try await store.updatePack(data)
            return (pack, .updated)
        } catch {
            let cached = await store.knownGoodPack(id: cachedPackID)
            return (cached, cached == nil ? .unavailable : .cached(generatedAt: cached?.generatedAt))
        }
    }

    /// Alerts. Callers must display only `PublicDataPolicy.currentOfficialAlerts(_, now:)`;
    /// offline this returns the cached envelope whose alerts expire on schedule.
    public func refreshAlerts(regionID: String) async -> (AlertsEnvelope?, Freshness) {
        do {
            let data = try await get(.regionAlerts(regionID: regionID), maxBytes: PublicPackStore.maxAlertBytes)
            let env = try await store.updateAlerts(data)
            return (env, .updated)
        } catch {
            let cached = await store.cachedAlerts(regionID: regionID)
            return (cached, cached == nil ? .unavailable : .cached(generatedAt: cached?.fetchedAt))
        }
    }
}
