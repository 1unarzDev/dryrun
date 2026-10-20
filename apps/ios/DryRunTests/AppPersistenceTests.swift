import XCTest
import DryRunCore
@testable import DryRun

private actor ControlledStore: PrivateDataStore {
    enum WriteError: Error { case unavailable }
    var snapshot: PrivateSnapshot?
    var fail = false
    var hold = false
    var pending: CheckedContinuation<Void, Never>?
    var began: CheckedContinuation<Void, Never>?
    var didBegin = false

    func load() async -> PrivateLoadResult { snapshot.map(PrivateLoadResult.loaded) ?? .empty }
    func save(_ value: PrivateSnapshot) async throws {
        didBegin = true
        began?.resume(); began = nil
        if hold { await withCheckedContinuation { pending = $0 } }
        if fail { throw WriteError.unavailable }
        snapshot = value
    }
    func deleteAll() async throws { snapshot = nil }
    func failWrites() { fail = true }
    func allowWrites() { fail = false }
    func holdWrites() { hold = true }
    func waitForWrite() async {
        if !didBegin { await withCheckedContinuation { began = $0 } }
    }
    func release() { hold = false; pending?.resume(); pending = nil }
}

/// Native app integration tests: run by scripts/mac/verify.sh. Authored on Linux; execution evidence is separate.
@MainActor
final class AppPersistenceTests: XCTestCase {
    func testPortableEvidenceSurvivesOrdinaryEditsAndFailedWrites() async throws {
        let store = ControlledStore()
        let model = AppModel(store: store)
        model.household = SampleHouseholds.oak; model.home = SampleHomes.ranch
        let wrote = await model.updateIntegratedAIState(expectedDigest: nil) { state in
            state.imageGeometryRecords = []
        }
        XCTAssertTrue(wrote)
        let data = try XCTUnwrap(model.integratedAIState)
        let edited = await model.updateHousehold { $0.displayName = "Renamed family" }
        XCTAssertTrue(edited)
        XCTAssertEqual(model.integratedAIState, data)
        if case .loaded(let snapshot) = await store.load() { XCTAssertEqual(snapshot.integratedAIState, data) }
        else { XCTFail("No durable snapshot") }
        await store.failWrites()
        let failed = await model.updateIntegratedAIState(expectedDigest: StableDigest.of(data)) { $0.imageGeometryRecords = nil }
        XCTAssertFalse(failed); XCTAssertEqual(model.integratedAIState, data)
        let stale = await model.updateIntegratedAIState(expectedDigest: "stale") { $0.sessions = [] }
        XCTAssertFalse(stale); XCTAssertEqual(model.integratedAIState, data)
    }

    func testResidentRemovalCommitsWindowAssociationsWithHouseholdAndRetainsBothOnFailure() async throws {
        let store = ControlledStore()
        let model = AppModel(store: store)
        var household = SampleHouseholds.oak
        let removedID = try XCTUnwrap(household.people.last?.id)
        let retainedID = try XCTUnwrap(household.people.first?.id)
        household.people[household.people.count - 1].isSelf = false
        var home = SampleHomes.ranch
        home.portals[0].emergencyEscapePersonIDs = [removedID, retainedID]
        model.household = household; model.home = home
        await store.failWrites()
        let failed = await model.updateHousehold { _ = HouseholdEditing.removePerson(removedID, from: &$0) }
        XCTAssertFalse(failed)
        XCTAssertEqual(model.household, household)
        XCTAssertEqual(model.home, home)
        await store.allowWrites()
        let saved = await model.updateHousehold { _ = HouseholdEditing.removePerson(removedID, from: &$0) }
        XCTAssertTrue(saved)
        XCTAssertFalse(model.household?.people.contains { $0.id == removedID } ?? true)
        XCTAssertEqual(model.home?.portals[0].emergencyEscapePersonIDs, [retainedID])
        guard case .loaded(let disk) = await store.load() else { return XCTFail("Missing committed household/home") }
        XCTAssertEqual(disk.home, model.home)
        XCTAssertEqual(disk.household, model.household)
    }

    func testPersonalSetupSavesAndReloadsWithoutFictionalLayout() async {
        let store = InMemoryPrivateDataStore()
        let model = AppModel(store: store)
        var household = SampleHouseholds.oak
        household.isFictional = false
        let saved = await model.useSampleHouseholdIfNoHome(household)
        XCTAssertTrue(saved)
        XCTAssertNil(model.home)
        let reloaded = AppModel(store: store)
        await reloaded.loadPrivateData()
        XCTAssertEqual(reloaded.household?.id, household.id)
        XCTAssertNil(reloaded.home)
        XCTAssertEqual(reloaded.phase, .ready)
    }

    func testEditingALayoutlessHouseholdKeepsMeetingPlaces() async {
        let model = AppModel(store: InMemoryPrivateDataStore())
        var household = SampleHouseholds.oak
        household.isFictional = false
        model.household = household
        let meetup = SavedPlace(homeID: household.stableHomeID, purpose: .outsideMeetingPoint, label: "Fictional gate")
        model.savedPlaces = [meetup]
        household.displayName = "Updated family"
        let saved = await model.useSampleHouseholdIfNoHome(household)
        XCTAssertTrue(saved)
        XCTAssertNil(model.home)
        XCTAssertEqual(model.savedPlaces, [meetup])
    }

