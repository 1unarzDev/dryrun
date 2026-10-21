import XCTest
import DryRunCore
import DryRunVault
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
    func holdNextWrite() { hold = true; didBegin = false }
    func waitForWrite() async {
        if !didBegin { await withCheckedContinuation { began = $0 } }
    }
    func release() { hold = false; pending?.resume(); pending = nil }
}

/// Native app integration tests: run by scripts/mac/verify.sh. Authored on Linux; execution evidence is separate.
@MainActor
final class AppPersistenceTests: XCTestCase {
    private let testPreferences = UserDefaults(suiteName: "DryRun.AppPersistenceTests." + UUID().uuidString)!
    private func makeModel(store: PrivateDataStore, exampleStore: PrivateDataStore? = nil) -> AppModel {
        AppModel(store: store, exampleStore: exampleStore, preferences: testPreferences)
    }

    private func practiceCommand(_ model: AppModel) async throws -> SessionCommand {
        let step = try XCTUnwrap(model.practiceStep())
        let library = try XCTUnwrap(model.scenarios)
        if let choice = PracticeCheckSources.authoredChoice(step.session, competency: step.competency, library: library) {
            return SessionCommand(kind: "choose", target: choice.id, value: try XCTUnwrap(choice.options.first).id)
        }
        let receipt = try step.session.query(library: library)
        let accepted = await ExerciseActions.accepted(ExerciseActions.candidates(session: step.session, receipt: receipt, localizer: model.localizer),
                                                       session: step.session, library: library)
        return try XCTUnwrap(accepted.first?.commands.first)
    }

    func testPracticeSameRevisionPhasesRejectPreviouslyDisplayedCommands() async throws {
        let model = makeModel(store: ControlledStore())
        await model.start(); await model.useSampleHousehold(SampleHouseholds.oak)
        let began = await model.beginPracticeCheck()
        XCTAssertTrue(began)
        var revisions: [Int] = []
        for _ in 0..<4 {
            let identity = try XCTUnwrap(model.practiceStepIdentity)
            revisions.append(identity.revision)
            let command = try await practiceCommand(model)
            let acceptedAnswer = await model.submitPracticeAnswer(command, expected: identity)
            let answer = try XCTUnwrap(acceptedAnswer)
            XCTAssertNil(model.practiceStepIdentity)
            let revealed = await model.revealPracticeFeedback(attemptID: identity.attemptID, actionID: answer.actionID)
            XCTAssertTrue(revealed)
            let acknowledged = await model.acknowledgePracticeFeedback(attemptID: identity.attemptID, actionID: answer.actionID,
                                                                       expectedScope: identity.scope, expectedLocale: identity.locale)
            XCTAssertTrue(acknowledged)
            let before = model.integratedAIState
            let stale = await model.submitPracticeAnswer(command, expected: identity)
            XCTAssertNil(stale)
            XCTAssertEqual(model.integratedAIState, before)
        }
        XCTAssertLessThan(Set(revisions).count, revisions.count, "Distinct frozen phases can share a numeric revision")
    }

