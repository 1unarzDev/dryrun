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
    func testSelectedScenarioDocumentIncludesTheSameCurrentRoutesUsedByItsPanels() async throws {
        let (model, _) = await makeModel()
        let savedHome = await model.updateHome(SampleHomes.ranch, expectedRevision: model.home?.revision)
        XCTAssertTrue(savedHome)
        let generated = await model.generatePlan(scenarioIDs: ["home-fire"], includePrivateNotes: false)
        let document = try XCTUnwrap(generated)
        XCTAssertEqual(document.scenarioIDs, ["home-fire"])
        XCTAssertTrue(document.pages.contains { $0.id == "scenario-home-fire" })
        let snapshot = try XCTUnwrap(document.visualSnapshot)
        XCTAssertFalse(snapshot.routes.isEmpty)
        XCTAssertTrue(snapshot.homePanels.contains { $0.scenarioID == "home-fire" })
        XCTAssertTrue(model.documentIsCurrent(document))
        var changed = try XCTUnwrap(model.household)
        changed.displayName = "Changed after snapshot began"
        let changedSaved = await model.updateHousehold(changed)
        XCTAssertTrue(changedSaved)
        XCTAssertFalse(model.documentIsCurrent(document))
    }

    func testNoLayoutRehearsalAndPlanNeverInsertAnExampleHome() async throws {
        let (model, _) = await makeModel()
        XCTAssertNil(model.home)
        await model.startRehearsal(scenarioID: "water-outage")
        let result = try XCTUnwrap(model.rehearsal?.result)
        XCTAssertNil(result.input.home)
        XCTAssertFalse(result.events.isEmpty)
        XCTAssertTrue(result.routes.isEmpty)
        let generated = await model.generatePlan(scenarioIDs: ["water-outage"], includePrivateNotes: false)
        let document = try XCTUnwrap(generated)
        XCTAssertEqual(document.scenarioIDs, ["water-outage"])
        XCTAssertTrue(document.pages.contains { $0.id == "family-card" })
        XCTAssertTrue(document.pages.contains { $0.id == "scenario-water-outage" })
        XCTAssertNil(document.visualSnapshot?.home)
    }

    func testFailedFactWriteDoesNotShowRecordedProgress() async throws {
        let (model, store) = await makeModel()
        var household = try XCTUnwrap(model.household)
        household.contacts = []
        let initialSaved = await model.updateHousehold(household)
        XCTAssertTrue(initialSaved)
        XCTAssertFalse(model.nextSteps?.recorded.contains { $0.id == "prep.contact" } == true)
        household = try XCTUnwrap(model.household)
        household.contacts.append(HouseholdContact(id: "new", role: .other, alias: "Trusted contact", phone: "+44 20 7946 0000"))
        await store.failWrites()
        let failedSaved = await model.updateHousehold(household)
        XCTAssertFalse(failedSaved)
        XCTAssertFalse(model.nextSteps?.recorded.contains { $0.id == "prep.contact" } == true)
        XCTAssertTrue(model.nextSteps?.toDo.contains { $0.id == "prep.contact" } == true)
    }

    func testSelectedPlanRetainsPracticedOriginAndLeakAssumptions() async throws {
        let (model, _) = await makeModel()
        let saved = await model.updateHome(SampleHomes.ranch, expectedRevision: model.home?.revision)
        XCTAssertTrue(saved)
        await model.startRehearsal(scenarioID: "home-fire", variants: ["origin:sp-kitchen", "start:p-oak-1|sp-living"])
        let practiced = try XCTUnwrap(model.rehearsal?.result)
        let fire = await model.generatePlan(scenarioIDs: ["home-fire"], includePrivateNotes: false)
        XCTAssertEqual(fire?.visualSnapshot?.exerciseStates?.first?.state, practiced.snapshots.last(where: { $0.spatialState != nil })?.spatialState)
        await model.startRehearsal(scenarioID: "flash-flood", variants: ["householdLeak", "waterEntry:sp-kitchen"])
        let leak = await model.generatePlan(scenarioIDs: ["flash-flood"], includePrivateNotes: false)
        let document = try XCTUnwrap(leak)
        XCTAssertEqual(document.visualSnapshot?.scenarioLabels?["flash-flood"], model.localizer("scenario.household-leak.title"))
        XCTAssertFalse(document.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key.hasPrefix("plan.scenario.flash-flood.immediate.") })
    }

}