    func testFailedEditsAndCompletionsLeaveCommittedStateUntouched() async {
        let store = ControlledStore()
        let model = AppModel(store: store)
        model.household = SampleHouseholds.oak
        await store.failWrites()
        let original = model.household
        let changed = await model.updateHousehold { $0.displayName = "Unsaved draft" }
        XCTAssertFalse(changed)
        let complete = await model.markPreparationCompleted("prep.medicalBackup", subjectID: "equipment.first")
        XCTAssertFalse(complete)
        XCTAssertEqual(model.household, original)
        XCTAssertNotNil(model.lastError)
    }

    func testConcurrentSaveCannotOverwriteANewerCommittedCandidate() async {
        let store = ControlledStore()
        await store.holdWrites()
        let model = AppModel(store: store)
        model.household = SampleHouseholds.oak
        let first = Task { await model.updateHousehold { $0.displayName = "First saved edit" } }
        await store.waitForWrite()
        let competing = await model.updateHousehold { $0.displayName = "Competing draft" }
        XCTAssertFalse(competing)
        await store.release()
        let committed = await first.value
        XCTAssertTrue(committed)
        XCTAssertEqual(model.household?.displayName, "First saved edit")
        guard case .loaded(let disk) = await store.load() else { return XCTFail("Missing saved snapshot") }
        XCTAssertEqual(disk.household, model.household)
    }

    func testStaleWholeHouseholdDraftCannotReplaceNewerFacts() async {
        let model = AppModel(store: InMemoryPrivateDataStore())
        model.household = SampleHouseholds.oak
        var stale = SampleHouseholds.oak
        stale.displayName = "Old draft"
        let first = await model.updateHousehold { $0.displayName = "Current committed name" }
        XCTAssertTrue(first)
        let second = await model.updateHousehold(stale)
        XCTAssertFalse(second)
        XCTAssertEqual(model.household?.displayName, "Current committed name")
        XCTAssertNotNil(model.lastError)
    }

    func testCardOnlyDocumentContainsNoHiddenHomeOrMapSnapshot() {
        let model = AppModel.preview()
        XCTAssertNotNil(model.currentPlan()?.visualSnapshot?.home)
        let card = model.outageCard()
        XCTAssertEqual(card?.pages.map(\.id), ["family-card"])
        XCTAssertNil(card?.visualSnapshot)
    }

    func testRescanPreservesHomeIdentityAndGeographicPlaces() async {
        let model = AppModel(store: InMemoryPrivateDataStore())
        model.household = SampleHouseholds.oak
        model.home = SampleHomes.ranch
        let place = SavedPlace(id: "meetup", homeID: SampleHomes.ranch.id, purpose: .outsideMeetingPoint,
                               label: "Fictional driveway", provenance: .userSelected)
        model.savedPlaces = [place]
        var rescan = SampleHomes.ranch
        rescan.id = "new-capture-id"
        let saved = await model.updateHome(rescan, expectedRevision: model.home?.revision)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.home?.id, SampleHomes.ranch.id)
        XCTAssertEqual(model.savedPlaces, [place])
    }

    func testGeometryEditInvalidatesEscapeAndDrillChecksOnlyAfterSuccessfulSave() async throws {
        let store = ControlledStore()
        let model = AppModel(store: store)
        var household = SampleHouseholds.oak
        household.preparedness = PreparednessRecord()
        let checked = Date(timeIntervalSince1970: 1_792_000_000)
        var exit = PreparationFact(); exit.checkedAt = checked
        household.preparedness?.items["clearExits"] = exit
        household.preparedness?.items["fireDrill"] = exit
        household.preparedness?.items["firstAid"] = exit
        model.household = household; model.home = SampleHomes.ranch
        var renamed = SampleHomes.ranch; renamed.spaces[0].label = "Renamed room"
        let renamedSaved = await model.updateHome(renamed, expectedRevision: model.home?.revision)
        XCTAssertTrue(renamedSaved)
        XCTAssertEqual(model.household?.preparedness?.items["clearExits"]?.checkedAt, checked)
        XCTAssertEqual(model.household?.preparedness?.items["fireDrill"]?.checkedAt, checked)
        var corrected = try XCTUnwrap(model.home)
        corrected.portals[0].operable = .confirmed(false)
        let saved = await model.updateHome(corrected, expectedRevision: model.home?.revision)
        XCTAssertTrue(saved)
        XCTAssertNil(model.household?.preparedness?.items["clearExits"]?.checkedAt)
        XCTAssertNil(model.household?.preparedness?.items["fireDrill"]?.checkedAt)
        XCTAssertEqual(model.household?.preparedness?.items["firstAid"]?.checkedAt, checked)
        let prior = model.home
        await store.failWrites()
        corrected.portals[0].operable = .confirmed(true)
        let failed = await model.updateHome(corrected, expectedRevision: model.home?.revision)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.home, prior)
    }
}
