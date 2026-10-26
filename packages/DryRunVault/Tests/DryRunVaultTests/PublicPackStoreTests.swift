import DryRunCore
@testable import DryRunVault
import Foundation
import Testing

func packJSON(packID: String = "tx-statewide", schema: Int = 1, extra: String = "", resourceSource: String = "S27",
              sourceURL: String = "https://www.211texas.org/contact-2-1-1/") -> Data {
    Data("""
    {"schemaVersion":\(schema),"contentVersion":"2026.10.0","packID":"\(packID)","generatedAt":"2026-10-09T00:00:00Z",
     "classification":"curated",\(extra)
     "regions":[{"id":"tx-statewide","name":"Texas","kind":"state","nwsZoneIDs":[],"nwsCountyIDs":[],"coverage":"statewideOnly","inTX25":"n/a"}],
     "resources":[{"id":"r-211","name":"211 Texas","publisher":"Texas HHSC","serviceType":"assistanceLine","jurisdiction":"Texas",
       "regionIDs":["tx-statewide"],"contact":{"phone":"877-541-7905"},"summary":"Local services.","activation":"notApplicable",
       "sourceIDs":["\(resourceSource)"],"checkedAt":"2026-10-09","reviewState":"needsReview","classification":"curated"}],
     "sources":[{"id":"S27","publisher":"211 Texas","title":"Contact 2-1-1","url":"\(sourceURL)","checkedAt":"2026-10-09","reviewState":"needsReview"}]}
    """.utf8)
}

@Suite("Public pack known-good cache")
struct PublicPackStoreTests {
    @Test func acceptsValidPackAndKeepsKnownGoodOnBadUpdates() async throws {
        let store = PublicPackStore(directory: makeTempRoot())
        try await store.updatePack(packJSON(), expectedRegionID: "tx-statewide")
        let bad: [Data] = [
            Data("{not json".utf8),
            packJSON(schema: 99),
            packJSON(resourceSource: "S99"),                       // cites unknown source
            packJSON(sourceURL: "http://169.254.169.254/latest"),   // non-https/untrusted
            packJSON(packID: "../../etc"),
            Data(repeating: 0x20, count: PublicPackStore.maxPackBytes + 1),
        ]
        for b in bad {
            await #expect(throws: PublicPackError.self) { try await store.updatePack(b, expectedRegionID: "tx-statewide") }
        }
        let good = await store.knownGoodPack(regionID: "tx-statewide")
        #expect(good?.resources.first?.contact.phone == "877-541-7905")
    }

    @Test func unknownKeysAreDroppedNotPersisted() async throws {
        let dir = makeTempRoot()
        let store = PublicPackStore(directory: dir)
        try await store.updatePack(packJSON(extra: "\"householdAlias\":\"\(canary)\","), expectedRegionID: "tx-statewide")
        for (_, d) in allFileBytes(under: dir) { #expect(!contains(d, canary)) }
    }

    @Test func activeWithoutExpiryRejected() async throws {
        let store = PublicPackStore(directory: makeTempRoot())
        let json = String(decoding: packJSON(), as: UTF8.self)
            .replacingOccurrences(of: "\"activation\":\"notApplicable\"", with: "\"activation\":\"active\"")
        await #expect(throws: PublicPackError.self) { try await store.updatePack(Data(json.utf8), expectedRegionID: "tx-statewide") }
    }

    @Test func expiredCachedAlertNeverCurrentOffline() async throws {
        let store = PublicPackStore(directory: makeTempRoot())
        let alerts = Data("""
        {"schemaVersion":1,"regionID":"48143","fetchedAt":"2026-10-09T10:00:00Z","status":"ok","alerts":[
         {"id":"a1","event":"Flash Flood Warning","description":"Official text.","severity":"Severe","areaDesc":"Erath, TX",
          "affectedZones":["TXC143"],"sent":"2026-10-09T09:00:00Z","expires":"2026-10-09T12:00:00Z","fetchedAt":"2026-10-09T10:00:00Z",
          "sourceURL":"https://api.weather.gov/alerts/a1","classification":"live"}]}
        """.utf8)
        try await store.updateAlerts(alerts, expectedRegionID: "48143")
        let cached = try #require(await store.cachedAlerts(regionID: "48143"))
        let later = PublicDataPolicy.parseDate("2026-10-09T13:00:00Z")!
        #expect(PublicDataPolicy.currentOfficialAlerts(cached.alerts, now: later).isEmpty)
        #expect(PublicDataPolicy.freshness(of: cached.alerts[0], now: later) == .expired)
    }
}

@Suite("Public cache region checks")
struct PublicRegionMismatchTests {
    @Test func alertsForWrongCountyRejectedAndCacheKept() async throws {
        let store = PublicPackStore(directory: makeTempRoot())
        func env(_ region: String, _ event: String) -> Data {
            Data("""
            {"schemaVersion":1,"regionID":"\(region)","fetchedAt":"2026-10-09T10:00:00Z","status":"ok","alerts":[
             {"id":"\(event)","event":"\(event)","description":"x","severity":"Severe","areaDesc":"x","affectedZones":[],
              "sent":"2026-10-09T09:00:00Z","expires":"2026-10-09T12:00:00Z","fetchedAt":"2026-10-09T10:00:00Z",
              "sourceURL":"https://api.weather.gov/alerts/x","classification":"live"}]}
            """.utf8)
        }
        try await store.updateAlerts(env("48143", "Erath alert"), expectedRegionID: "48143")
        await #expect(throws: PublicPackError.regionMismatch(expected: "48143", found: "48221")) {
            try await store.updateAlerts(env("48221", "Hood alert"), expectedRegionID: "48143")
        }
        #expect(await store.cachedAlerts(regionID: "48143")?.alerts.first?.event == "Erath alert")
    }

    @Test func packMustContainRequestedRegionAndIsFoundByRegionOffline() async throws {
        let store = PublicPackStore(directory: makeTempRoot())
        await #expect(throws: PublicPackError.self) { try await store.updatePack(packJSON(), expectedRegionID: "48143") }
        try await store.updatePack(packJSON(packID: "tx-statewide.tx-statewide"), expectedRegionID: "tx-statewide")
        #expect(await store.knownGoodPack(regionID: "tx-statewide") != nil)
    }
}

@Suite("Public request builder never carries private data")
struct PublicRequestPrivacyTests {
    @Test func canaryCannotEnterAnyRequest() throws {
        let base = URL(string: "https://api.dryrun.example")!
        let household = canaryPayload().household!
        // The only household-derived value the client may send is the allowlisted public region ID.
        let endpoints: [PublicEndpoint] = [.health, .manifest, .regionPack(regionID: household.regionID),
                                           .regionAlerts(regionID: household.regionID), .content(version: "2026.10.0", locale: "vi"),
                                           .source(sourceID: "S27")]
        for e in endpoints {
            let url = try PublicQueryBuilder.url(base: base, endpoint: e)
            #expect(!url.absoluteString.contains("CANARY"))
            #expect(url.query == nil)
        }
        #expect(throws: PublicRequestError.self) {
            _ = try PublicQueryBuilder.url(base: base, endpoint: .regionPack(regionID: household.people[0].alias))
        }
        #expect(throws: PublicRequestError.self) {
            _ = try PublicQueryBuilder.url(base: base, endpoint: .regionAlerts(regionID: household.privateLocation!.addressLine!))
        }
        #expect(throws: PublicRequestError.unexpectedQueryKey("address")) {
            try PublicQueryBuilder.validateQuery(["address": canary])
        }
    }
}
