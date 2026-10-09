@testable import DryRunCore
import Foundation
import Testing

/// Walks up from this file to the repository root (the directory containing content/regions).
private let repoRoot: URL = {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while url.path != "/" {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("content/regions").path) { return url }
        url.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: "/repo")
}()

private func alert(classification: String = "live", expires: String? = "2026-10-09T20:00:00Z", ends: String? = nil,
                   fetchedAt: String = "2026-10-09T19:00:00Z") throws -> PublicAlert {
    func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
    let json = """
    {"id":"a","event":"Tornado Warning","description":"Official text unchanged.","severity":"Extreme","areaDesc":"Hood, TX",
     "affectedZones":["TXZ131"],"sent":"2026-10-09T18:55:00Z","expires":\(q(expires)),"ends":\(q(ends)),
     "fetchedAt":"\(fetchedAt)","sourceURL":"https://api.weather.gov/alerts/a","classification":"\(classification)"}
    """
    return try DryRunJSON.decoder().decode(PublicAlert.self, from: Data(json.utf8))
}

private func resource(type: String, activation: String, classification: String = "curated", sources: String = "[\"S41\"]",
                      expires: String? = "2026-10-10T00:00:00Z") throws -> PublicResource {
    let exp = expires.map { "\"\($0)\"" } ?? "null"
    let json = """
    {"id":"r","name":"Library","publisher":"City","serviceType":"\(type)","jurisdiction":"x","regionIDs":["48143"],"contact":{},
     "summary":"s","activation":"\(activation)","sourceIDs":\(sources),"checkedAt":"2026-10-09","expiresAt":\(exp),
     "reviewState":"needsReview","classification":"\(classification)"}
    """
    return try DryRunJSON.decoder().decode(PublicResource.self, from: Data(json.utf8))
}

private let now = PublicDataPolicy.parseDate("2026-10-09T19:10:00Z")!

@Suite("Public data policy")
struct PublicDataPolicyTests {
    @Test func liveFreshAlertIsCurrent() throws {
        #expect(PublicDataPolicy.freshness(of: try alert(), now: now) == .current)
    }

    @Test func expiredAlertNeverCurrentEvenIfCached() throws {
        let later = PublicDataPolicy.parseDate("2026-10-09T21:00:00Z")!
        #expect(PublicDataPolicy.freshness(of: try alert(), now: later) == .expired)
        // `ends` takes precedence over a later `expires`.
        #expect(PublicDataPolicy.freshness(of: try alert(expires: "2026-10-10T00:00:00Z", ends: "2026-10-09T19:05:00Z"), now: now) == .expired)
    }

    @Test func demoAlertNeverCurrent() throws {
        let a = try alert(classification: "demo")
        #expect(PublicDataPolicy.freshness(of: a, now: now) == .demo)
        #expect(PublicDataPolicy.currentOfficialAlerts([a], now: now).isEmpty)
        #expect(PublicDataPolicy.freshness(of: try alert(classification: "fixture"), now: now) == .demo)
    }

    @Test func oldCopyIsStaleNotCurrent() throws {
        let a = try alert(expires: "2026-10-10T00:00:00Z", fetchedAt: "2026-10-09T17:00:00Z")
        #expect(PublicDataPolicy.freshness(of: a, now: now) == .stale)
        #expect(!AlertFreshness.stale.mayDisplayAsCurrentOfficialWarning)
    }

    @Test func missingTimesAreUnknown() throws {
        #expect(PublicDataPolicy.freshness(of: try alert(expires: nil), now: now) == .unknown)
    }

