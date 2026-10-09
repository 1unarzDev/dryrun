import Foundation
import Testing
@testable import DryRunCore

/// fixtures/homes/*.json are generated from `SampleHomes`. Regenerate with DRYRUN_WRITE_FIXTURES=1.
@Suite("Spatial fixtures and validation")
struct SpatialFixtureTests {
    static var repoRoot: URL {
        if let r = ProcessInfo.processInfo.environment["DRYRUN_REPO_ROOT"], !r.isEmpty { return URL(fileURLWithPath: r) }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u
    }

    @Test func homeFixturesMatchSampleHomes() throws {
        let dir = Self.repoRoot.appendingPathComponent("fixtures/homes")
        let write = ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1"
        for home in SampleHomes.all {
            let url = dir.appendingPathComponent("\(home.id).json")
            if write {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try DryRunJSON.encoder().encode(home).write(to: url, options: .atomic)
            }
            let decoded = try DryRunJSON.decoder().decode(HomeModel.self, from: Data(contentsOf: url))
            #expect(decoded == home, "fixtures/homes/\(home.id).json is out of date; rerun with DRYRUN_WRITE_FIXTURES=1")
            #expect(decoded.isFictional)
            #expect(decoded.source == .sample)
        }
    }

    @Test func ranchHasNoBlockingIssuesAndFlagsWhatNeedsConfirmation() {
        let issues = HomeValidator.validate(SampleHomes.ranch)
        #expect(!issues.contains { $0.severity == .blocking }, "\(issues.filter { $0.severity == .blocking })")
        #expect(issues.contains { $0.kind == .windowNotAnExit && $0.elementID == "pt-win-bed1" })
        #expect(issues.contains { $0.kind == .clearWidthUnknown && $0.elementID == "pt-bed1-hall" })
        #expect(issues.contains { $0.kind == .shelterCandidateNotEngineered })
        #expect(!issues.contains { $0.kind == .missingMeetingPoint })
    }

    @Test func apartmentAndTwoStoryIssues() {
        let apt = HomeValidator.validate(SampleHomes.apartment)
        #expect(apt.contains { $0.kind == .noVerifiedExteriorExit })
        #expect(apt.contains { $0.kind == .commonAreaOutsideModel && $0.elementID == "pt-entry" })
        #expect(apt.contains { $0.kind == .upperFloorExteriorPortal && $0.elementID == "pt-balcony" })
        #expect(apt.contains { $0.kind == .structureIncomplete })

        var two = SampleHomes.twoStory
        two.connectors[0].verification = .proposed
        two.annotations.removeAll { $0.kind == .outsideMeetingPoint }
        let issues = HomeValidator.validate(two)
        #expect(issues.contains { $0.kind == .connectorUnverified })
        #expect(issues.contains { $0.kind == .missingMeetingPoint })
        #expect(issues.contains { $0.kind == .upperFloorExteriorPortal && $0.elementID == "pt-win-up-bed1" })
    }

    @Test func invalidAndOverlappingGeometryIsReported() {
        var home = SampleHomes.ranch
        home.spaces.append(Space(id: "sp-bad", floorID: "fl-ground", label: "Bowtie", kind: .other,
                                polygon: [Vec2(20, 0), Vec2(22, 2), Vec2(22, 0), Vec2(20, 2)]))
        home.spaces.append(Space(id: "sp-overlap", floorID: "fl-ground", label: "Overlap", kind: .other,
                                polygon: SampleHomes.rect(1, 1, 3, 3)))
        let issues = HomeValidator.validate(home)
        #expect(issues.contains { $0.kind == .invalidPolygon && $0.elementID == "sp-bad" })
        #expect(issues.contains { $0.kind == .overlappingSpaces && $0.elementID.contains("sp-overlap") })
        let r = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-bad"), in: home)
        #expect(r.noRouteReason == .invalidGeometry)
    }
}
