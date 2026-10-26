import Foundation
import Testing
@testable import DryRunCore

enum LeadTestSupport {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static var contentRoot: URL { repoRoot.appendingPathComponent("content") }
    static let fixedDate = ISO8601DateFormatter().date(from: "2026-10-09T15:00:00Z")!
}

@Suite("Fixture households")
struct FixtureHouseholdTests {
    @Test("Bundled households are fictional, round-trip, and match fixtures/households JSON")
    func householdsMatchFixtures() throws {
        let dir = LeadTestSupport.repoRoot.appendingPathComponent("fixtures/households")
        let write = ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1"
        for household in SampleHouseholds.all {
            #expect(household.isFictional)
            let data = try DryRunJSON.encoder().encode(household)
            let url = dir.appendingPathComponent("\(household.id).json")
            if write {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url)
            }
            let onDisk = try DryRunJSON.decoder().decode(HouseholdProfile.self, from: Data(contentsOf: url))
            #expect(onDisk == household, "fixtures/households/\(household.id).json is out of date; rerun with DRYRUN_WRITE_FIXTURES=1")
        }
    }

    @Test("Unknown evidence decodes from a minimal JSON object and is never treated as confirmed")
    func lenientEvidence() throws {
        let v = try DryRunJSON.decoder().decode(EvidenceValue<Bool>.self, from: Data(#"{"origin":"userConfirmed","status":"confirmed"}"#.utf8))
        #expect(v.value == nil)
        #expect(v.status == .unknown)
        #expect(!v.isConfirmed)
        let scanned = EvidenceValue<Double>.scanned(0.9, unit: "m")
        #expect(scanned.confirmedValue == nil, "scan-observed values never satisfy confirmed requirements")
    }

    @Test("Household fixtures contain no real-looking phone numbers outside the 555-01xx fictional range")
    func fictionalPhones() {
        for h in SampleHouseholds.all {
            for c in h.contacts { #expect(c.phone.map { $0.contains("555-01") } ?? true) }
        }
    }
}
