import XCTest
import DryRunCore
@testable import DryRun

private actor ExportControlledStore: PrivateDataStore {
    enum Failure: Error { case unavailable }
    var snapshot: PrivateSnapshot
    var fail = false
    init(household: HouseholdProfile) { snapshot = PrivateSnapshot(household: household) }
    func load() async -> PrivateLoadResult { .loaded(snapshot) }
    func save(_ snapshot: PrivateSnapshot) async throws {
        if fail { throw Failure.unavailable }
        self.snapshot = snapshot
    }
    func deleteAll() async throws { }
    func failWrites() { fail = true }
}

@MainActor
final class PlanGenerationPrivacyTests: XCTestCase {
    private func makeModel() async -> (AppModel, ExportControlledStore) {
        var household = SampleHouseholds.oak
        household.people[0].emergencyInformation = .init(criticalConditions: "CRITICAL-PRIVATE-CANARY")
        household.equipment[0].carePlanNotes = "NOTES-PRIVATE-CANARY"
        let store = ExportControlledStore(household: household)
        let model = AppModel(store: store)
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        return (model, store)
    }
    private func text(_ document: PlanDocument) -> String {
        document.pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined(separator: "\n")
    }

    func testFailedFreshGenerationReturnsNoExportInsteadOfRetainedSensitivePlan() async throws {
        let (model, store) = await makeModel()
        let old = await model.generatePlan(scenarioIDs: [], includePrivateNotes: true, selection: .init(includeCriticalInformation: true))
        let sensitive = try XCTUnwrap(old)
        XCTAssertTrue(text(sensitive).contains("CRITICAL-PRIVATE-CANARY"))
        await store.failWrites()
        let request = FamilyPlanExportRequest(includePlan: true, includeCard: true, includePrivateNotes: false, selection: .init())
        let failed = await model.generatePlan(scenarioIDs: [], includePrivateNotes: request.includePrivateNotes, selection: request.selection)
        XCTAssertNil(failed)
        XCTAssertEqual(model.savedPlan, sensitive)
        XCTAssertFalse(model.planIsStale) // Input revision alone cannot validate changed export consent.
        XCTAssertNil(request.document(generatedPlan: failed, card: model.outageCard(selection: request.selection)))
    }

    func testSuccessfulFreshGenerationReplacesOldSensitiveSelection() async throws {
        let (model, _) = await makeModel()
        _ = await model.generatePlan(scenarioIDs: [], includePrivateNotes: true, selection: .init(includeCriticalInformation: true))
        let fresh = await model.generatePlan(scenarioIDs: [], includePrivateNotes: false, selection: .init())
        let document = try XCTUnwrap(fresh)
        XCTAssertFalse(text(document).contains("CRITICAL-PRIVATE-CANARY"))
        XCTAssertFalse(text(document).contains("NOTES-PRIVATE-CANARY"))
        XCTAssertEqual(model.savedPlan, document)
    }

    func testFreshPlanWithTwoPlacesIsCurrentRegardlessOfInsertionOrderAndAfterReload() async throws {
        let (model, store) = await makeModel()
        let homeID = try XCTUnwrap(model.household?.stableHomeID)
        let first = await model.savePlace(SavedPlace(id: "z-near", homeID: homeID, purpose: .outsideMeetingPoint, label: "Fictional gate"))
        let second = await model.savePlace(SavedPlace(id: "a-backup", homeID: homeID, purpose: .backupMeetingPlace, label: "Fictional library"))
        XCTAssertTrue(first && second)
        let generated = await model.generatePlan(scenarioIDs: [], includePrivateNotes: false)
        XCTAssertNotNil(generated)
        XCTAssertFalse(model.planIsStale)
        let restored = AppModel(store: store)
        await restored.start()
        XCTAssertFalse(restored.planIsStale)
        XCTAssertEqual(restored.savedPlan, generated)
    }
}
