import XCTest
@testable import DryRunCore

/// Exact native wire inputs for reviewer-controlled live experiments. No model output.
final class NativeGatewayInputExportTests: XCTestCase {
    func testExportEachSelectableFamilyUsingCanonicalNativeContracts() throws {
        guard let root = ProcessInfo.processInfo.environment["DRYRUN_NATIVE_INPUT_EXPORT_DIR"],
              let repo = ProcessInfo.processInfo.environment["DRYRUN_AUTHORED_CONTENT_ROOT"] else { throw XCTSkip("Explicit synthetic export paths required") }
        let destination = URL(fileURLWithPath:root);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:URL(fileURLWithPath:repo).appendingPathComponent("content/ai/rubric-v0.json")))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-20T12:00:00Z"))
        for (name,household) in [("oak",SampleHouseholds.oak),("lake",SampleHouseholds.lake),("pine",SampleHouseholds.pine)] {
            XCTAssertTrue(household.isFictional)
            var home = SampleHomes.ranch;home.id = household.stableHomeID
            let state = IntegratedAIState();let catalog = PreparationTaskCatalog.build(household:household,home:home,rubric:rubric,at:date)
            XCTAssertFalse(catalog.isEmpty)
            let request = try PreparationFeatureBridge.request(requestID: "native-baseline-\(name)",
                household: household, home: home, inventory: state.inventory, rubric: rubric, at: date,
                state: state, scopeSessionID: "native-baseline-\(name)", locale: "en")
            let bytes = try DryRunJSON.encoder().encode(request)
            try bytes.write(to:destination.appendingPathComponent(name+".json"),options:.atomic)
        }
    }
}
