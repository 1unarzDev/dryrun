import XCTest
import DryRunCore
@testable import DryRun

/// Prepare's six-scenario recompute after the active example is loaded again (phone report: Settings > Try a sample
/// family > Oak while Oak was loaded left Prepare on "Running all six practice scenarios" for minutes). Fictional
/// in-memory household only; no network.
@MainActor
final class PrepareReloadTests: XCTestCase {
    private let preferences = UserDefaults(suiteName: "DryRun.PrepareReloadTests." + UUID().uuidString)!

    func testReloadingTheActiveExampleReKeysAndRecomputesPrepare() async throws {
        let model = AppModel(store: InMemoryPrivateDataStore(), preferences: preferences)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        await model.refreshNextSteps()
        XCTAssertNotNil(model.nextStepResults)
        let before = model.nextStepsRefreshID

        await model.useSampleHousehold(SampleHouseholds.oak)
        XCTAssertNil(model.nextStepResults, "reload drops the derived results")
        // The cause: the same fixture revision gives the same currentKey, so a task keyed on it never re-ran.
        XCTAssertEqual(model.nextStepsRefreshID.key, before.key, "same example, same revision key")
        XCTAssertNotEqual(model.nextStepsRefreshID, before, "the refresh ID still moves, so Prepare's task re-runs")

        await model.refreshNextSteps()
        XCTAssertNotNil(model.nextStepResults)
        XCTAssertFalse(model.nextStepsStalled)
    }

    func testConcurrentRefreshesForTheSameInputsRunOnceAndBothFinish() async throws {
        let model = AppModel(store: InMemoryPrivateDataStore(), preferences: preferences)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.lake)
        async let first: Void = model.refreshNextSteps()
        async let second: Void = model.refreshNextSteps()
        _ = await (first, second)
        XCTAssertNotNil(model.nextStepResults)
        XCTAssertFalse(model.nextStepsStalled)
    }
}