    func testAcceptedPracticeAnswerRecoversAfterFailedFeedbackSaveWithoutRegrading() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        await model.start(); await model.useSampleHousehold(SampleHouseholds.oak)
        let began = await model.beginPracticeCheck()
        XCTAssertTrue(began)
        let identity = try XCTUnwrap(model.practiceStepIdentity)
        let command = try await practiceCommand(model)
        let acceptedAnswer = await model.submitPracticeAnswer(command, expected: identity)
        let answer = try XCTUnwrap(acceptedAnswer)
        await store.failWrites()
        let failedReveal = await model.revealPracticeFeedback(attemptID: identity.attemptID, actionID: answer.actionID)
        XCTAssertFalse(failedReveal)
        XCTAssertEqual(model.pendingPracticeFeedback?.observation.actionID, answer.actionID)
        XCTAssertNil(model.practiceStep())
        await store.allowWrites()
        let restored = makeModel(store: store)
        await restored.start()
        XCTAssertEqual(restored.pendingPracticeFeedback?.observation, answer)
        let retry = await restored.revealPracticeFeedback(attemptID: identity.attemptID, actionID: answer.actionID)
        XCTAssertTrue(retry)
        XCTAssertNil(restored.practiceStep())
        XCTAssertEqual(restored.latestPracticeCheck?.observations?.count, 1)
        XCTAssertEqual(restored.pendingPracticeFeedback?.session.commits.filter { $0.actor == "user" }.count, 1)
        let acknowledged = await restored.acknowledgePracticeFeedback(attemptID: identity.attemptID, actionID: answer.actionID,
                                                                     expectedScope: restored.scopeSessionID, expectedLocale: restored.locale)
        XCTAssertTrue(acknowledged)
        XCTAssertNotNil(restored.practiceStep())
        XCTAssertEqual(restored.latestPracticeCheck?.observations?.first?.credit, answer.credit)
    }

    func testPracticeDisplayedAnswerCannotCrossLocaleOrFamilyScope() async throws {
        let model = makeModel(store: ControlledStore())
        await model.start(); await model.useSampleHousehold(SampleHouseholds.oak)
        let began = await model.beginPracticeCheck()
        XCTAssertTrue(began)
        let identity = try XCTUnwrap(model.practiceStepIdentity)
        let command = try await practiceCommand(model)
        model.locale = "es"
        let beforeLocale = model.integratedAIState
        let wrongLocale = await model.submitPracticeAnswer(command, expected: identity)
        XCTAssertNil(wrongLocale)
        XCTAssertEqual(model.integratedAIState, beforeLocale)
        await model.useSampleHousehold(SampleHouseholds.lake)
        let beforeFamily = model.integratedAIState
        let wrongFamily = await model.submitPracticeAnswer(command, expected: identity)
        XCTAssertNil(wrongFamily)
        XCTAssertEqual(model.integratedAIState, beforeFamily)
    }

    func testLegacyRevealedFeedbackDoesNotBlockNextPhaseOrChangeGrade() async throws {
        // Authored legacy JSON, never a recorded app answer.
        let legacyJSON = Data(#"{"competencyID":"communication","actionID":"authored-old","acceptedRevision":1,"receiptDigest":"authored-digest","credit":0.5,"feedbackRevealed":true}"#.utf8)
        let legacy = try JSONDecoder().decode(PracticeObservation.self, from: legacyJSON)
        XCTAssertNil(legacy.feedbackAcknowledged)
        let model = makeModel(store: ControlledStore())
        await model.start(); await model.useSampleHousehold(SampleHouseholds.oak)
        let began = await model.beginPracticeCheck()
        XCTAssertTrue(began)
        let identity = try XCTUnwrap(model.practiceStepIdentity)
        let command = try await practiceCommand(model)
        let accepted = await model.submitPracticeAnswer(command, expected: identity)
        let observation = try XCTUnwrap(accepted)
        XCTAssertEqual(observation.feedbackAcknowledged, false)
        let revealed = await model.revealPracticeFeedback(attemptID: identity.attemptID, actionID: observation.actionID)
        XCTAssertTrue(revealed)
        let migrated = await model.updateAIState { state, _ in
            state.practiceAttempts[0].observations?[0].feedbackAcknowledged = legacy.feedbackAcknowledged
        }
        XCTAssertTrue(migrated)
        XCTAssertNil(model.pendingPracticeFeedback)
        XCTAssertNotNil(model.practiceStep())
        XCTAssertEqual(model.latestPracticeCheck?.observations?.first?.credit, observation.credit)
        XCTAssertEqual(model.latestPracticeCheck?.observations?.first?.receiptDigest, observation.receiptDigest)
    }

    func testConfirmedInventorySurvivesHouseholdEditsAndFailedWritesPublishNothing() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        model.household = SampleHouseholds.oak; model.home = SampleHomes.ranch
        let water = InventoryItem(id: "water-1", physicalID: "jug-1", category: "water", quantity: .confirmed(4),
                                  unit: .usGallon, usableQuantity: .confirmed(4), accessible: .confirmed(true))
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let confirmed = await model.updateAIState { state, household in
            try state.confirmInventory([water], household: &household, baseHouseholdRevision: household.revision,
                                       baseInventoryRevision: state.inventory.revision, at: date) { _, _ in }
        }
        XCTAssertTrue(confirmed)
        XCTAssertEqual(model.aiState.inventory.items.map(\.id), ["water-1"])
        // An unrelated household edit carries the ledger through the same atomic snapshot.
        let renamed = await model.updateHousehold { $0.people[0].alias = "Renamed (fictional)" }
        XCTAssertTrue(renamed)
        let saved = await store.snapshot
        XCTAssertEqual(saved?.aiState?.inventory.items.map(\.id), ["water-1"])
        // A failed write leaves both the published ledger and the stored one unchanged.
        await store.failWrites()
        let extra = InventoryItem(id: "water-2", physicalID: "jug-2", category: "water", quantity: .confirmed(1), unit: .usGallon)
        let failed = await model.updateAIState { state, household in
            try state.confirmInventory([extra], household: &household, baseHouseholdRevision: household.revision,
                                       baseInventoryRevision: state.inventory.revision, at: date) { _, _ in }
        }
        XCTAssertFalse(failed)
        XCTAssertEqual(model.aiState.inventory.items.map(\.id), ["water-1"])
        let stored = await store.snapshot
        XCTAssertEqual(stored?.aiState?.inventory.items.map(\.id), ["water-1"])
    }

    func testEncryptedVaultRoundTripsIntegratedAIStateAndRelaunchRestoresIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = InMemoryVaultKeyStore()
        func store() -> VaultPrivateDataStore {
            VaultPrivateDataStore(repository: HouseholdVaultRepository(locations: VaultLocations(root: root), keyStore: keys,
                                                                       protection: VaultFileProtection()))
        }
        let first = makeModel(store: store())
        await first.useSampleHousehold(SampleHouseholds.oak)
        let item = InventoryItem(id: "light-1", physicalID: "flashlight-1", category: "light", quantity: .confirmed(1),
                                 unit: .count, preparationKind: .flashlight)
        let confirmed = await first.updateAIState { state, household in
            try state.confirmInventory([item], household: &household, baseHouseholdRevision: household.revision,
                                       baseInventoryRevision: state.inventory.revision, at: Date()) { _, _ in }
        }
        XCTAssertTrue(confirmed)
        // A fresh model over the same encrypted files is a relaunch.
        let relaunched = makeModel(store: store())
        await relaunched.loadPrivateData()
        XCTAssertEqual(relaunched.aiState.inventory.items.map(\.id), ["light-1"])
        XCTAssertEqual(relaunched.aiState.inventory.revision, first.aiState.inventory.revision)
    }

    func testAdaptiveExerciseResumesAfterRelaunchAndFailedSaveDoesNotAdvanceIt() async throws {
        let store = ControlledStore()
        let first = makeModel(store: store)
        await first.start()
        await first.useSampleHousehold(SampleHouseholds.oak)
        await first.openAdaptive(scenarioID: "home-fire")
        var exercise = try XCTUnwrap(first.adaptive)
        // Advance to the first authored decision and answer it.
        for _ in 0..<6 where exercise.receipt.directorState?.awaitingUserAction != true {
            await first.advanceAdaptive()
            exercise = try XCTUnwrap(first.adaptive)
        }
        let scenarios = try XCTUnwrap(first.scenarios)
        let choice = try XCTUnwrap(LocalDirector.dueChoice(session: exercise.session, receipt: exercise.receipt, library: scenarios))
        let answered = await first.submitAdaptive([SessionCommand(kind: "choose", target: choice.id, value: choice.options[0].id)])
        XCTAssertTrue(answered)
        let committed = try XCTUnwrap(first.adaptive)
        // A failed write leaves the published exercise exactly where it was.
        await store.failWrites()
        await first.advanceAdaptive()
        XCTAssertEqual(first.adaptive?.session.revision, committed.session.revision)
        await store.allowWrites()
        // Relaunch over the same store resumes the same session at the committed revision.
        let relaunched = makeModel(store: store)
        await relaunched.start()
        await relaunched.openAdaptive(scenarioID: "home-fire")
        XCTAssertEqual(relaunched.adaptive?.session.id, committed.session.id)
        XCTAssertEqual(relaunched.adaptive?.receipt, committed.receipt)
    }

    func testExampleStorePreservesPersonalSnapshotAndCardSelectionThroughDelete() async throws {
        let personal = ControlledStore()
        let examples = ControlledStore()
        let model = makeModel(store: personal, exampleStore: examples)
        var family = SampleHouseholds.oak
        family.isFictional = false
        let created = await model.useSampleHouseholdIfNoHome(family)
        XCTAssertTrue(created)
        let originalSelection = model.cardSelection
        let globalBefore = AppModel.storedCardSelection(preferences: testPreferences)
        guard case .loaded(let original) = await personal.load() else {
            return XCTFail("Missing authored personal fixture")
        }
        await model.useSampleHousehold(SampleHouseholds.lake)
        model.cardSelection = FamilyCardSelection(includeCriticalInformation: false, includeMedication: false, includeResponderInstructions: false, includeContacts: false)
        XCTAssertEqual(AppModel.storedCardSelection(preferences: testPreferences), globalBefore)
        guard case .loaded(let stillPersonal) = await personal.load() else {
            return XCTFail("Example selection removed personal fixture")
        }
        XCTAssertEqual(stillPersonal.household, original.household)
        let deleted = await model.deleteAllPrivateData()
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.household, original.household)
        XCTAssertEqual(model.cardSelection, originalSelection)
        XCTAssertEqual(AppModel.storedCardSelection(preferences: testPreferences), globalBefore)
        guard case .empty = await examples.load() else {
            return XCTFail("Example deletion did not clear example store")
        }
    }

    func testRehearsalSaveSerializesRepeatedChoicesAndFamilyReset() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        await model.startRehearsal(scenarioID: "home-fire")
        model.rehearsal?.advanceUntilDecisionOrEnd()
        let decision = try XCTUnwrap(model.rehearsal?.pendingDecision)
        let scope = model.scopeSessionID
        await store.holdNextWrite()
        let first = Task { await model.choose(option: "get-out", at: decision.id) }
        await store.waitForWrite()
        await model.choose(option: "grab-belongings", at: decision.id)
        await model.useSampleHousehold(SampleHouseholds.lake)
        XCTAssertEqual(model.scopeSessionID, scope)
        XCTAssertEqual(model.household?.id, "hh-oak")
        XCTAssertNil(model.rehearsal?.result.input.choices[decision.id])
        await store.release()
        await first.value
        XCTAssertEqual(model.rehearsal?.result.input.choices[decision.id], "get-out")
        let data = try XCTUnwrap(model.integratedAIState)
        let state = try DryRunJSON.decoder().decode(IntegratedAIState.self, from: data)
        XCTAssertEqual(state.sessions.last?.commits.filter { $0.actor == "user" }.count, 1)
    }

    func testFailedRehearsalStartCannotPublishAnUnsavedSession() async {
        let store = ControlledStore()
        let model = makeModel(store: store)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        await store.failWrites()
        await model.startRehearsal(scenarioID: "home-fire")
        XCTAssertNil(model.rehearsal)
        XCTAssertNil(model.rehearsalSessionID)
        XCTAssertNil(model.integratedAIState)
        XCTAssertNotNil(model.lastError)
    }

    func testAllSixRehearsalsCommitChoiceAndRestoreCanonicalTraceAndScene() async throws {
        for hazard in ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"] {
            let store = ControlledStore()
            let model = makeModel(store: store)
            await model.start()
            await model.useSampleHousehold(SampleHouseholds.oak)
            await model.startRehearsal(scenarioID: hazard)
            model.rehearsal?.advanceUntilDecisionOrEnd()
            let decision = try XCTUnwrap(model.rehearsal?.pendingDecision)
            let option = try XCTUnwrap(decision.options.first { $0.isRecommended } ?? decision.options.first)
            await model.choose(option: option.id, at: decision.id)
            let data = try XCTUnwrap(model.integratedAIState)
            let state = try DryRunJSON.decoder().decode(IntegratedAIState.self, from: data)
            let id = try XCTUnwrap(model.rehearsalSessionID)
            let session = try XCTUnwrap(state.sessions.first { $0.id == id })
            XCTAssertTrue(session.initial.choices.isEmpty)
            XCTAssertEqual(session.commits.filter { $0.actor == "user" }.count, 1)
            XCTAssertEqual(AuthoredRehearsalBridge.acceptedInput(session).choices[decision.id], option.id)
            XCTAssertEqual(model.rehearsal?.snapshotAtCursor?.spatialState, model.rehearsalReceipt?.snapshot.spatialState)
            XCTAssertEqual(model.rehearsal?.snapshotAtCursor?.resources, model.rehearsalReceipt?.snapshot.resources)
            XCTAssertTrue(state.practiceAttempts.isEmpty)
            let restored = makeModel(store: store)
            await restored.start()
            XCTAssertEqual(restored.rehearsalSessionID, id)
            XCTAssertEqual(restored.rehearsalReceipt, model.rehearsalReceipt)
            XCTAssertEqual(restored.rehearsal?.result.input.choices[decision.id], option.id)
            XCTAssertEqual(restored.rehearsal?.snapshotAtCursor?.spatialState, model.rehearsalReceipt?.snapshot.spatialState)
            // Repeated stale button callbacks cannot append another answer.
            await restored.choose(option: option.id, at: decision.id)
            XCTAssertEqual(restored.integratedAIState, data)
        }
    }

    func testFailedChoiceSavePublishesNoAnswerReceiptOrNewSessionState() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        await model.startRehearsal(scenarioID: "home-fire")
        model.rehearsal?.advanceUntilDecisionOrEnd()
        let decision = try XCTUnwrap(model.rehearsal?.pendingDecision)
        let cursor = model.rehearsal, receipt = model.rehearsalReceipt, data = model.integratedAIState
        await store.failWrites()
        await model.choose(option: "get-out", at: decision.id)
        XCTAssertEqual(model.rehearsal, cursor)
        XCTAssertEqual(model.rehearsalReceipt, receipt)
        XCTAssertEqual(model.integratedAIState, data)
        XCTAssertNil(model.rehearsal?.result.input.choices[decision.id])
        XCTAssertNotNil(model.lastError)
        await store.allowWrites()
        await model.choose(option: "get-out", at: decision.id)
        XCTAssertEqual(model.rehearsal?.result.input.choices[decision.id], "get-out")
    }

    func testRehearsalCallbackCannotCrossFamilyResetOrMaterialRevision() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        await model.start()
        await model.useSampleHousehold(SampleHouseholds.oak)
        await model.startRehearsal(scenarioID: "home-fire")
        model.rehearsal?.advanceUntilDecisionOrEnd()
        let decision = try XCTUnwrap(model.rehearsal?.pendingDecision)
        let previousID = model.rehearsalSessionID
        await model.useSampleHousehold(SampleHouseholds.lake)
        await model.choose(option: "get-out", at: decision.id)
        XCTAssertNil(model.integratedAIState)
        XCTAssertNil(model.rehearsal)
        await model.useSampleHousehold(SampleHouseholds.oak)
        await model.startRehearsal(scenarioID: "home-fire")
        XCTAssertNotEqual(model.rehearsalSessionID, previousID)
        let oldData = model.integratedAIState
        var changed = try XCTUnwrap(model.home)
        changed.revision += 1
        model.home = changed
        model.restorePersistedRehearsal()
        XCTAssertNil(model.rehearsalSessionID)
        XCTAssertEqual(model.integratedAIState, oldData)
    }

    func testHomeDraftCannotCrossFamilyOrResetWithMatchingHomeRevision() async throws {
        let model = makeModel(store: InMemoryPrivateDataStore())
        await model.useSampleHousehold(SampleHouseholds.oak)
        let original = try XCTUnwrap(model.home)
        let oldScope = model.scopeSessionID
        await model.useSampleHousehold(SampleHouseholds.lake)
        let other = model.home
        let crossed = await model.updateHome(original, baseRevision: original.revision, scopeSessionID: oldScope)
        XCTAssertFalse(crossed)
        XCTAssertEqual(model.home, other)
        let beforeReset = model.scopeSessionID
        await model.useSampleHousehold(SampleHouseholds.lake)
        XCTAssertNotEqual(model.scopeSessionID, beforeReset)
        let resetCrossed = await model.updateHome(original, baseRevision: original.revision, scopeSessionID: beforeReset)
        XCTAssertFalse(resetCrossed)
        var current = try XCTUnwrap(model.home)
        current.spaces[0].label = "Current family's room"
        let currentSaved = await model.updateHome(current, baseRevision: current.revision, scopeSessionID: model.scopeSessionID)
        XCTAssertTrue(currentSaved)
    }

    func testUnsavedHomeDraftCannotOverwriteAHomeCreatedWhileEditorWasOpen() async {
        let model = makeModel(store: InMemoryPrivateDataStore())
        model.household = SampleHouseholds.oak
        let first = await model.updateHome(SampleHomes.ranch, baseRevision: nil)
        XCTAssertTrue(first)
        let savedHome = model.home
        let stale = await model.updateHome(SampleHomes.twoStory, baseRevision: nil)
        XCTAssertFalse(stale)
        XCTAssertEqual(model.home, savedHome)
    }

    func testStaleHomeDraftCannotOverwriteNewerHomeAndFailedSaveKeepsDraft() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        model.household = SampleHouseholds.oak
        model.home = SampleHomes.ranch
        let original = SampleHomes.ranch
        var first = original
        first.spaces[0].label = "First committed room"
        let saved = await model.updateHome(first, baseRevision: original.revision)
        XCTAssertTrue(saved)
        let committed = try XCTUnwrap(model.home)
        var stale = original
        stale.spaces[0].label = "Stale draft room"
        let staleSaved = await model.updateHome(stale, baseRevision: original.revision)
        XCTAssertFalse(staleSaved)
        XCTAssertEqual(model.home, committed)
        await store.failWrites()
        var draft = committed
        draft.spaces[0].label = "Retry this room"
        let failed = await model.updateHome(draft, baseRevision: committed.revision)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.home, committed)
        XCTAssertEqual(draft.spaces[0].label, "Retry this room")
    }

    func testOrdinaryEditsPreserveIntegratedEvidenceAcrossReloadAndExampleResetClearsIt() async throws {
        let state = try DryRunJSON.encoder().encode(IntegratedAIState())
        let store = InMemoryPrivateDataStore(snapshot: PrivateSnapshot(
            household: SampleHouseholds.oak, home: SampleHomes.ranch, integratedAIState: state))
        let model = makeModel(store: store)
        await model.loadPrivateData()
        XCTAssertEqual(model.integratedAIState, state)
        let changed = await model.updateHousehold { $0.displayName = "Edited fictional family" }
        XCTAssertTrue(changed)
        let reloaded = makeModel(store: store)
        await reloaded.loadPrivateData()
        XCTAssertEqual(reloaded.integratedAIState, state)
        await reloaded.useSampleHousehold(SampleHouseholds.oak)
        XCTAssertNil(reloaded.integratedAIState)
        guard case .loaded(let disk) = await store.load() else { return XCTFail("Missing reset example") }
        XCTAssertNil(disk.integratedAIState)
    }

    func testFailedExampleSwitchRetainsCurrentIntegratedEvidence() async throws {
        let state = try DryRunJSON.encoder().encode(IntegratedAIState())
        let store = ControlledStore()
        try await store.save(PrivateSnapshot(household: SampleHouseholds.oak, integratedAIState: state))
        let model = makeModel(store: store)
        await model.loadPrivateData()
        await store.failWrites()
        await model.useSampleHousehold(SampleHouseholds.lake)
        XCTAssertEqual(model.household?.id, SampleHouseholds.oak.id)
        XCTAssertEqual(model.integratedAIState, state)
    }

    func testResidentRemovalCommitsWindowAssociationsWithHouseholdAndRetainsBothOnFailure() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
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
        let model = makeModel(store: store)
        var household = SampleHouseholds.oak
        household.isFictional = false
        let saved = await model.useSampleHouseholdIfNoHome(household)
        XCTAssertTrue(saved)
        XCTAssertNil(model.home)
        let reloaded = makeModel(store: store)
        await reloaded.loadPrivateData()
        XCTAssertEqual(reloaded.household?.id, household.id)
        XCTAssertNil(reloaded.home)
        XCTAssertEqual(reloaded.phase, .ready)
    }

    func testEditingALayoutlessHouseholdKeepsMeetingPlaces() async {
        let model = makeModel(store: InMemoryPrivateDataStore())
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
        let model = makeModel(store: store)
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
        let model = makeModel(store: store)
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
        let model = makeModel(store: InMemoryPrivateDataStore())
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
        let model = makeModel(store: InMemoryPrivateDataStore())
        model.household = SampleHouseholds.oak
        model.home = SampleHomes.ranch
        let place = SavedPlace(id: "meetup", homeID: SampleHomes.ranch.id, purpose: .outsideMeetingPoint,
                               label: "Fictional driveway", provenance: .userSelected)
        model.savedPlaces = [place]
        var rescan = SampleHomes.ranch
        rescan.id = "new-capture-id"
        let saved = await model.updateHome(rescan)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.home?.id, SampleHomes.ranch.id)
        XCTAssertEqual(model.savedPlaces, [place])
    }

    func testGeometryEditInvalidatesEscapeAndDrillChecksOnlyAfterSuccessfulSave() async throws {
        let store = ControlledStore()
        let model = makeModel(store: store)
        var household = SampleHouseholds.oak
        household.preparedness = PreparednessRecord()
        let checked = Date(timeIntervalSince1970: 1_792_000_000)
        var exit = PreparationFact(); exit.checkedAt = checked
        household.preparedness?.items["clearExits"] = exit
        household.preparedness?.items["fireDrill"] = exit
        household.preparedness?.items["firstAid"] = exit
        model.household = household; model.home = SampleHomes.ranch
        var renamed = SampleHomes.ranch; renamed.spaces[0].label = "Renamed room"
        let renamedSaved = await model.updateHome(renamed)
        XCTAssertTrue(renamedSaved)
        XCTAssertEqual(model.household?.preparedness?.items["clearExits"]?.checkedAt, checked)
        XCTAssertEqual(model.household?.preparedness?.items["fireDrill"]?.checkedAt, checked)
        var corrected = try XCTUnwrap(model.home)
        corrected.portals[0].operable = .confirmed(false)
        let saved = await model.updateHome(corrected)
        XCTAssertTrue(saved)
        XCTAssertNil(model.household?.preparedness?.items["clearExits"]?.checkedAt)
        XCTAssertNil(model.household?.preparedness?.items["fireDrill"]?.checkedAt)
        XCTAssertEqual(model.household?.preparedness?.items["firstAid"]?.checkedAt, checked)
        let prior = model.home
        await store.failWrites()
        corrected.portals[0].operable = .confirmed(true)
        let failed = await model.updateHome(corrected)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.home, prior)
    }
}
