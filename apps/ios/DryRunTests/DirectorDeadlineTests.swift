import XCTest
import DryRunCore
@testable import DryRun

/// A director transport that stalls like an unresponsive provider: it never answers on its own and ignores
/// cancellation. Optionally it first asks for one read-only tool so a continuation token exists.
private final class StalledTransport: DirectorTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var starts = 0, resumes = 0
    private var cancelled: [String] = []
    let askForTool: Bool
    init(askForTool: Bool = false) { self.askForTool = askForTool }

    var startCount: Int { lock.withLock { starts } }
    var resumeCount: Int { lock.withLock { resumes } }
    var cancelledTokens: [String] { lock.withLock { cancelled } }

    private func stall() async {
        await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
    }
    /// Lets the stalled calls return (late) so the test leaves no suspended continuation behind.
    func release() { let pending = lock.withLock { let p = waiting; waiting = []; return p }; pending.forEach { $0.resume() } }

    func start(_ request: DirectorGatewayBridge.OperationRequest) async -> DirectorGatewayClient.Outcome {
        lock.withLock { starts += 1 }
        if askForTool {
            return .needsTools(token: "token-1", binding: request.context.binding,
                               call: .init(id: "call-1", name: "inspectScene", arguments: .init()))
        }
        await stall()
        return .unavailable("late")
    }
    func resume(token: String, binding: AgentContextBinding, callID: String, result: DirectorGatewayBridge.ToolResult,
                expectedContextBinding: AuthorizedAIContext.Binding?) async -> DirectorGatewayClient.Outcome {
        lock.withLock { resumes += 1 }
        await stall()
        return .unavailable("late")
    }
    func cancel(token: String) async { lock.withLock { cancelled.append(token) } }
}

/// Audit wave 1 REL-01 (director job experience): a stalled gateway turn must not leave the exercise stuck.
@MainActor
final class DirectorDeadlineTests: XCTestCase {
    private func model(_ transport: StalledTransport, deadline: Duration) async -> AppModel {
        let defaults = UserDefaults(suiteName: "director-deadline-\(UUID().uuidString)")!
        let model = AppModel(store: InMemoryPrivateDataStore(), preferences: defaults)
        model.directorTransport = transport
        model.cloudDirectorEnabled = true
        model.directorDeadline = deadline
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        return model
    }

    func testStalledGatewayTurnFallsBackToTheLocalDirectorWithinTheDeadline() async throws {
        let transport = StalledTransport()
        let model = await model(transport, deadline: .milliseconds(400))
        XCTAssertTrue(model.cloudDirectorAvailable)
        let started = ContinuousClock.now
        await model.openAdaptive(scenarioID: "freeze-power-loss")
        let elapsed = ContinuousClock.now - started
        let exercise = try XCTUnwrap(model.adaptive)
        XCTAssertEqual(transport.startCount, 1)
        XCTAssertEqual(exercise.lastDirector, .local, "the local director took the step")
        XCTAssertGreaterThan(exercise.session.revision, 0)
        XCTAssertEqual(model.directorFallbackNote, model.localizer("adaptive.fallback.deadline"))
        XCTAssertFalse(model.directorTurnInFlight)
        XCTAssertLessThan(elapsed, .seconds(10))
        transport.release()
    }

    func testDeadlineAfterAToolRoundCancelsTheGatewayToken() async throws {
        let transport = StalledTransport(askForTool: true)
        let model = await model(transport, deadline: .milliseconds(600))
        await model.openAdaptive(scenarioID: "freeze-power-loss")
        XCTAssertEqual(transport.resumeCount, 1, "the phone answered the read-only tool before the stall")
        XCTAssertEqual(model.adaptive?.lastDirector, .local)
        // The best-effort gateway cancel runs in its own task.
        for _ in 0..<50 where transport.cancelledTokens.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(transport.cancelledTokens, ["token-1"])
        transport.release()
    }

    func testEndStaysAvailableAndWinsWhileAGatewayTurnIsInFlight() async throws {
        let transport = StalledTransport()
        let model = await model(transport, deadline: .seconds(60))
        let opening = Task { await model.openAdaptive(scenarioID: "freeze-power-loss") }
        for _ in 0..<500 where !(model.directorTurnInFlight && transport.startCount == 1) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.directorTurnInFlight)
        XCTAssertFalse(model.isWorking, "End is disabled only by isWorking")
        let before = try XCTUnwrap(model.adaptive)
        let started = ContinuousClock.now
        let ended = await model.submitAdaptive([SessionCommand(kind: "finish")])
        await opening.value
        XCTAssertTrue(ended)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), "End did not wait for the 60 s deadline")
        let after = try XCTUnwrap(model.adaptive)
        XCTAssertTrue(after.receipt.finished)
        XCTAssertEqual(after.session.revision, before.session.revision + 1, "no director step was committed after End")
        XCTAssertFalse(model.directorTurnInFlight)
        XCTAssertNil(model.directorFallbackNote)
        transport.release()
    }

    func testDirectorSourceFollowsTheReportedServingProvider() {
        XCTAssertEqual(AppModel.DirectorSource(servedBy: "codex"), .codex)
        XCTAssertEqual(AppModel.DirectorSource(servedBy: "gemini"), .gemini)
        XCTAssertEqual(AppModel.DirectorSource(servedBy: "groq"), .groq)
        XCTAssertEqual(AppModel.DirectorSource(servedBy: nil), .beacon)
        XCTAssertEqual(AppModel.DirectorSource(servedBy: "other"), .beacon)
        XCTAssertTrue(AppModel.DirectorSource.codex.isRemote)
        XCTAssertFalse(AppModel.DirectorSource.local.isRemote)
    }
}
