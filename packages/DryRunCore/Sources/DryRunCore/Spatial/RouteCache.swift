import Foundation

/// Stable content fingerprint of a home (FNV-1a 64 over sorted-key JSON). Catches edits even if a caller
/// forgot to bump `revision`.
public enum HomeFingerprint {
    public static func of(_ home: HomeModel) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        // NaN/inf must not make encoding fail (which would give every such home the same fingerprint).
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        let data: Data
        do { data = try enc.encode(home) } catch {
            // Unreachable for current types; still never collapse to a constant.
            data = Data(String(reflecting: home).utf8)
        }
        // Two independent FNV-1a 64 lanes (different offset bases) → 128-bit hex fingerprint.
        var h1: UInt64 = 0xcbf2_9ce4_8422_2325, h2: UInt64 = 0x6c62_272e_07bb_0142
        for b in data {
            h1 ^= UInt64(b); h1 = h1 &* 0x0000_0100_0000_01b3
            h2 = (h2 ^ UInt64(b &+ 0x5f)) &* 0x0000_0100_0000_01b3
        }
        return String(h1, radix: 16) + String(h2, radix: 16)
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
    /// True only if this result was computed for this exact home CONTENT (fingerprint), revision, and algorithm.
    /// A result without a fingerprint (older data) is never current.
    public func isCurrent(for home: HomeModel) -> Bool {
        guard let homeFingerprint else { return false }
        return homeID == home.id && homeRevision == home.revision && algorithmVersion == RouteResult.algorithmVersion
            && homeFingerprint == HomeFingerprint.of(home)
    }
}

extension HomeModel {
    /// Apply an edit and bump the revision so every dependent route/result/plan cache is invalidated.
    public mutating func edit(_ change: (inout HomeModel) -> Void) {
        change(&self)
        bumpRevision()
    }
}
