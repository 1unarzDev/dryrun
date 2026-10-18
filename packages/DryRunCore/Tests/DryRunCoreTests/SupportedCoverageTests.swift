import Foundation
import Testing
@testable import DryRunCore

@Suite("Explicit supported public coverage")
struct SupportedCoverageTests {
    @Test func supportedCountiesExactlyMatchBundledCoverage() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let bundled = Set(content.regionPacks.flatMap(\.regions).map(\.id))
        #expect(PublicDataPolicy.supportedRegionIDs == bundled.union(["tx-25"]))
        for id in bundled {
            #expect(PublicDataPolicy.isAllowedRegionID(id))
            #expect(!(try PublicQueryBuilder.path(for: .regionPack(regionID: id))).isEmpty)
        }
        #expect(PublicDataPolicy.isAllowedRegionID("tx-25"))
    }

    @Test func uncoveredUSAndForeignLocationsCannotBuildPublicRequestsOrInheritTexasResources() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        // Real Texas county outside current coverage, nonexistent Texas FIPS, another US county,
        // foreign location labels and optional/unresolved location values all remain unsupported.
        for id in ["48001", "48999", "06037", "FR-75", "Paris", "US", "VN", "unsupported", ""] {
            #expect(!PublicDataPolicy.isAllowedRegionID(id))
            #expect(content.resources(forRegion: id).isEmpty)
            for endpoint in [PublicEndpoint.regionPack(regionID: id), .regionAlerts(regionID: id)] {
                #expect(throws: PublicRequestError.invalidRegionID) { try PublicQueryBuilder.path(for: endpoint) }
            }
        }
        #expect(!content.resources(forRegion: "48143").isEmpty)
        #expect(!content.resources(forRegion: "tx-statewide").isEmpty)
    }
}
