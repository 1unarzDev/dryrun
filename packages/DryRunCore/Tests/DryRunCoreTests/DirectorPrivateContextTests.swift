import XCTest
@testable import DryRunCore

final class DirectorPrivateContextTests: XCTestCase {
    func testFullCanonicalDirectorRequestIsBoundToExactReceiptAndDerivedScore() throws {
        guard let root = ProcessInfo.processInfo.environment["DRYRUN_AUTHORED_CONTENT_ROOT"] else { throw XCTSkip("Explicit authored content root required") }
        let url = URL(fileURLWithPath: root)
        let library = try ScenarioLibrary.load(from: url.appendingPathComponent("content/scenarios"))
        let scenario = try XCTUnwrap(library.scenario("water-outage"))
        let household = SampleHouseholds.oak
        var home = SampleHomes.ranch; home.id = household.stableHomeID
        let initial = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version, contentVersion: "authored-test")
        let session = try SimulationSession.initialize(id: "director-context-test", initial: initial, library: library)
        let receipt = try session.query(library: library)
        let state = IntegratedAIState(sessions: [session])
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self, from: Data(contentsOf: url.appendingPathComponent("content/ai/rubric-v0.json")))
        let score = try ScoreCompiler.compile(rubric: rubric, assessments: [])
        let request = try DirectorGatewayBridge.operationRequest(requestID: "request-a", session: session, receipt: receipt, library: library,
            state: state, scopeSessionID: "family-scope-a", locale: "es", currentScorecard: score)
        let context = try XCTUnwrap(request.context.privateContext)
        XCTAssertEqual(request.context.contextBinding, context.binding)
        XCTAssertEqual(context.scope.sessionID, "family-scope-a")
        XCTAssertEqual(context.scope.householdID, household.id)
        XCTAssertEqual(request.context.experience, receipt.experience)
        XCTAssertEqual(request.context.locale, "es")
        XCTAssertTrue(context.records.contains { $0.sourcePath == "currentHostScorecard" && $0.status == "recorded" })
        XCTAssertTrue(context.records.contains { $0.sourcePath.hasPrefix("sessions.item.") })
        XCTAssertTrue(state.scorecards.isEmpty)
        var stale = receipt; stale.revision += 1
        XCTAssertThrowsError(try DirectorGatewayBridge.operationRequest(requestID: "stale", session: session, receipt: stale, library: library,
            state: state, scopeSessionID: "family-scope-a"))
        XCTAssertThrowsError(try DirectorGatewayBridge.operationRequest(requestID: "no-state", session: session, receipt: receipt, library: library,
            scopeSessionID: "family-scope-a"))
        if let output = ProcessInfo.processInfo.environment["DRYRUN_DIRECTOR_WIRE_PATH"] {
            try DryRunJSON.encoder().encode(request).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }
}
