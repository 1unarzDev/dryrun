import Foundation

/// Stable content fingerprint of a home (FNV-1a 64 over sorted-key JSON). Catches edits even if a caller
/// forgot to bump `revision`.
public enum HomeFingerprint {
    public static func of(_ home: HomeModel) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = (try? enc.encode(home)) ?? Data()
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
        return String(h, radix: 16)
    }
}

public struct RouteCacheKey: Hashable, Sendable {
    public var homeID: String
    public var homeRevision: Int
    public var homeFingerprint: String
    public var request: RouteRequest
    public var algorithmVersion: String
    public init(home: HomeModel, request: RouteRequest) {
        homeID = home.id; homeRevision = home.revision; homeFingerprint = HomeFingerprint.of(home)
        self.request = request; algorithmVersion = RouteResult.algorithmVersion
    }
}

/// Thread-safe memo of route results. A result is only returned for the exact home revision AND content
/// fingerprint it was computed from, so an edited doorway can never serve an old "good" route.
public final class RouteCache: @unchecked Sendable {
    private var storage: [RouteCacheKey: RouteResult] = [:]
    private let lock = NSLock()
    private let planner: EgressPlanning

    public init(planner: EgressPlanning = EgressPlanner()) { self.planner = planner }

    public func route(_ request: RouteRequest, in home: HomeModel) -> RouteResult {
        let key = RouteCacheKey(home: home, request: request)
        lock.lock()
        if let hit = storage[key] { lock.unlock(); return hit }
        lock.unlock()
        let result = planner.plan(request, in: home)
        lock.lock()
        // Drop every entry for older revisions/fingerprints of this home.
        storage = storage.filter { $0.key.homeID != home.id || ($0.key.homeRevision == key.homeRevision && $0.key.homeFingerprint == key.homeFingerprint) }
        storage[key] = result
        lock.unlock()
        return result
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }

    public func invalidateAll() { lock.lock(); storage.removeAll(); lock.unlock() }
}

extension RouteResult {
    /// True only if this result was computed for this exact home revision and algorithm.
    public func isCurrent(for home: HomeModel) -> Bool {
        homeID == home.id && homeRevision == home.revision && algorithmVersion == RouteResult.algorithmVersion
    }
}

extension HomeModel {
    /// Apply an edit and bump the revision so every dependent route/result/plan cache is invalidated.
    public mutating func edit(_ change: (inout HomeModel) -> Void) {
        change(&self)
        bumpRevision()
    }
}
