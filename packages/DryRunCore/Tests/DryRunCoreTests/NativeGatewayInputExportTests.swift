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
            var home = SampleHomes.forExampleHousehold(SampleHomes.ranch, household);home.id = household.stableHomeID
            let state = IntegratedAIState();let catalog = PreparationTaskCatalog.build(household:household,home:home,rubric:rubric,at:date)
            XCTAssertFalse(catalog.isEmpty)
            let request = try PreparationFeatureBridge.request(requestID: "native-baseline-\(name)",
                household: household, home: home, inventory: state.inventory, rubric: rubric, at: date,
                state: state, scopeSessionID: "native-baseline-\(name)", locale: "en")
            let bytes = try DryRunJSON.encoder().encode(request)
            try bytes.write(to:destination.appendingPathComponent(name+".json"),options:.atomic)
        }
    }

    /// Debrief requests exactly as the app sends them after a finished rehearsal: the deterministic rehearsal's own
    /// recommendations, the full authorized context and all three providers consented. One hazard per family.
    func testExportDebriefRequestsAfterADeterministicRehearsal() throws {
        guard let root = ProcessInfo.processInfo.environment["DRYRUN_NATIVE_DEBRIEF_EXPORT_DIR"],
              let repo = ProcessInfo.processInfo.environment["DRYRUN_AUTHORED_CONTENT_ROOT"] else { throw XCTSkip("Explicit synthetic export paths required") }
        let destination = URL(fileURLWithPath:root);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:URL(fileURLWithPath:repo).appendingPathComponent("content/ai/rubric-v0.json")))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-20T12:00:00Z"))
        for (name,household,scenario) in [("oak",SampleHouseholds.oak,"freeze-power-loss"),("lake",SampleHouseholds.lake,"flash-flood"),("pine",SampleHouseholds.pine,"heat-grid-strain")] {
            XCTAssertTrue(household.isFictional)
            var home = SampleHomes.forExampleHousehold(SampleHomes.ranch, household);home.id = household.stableHomeID
            let result = try SimFixtures.run(household, scenario)
            XCTAssertFalse(result.recommendations.isEmpty)
            var request = try DebriefFeatureBridge.request(requestID: "native-debrief-\(name)", scenarioID: scenario, recommendations: result.recommendations,
                household: household, home: home, inventory: IntegratedAIState().inventory, rubric: rubric, at: date,
                state: IntegratedAIState(), scopeSessionID: "native-debrief-\(name)", locale: "en")
            request.providerConsent = ["codex", "gemini", "groq"]
            try DryRunJSON.encoder().encode(request).write(to:destination.appendingPathComponent("debrief-"+name+".json"),options:.atomic)
        }
    }
}
