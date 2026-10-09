import Foundation
import Observation
import DryRunCore
import DryRunVault

/// Application state. Heavy work (simulation, routing, plan building) runs off the main actor;
/// every async result carries a run ID + revision key and is dropped if a newer request superseded it.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case onboarding
        case ready
        /// Keychain key not available because the device is locked. Not corruption; retry after unlock.
        case vaultLocked
        /// Stored data could not be opened. The original file is preserved; nothing was reset.
        case vaultNeedsRecovery(String)
        case contentFailed(String)
    }

    var phase: Phase = .loading
    private(set) var content: ContentLibrary?
    private(set) var scenarios: ScenarioLibrary?
    private(set) var engine: RehearsalEngine?
    var household: HouseholdProfile?
    var home: HomeModel?
    var locale: String = "en" { didSet { if locale != oldValue { invalidatePlans() } } }
    var savedPlan: PlanDocument?
    var rehearsal: RehearsalCursor?
    var comparison: RehearsalComparison?
    var lastError: String?
    var isWorking = false
    let capabilities = CapabilityService()
    let store: PrivateDataStore
    /// Public-only client (region ID in, public data out). Backed by an atomic known-good cache.
    let publicClient: PublicAPIClient = AppModel.makePublicClient()

    private var runGate = LatestRequestGate()
    private var planGate = LatestRequestGate()

    /// Identity of the current household/home/content. Results computed for anything else are discarded.
    var currentKey: RevisionKey? {
        guard let household, let home, let content else { return nil }
        return RevisionKey(householdID: household.id, householdRevision: household.revision, homeID: home.id,
                           homeRevision: home.revision, contentVersion: content.contentVersion, algorithmVersion: "app/1")
    }

    init(store: PrivateDataStore) {
        self.store = store
    }

    var localizer: Localizer {
        content?.localizer(for: locale) ?? Localizer(locale: "en", tables: [:], manifest: nil)
    }

    /// No deployed backend by default: `DryRunPublicAPIBaseURL` is absent from Info.plist, so the client
    /// serves cached/bundled data only. Setting it is a deliberate deployment decision (see BACKLOG).
    static func makePublicClient() -> PublicAPIClient {
        let base = (Bundle.main.object(forInfoDictionaryKey: "DryRunPublicAPIBaseURL") as? String).flatMap(URL.init(string:))
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DryRun/public", isDirectory: true)
        return PublicAPIClient(baseURL: base, store: PublicPackStore(directory: dir))
    }

    /// Plans also depend on the selected language: a late English plan must not land after switching to Vietnamese.
    var planKey: RevisionKey? {
        guard var key = currentKey else { return nil }
        key.algorithmVersion = "plan/\(PlanDocument.schemaVersion)/\(locale)"
        return key
    }

    // MARK: - Startup

    func start() async {
        capabilities.refresh()
        do {
            let root = try ContentLocator.contentRoot()
            let loaded = try await Task.detached(priority: .userInitiated) {
                let c = try ContentLibrary.load(from: root)
                let s = try ScenarioLibrary.load(from: root.appendingPathComponent("scenarios"))
                return (c, s)
            }.value
            content = loaded.0
            scenarios = loaded.1
            engine = RehearsalEngine(library: loaded.1, planner: EgressPlanner())
        } catch {
            phase = .contentFailed(String(describing: error))
            return
        }
        await loadPrivateData()
    }

    func loadPrivateData() async {
        switch await store.load() {
        case .empty:
            phase = .onboarding
        case .loaded(let snapshot):
            household = snapshot.household
            home = snapshot.home
            savedPlan = snapshot.savedPlan
            locale = snapshot.household.preferredLocale
            phase = .ready
        case .locked:
            phase = .vaultLocked
        case .needsRecovery(let message):
            // Never fall through to onboarding: that would look like a successful empty household.
            phase = .vaultNeedsRecovery(message)
        }
    }

    // MARK: - Household

    func useSampleHousehold(_ sample: HouseholdProfile) async {
        household = sample
        home = SampleHomes.ranch
        locale = sample.preferredLocale
        phase = .ready
        await persist()
    }

    func updateHousehold(_ edit: (inout HouseholdProfile) -> Void) async {
        guard var h = household else { return }
        edit(&h)
        h.bumpRevision()
        household = h
        invalidateDerived()
        await persist()
    }

    func updateHome(_ newHome: HomeModel) async {
        var h = newHome
        if let old = home, old != newHome, old.revision == newHome.revision { h.bumpRevision() }
        home = h
        invalidateDerived()
        await persist()
    }

    /// "Mark preparation completed": changes the REAL household state, only on explicit user action.
    /// A completion is a record of real-world action, not a simulation input (the engine never reads it), so it does
    /// not bump the revision or discard the rehearsal on screen. Facts the preparation changed (e.g. a confirmed
    /// backup) are edited through the household setup, which does invalidate derived results.
    func markPreparationCompleted(_ actionID: String) async {
        guard var h = household, !h.completedPreparations.contains(where: { $0.actionID == actionID }) else { return }
        h.completedPreparations.append(CompletedPreparation(actionID: actionID, completedAt: Date()))
        h.updatedAt = Date()
        household = h
        await persist()
    }

    // MARK: - Rehearsal

    func startRehearsal(scenarioID: String, variants: [String] = []) async {
        guard let household, let home, let content, let scenarios,
              let scenario = scenarios.scenarios.first(where: { $0.id == scenarioID }) else { return }
        let input = RehearsalInput(household: household, home: home, scenarioID: scenarioID,
                                   scenarioVersion: scenario.version, contentVersion: content.contentVersion,
                                   seed: 1, variants: variants)
        comparison = nil
        await run(input, resetCursor: true)
    }

    /// Choosing at a decision point re-runs the deterministic engine with the choice and keeps the cursor.
    func choose(option: String, at decisionID: String) async {
        guard var input = rehearsal?.result.input else { return }
        input.choices[decisionID] = option
        await run(input, resetCursor: false)
    }

    private func run(_ input: RehearsalInput, resetCursor: Bool) async {
        guard let engine, let key = currentKey else { return }
        let ticket = runGate.begin(for: key)
        isWorking = true
        defer { if runGate.shouldApply(ticket, current: currentKey) { isWorking = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try engine.run(input) }.value
            // A late result from an older run, or one computed for an older household/home, never overwrites newer state.
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            if resetCursor || rehearsal == nil {
                rehearsal = RehearsalCursor(result: result)
            } else {
                rehearsal?.replace(result: result)
            }
        } catch {
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            lastError = String(describing: error)
        }
    }

    /// "Try this change": runs a simulation COPY with one intervention. The household is not modified.
    func tryChange(_ intervention: Intervention) async {
        guard let engine, let baseline = rehearsal?.result.input, let key = currentKey else { return }
        let ticket = runGate.begin(for: key)
        isWorking = true
        defer { if runGate.shouldApply(ticket, current: currentKey) { isWorking = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try engine.compare(baseline, applying: intervention) }.value
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            comparison = result
        } catch {
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            lastError = String(describing: error)
        }
    }

    // MARK: - Plans

    /// Builds a plan for the selected scenarios by running each deterministically, then saves it in the vault.
    func generatePlan(scenarioIDs: [String], includePrivateNotes: Bool) async {
        guard let household, let home, let content, let scenarios, let engine, let key = planKey else { return }
        let ticket = planGate.begin(for: key)
        let locale = self.locale
        let localizer = content.localizer(for: locale)
        let resources = content.resources(forRegion: household.regionID)
        let inputs = scenarioIDs.compactMap { id -> RehearsalInput? in
            guard let s = scenarios.scenarios.first(where: { $0.id == id }) else { return nil }
            return RehearsalInput(household: household, home: home, scenarioID: id, scenarioVersion: s.version,
                                  contentVersion: content.contentVersion, seed: 1)
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let doc = try await Task.detached(priority: .userInitiated) {
                let results = try inputs.map { try engine.run($0) }
                return PlanBuilder.build(household: household, home: home, results: results, localizer: localizer,
                                         resources: resources, contentVersion: content.contentVersion, generatedAt: Date(),
                                         options: .init(includePrivateNotes: includePrivateNotes))
            }.value
            // Language or household changed while building: drop this plan rather than save a mismatched one.
            guard planGate.shouldApply(ticket, current: planKey) else { return }
            savedPlan = doc
            await persist()
        } catch {
            lastError = String(describing: error)
        }
    }

    var planIsStale: Bool {
        guard let savedPlan, let household, let home, let content else { return false }
        return savedPlan.isStale(household: household, home: home, contentVersion: content.contentVersion) || savedPlan.locale != locale
    }

    private func invalidateDerived() {
        // Routes, rehearsal results, and comparisons are tied to revisions; drop them so nothing stale is shown.
        rehearsal = nil
        comparison = nil
        runGate.invalidate()
    }

    private func invalidatePlans() { planGate.invalidate() }

    // MARK: - Persistence

    func persist() async {
        guard let household, let home else { return }
        do {
            try await store.save(PrivateSnapshot(household: household, home: home, savedPlan: savedPlan))
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Delete everything private: vault, derived caches, temporary exports, and the key.
    func deleteAllPrivateData() async {
        do {
            try await store.deleteAll()
            TemporaryExports.purgeAll()
            household = nil; home = nil; savedPlan = nil; rehearsal = nil; comparison = nil
            runGate.invalidate(); planGate.invalidate()
            phase = .onboarding
        } catch {
            lastError = String(describing: error)
        }
    }
}