    @Test func poiIsNeverActivatedShelterWithoutEvidence() throws {
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "shelter", activation: "unknown"), now: now) == .unconfirmed)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "shelter", activation: "active", sources: "[]"), now: now) == .unconfirmed)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "coolingCenter", activation: "active", classification: "demo"), now: now) == .unconfirmed)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "warmingCenter", activation: "active", expires: nil), now: now) == .unconfirmed)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "warmingCenter", activation: "active", expires: "2026-10-09T19:00:00Z"), now: now) == .unconfirmed)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "warmingCenter", activation: "active"), now: now) == .confirmedActive)
        #expect(PublicDataPolicy.activationDisplay(for: try resource(type: "emergencyManagement", activation: "active"), now: now) == .notApplicable)
    }

    @Test func regionAllowlist() {
        for ok in ["48143", "48221", "48439", "tx-statewide"] { #expect(PublicDataPolicy.isAllowedRegionID(ok)) }
        for bad in ["", "4814", "481433", "06037", "48a43", "123 Main St", "https://evil.example", "../48143", "４８１４３"] {
            #expect(!PublicDataPolicy.isAllowedRegionID(bad), "\(bad)")
        }
    }

    @Test func queryBuilderRejectsUnexpectedValues() throws {
        #expect(try PublicQueryBuilder.path(for: .regionPack(regionID: "48143")) == "/v1/regions/48143/pack")
        #expect(try PublicQueryBuilder.path(for: .content(version: "2026.10.0", locale: "es")) == "/v1/content/2026.10.0/es")
        #expect(throws: PublicRequestError.self) { try PublicQueryBuilder.path(for: .content(version: "../x", locale: "en")) }
        #expect(throws: PublicRequestError.self) { try PublicQueryBuilder.path(for: .content(version: "1", locale: "fr")) }
        #expect(throws: PublicRequestError.self) { try PublicQueryBuilder.path(for: .source(sourceID: "S1/../x")) }
        #expect(throws: PublicRequestError.unexpectedQueryKey("lat")) { try PublicQueryBuilder.validateQuery(["lat": "32.2"]) }
        let url = try PublicQueryBuilder.url(base: URL(string: "https://api.example.org/")!, endpoint: .regionAlerts(regionID: "48221"))
        #expect(url.absoluteString == "https://api.example.org/v1/regions/48221/alerts")
    }
}

@Suite("Public data contract (shared JSON with services/public-api)")
struct PublicDataContractTests {
    @Test func regionPacksDecode() throws {
        for name in ["tx-statewide", "tx-25-counties"] {
            let data = try Data(contentsOf: repoRoot.appendingPathComponent("content/regions/\(name).json"))
            let pack = try DryRunJSON.decoder().decode(RegionPack.self, from: data)
            #expect(pack.schemaVersion == 1)
            let sourceIDs = Set(pack.sources.map(\.id))
            for r in pack.resources {
                #expect(!r.sourceIDs.isEmpty && r.sourceIDs.allSatisfy(sourceIDs.contains), "\(r.id)")
                // No curated pack marks any site as activated.
                #expect(PublicDataPolicy.activationDisplay(for: r, now: now) != .confirmedActive)
            }
            for region in pack.regions { #expect(PublicDataPolicy.isAllowedRegionID(region.id)) }
        }
    }

    @Test func tx25PackCoversThirteenCountiesWithExplicitStatus() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("content/regions/tx-25-counties.json"))
        let pack = try DryRunJSON.decoder().decode(RegionPack.self, from: data)
        #expect(pack.regions.count == 13)
        #expect(pack.regions.filter { $0.inTX25 == "part" }.map(\.name).sorted() ==
                ["Callahan County", "Johnson County", "Parker County", "Tarrant County"])
        // UGC county codes follow the FIPS county number.
        for r in pack.regions { #expect(r.nwsCountyIDs == ["TXC" + r.id.suffix(3)]) }
    }

    @Test func alertsFixtureDecodesAndIsDemo() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("services/public-api/test/fixtures/contract-alerts.json"))
        let env = try DryRunJSON.decoder().decode(AlertsEnvelope.self, from: data)
        #expect(env.alerts.count == 1)
        #expect(PublicDataPolicy.currentOfficialAlerts(env.alerts, now: now).isEmpty)
    }
}
