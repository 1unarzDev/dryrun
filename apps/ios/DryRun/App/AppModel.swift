import Foundation
import Observation
import DryRunCore

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
    var rehearsal: RehearsalSession?
    var comparison: RehearsalComparison?
    var lastError: String?
    var isWorking = false
    let capabilities = CapabilityService()
    let store: PrivateDataStore

    private var latestRunID = 0
    private var latestPlanID = 0

    init(store: PrivateDataStore) {
        self.store = store
    }

    var localizer: Localizer {
        content?.localizer(for: locale) ?? Localizer(locale: "en", tables: [:], manifest: nil)
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
    func markPreparationCompleted(_ actionID: String) async {
        await updateHousehold { h in
            guard !h.completedPreparations.contains(where: { $0.actionID == actionID }) else { return }
            h.completedPreparations.append(CompletedPreparation(actionID: actionID, completedAt: Date()))
        }
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
        guard let engine else { return }
        latestRunID += 1
        let runID = latestRunID
        isWorking = true
        defer { if runID == latestRunID { isWorking = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try engine.run(input) }.value
            // A late result from an older run, or one computed for an older household/home, never overwrites newer state.
            guard runID == latestRunID, isCurrent(result.input) else { return }
            if resetCursor || rehearsal == nil {
                rehearsal = RehearsalSession(result: result)
            } else {
                rehearsal?.replace(result: result)
            }
        } catch {
            guard runID == latestRunID else { return }
            lastError = String(describing: error)
        }
    }

    /// "Try this change": runs a simulation COPY with one intervention. The household is not modified.
    func tryChange(_ intervention: Intervention) async {
        guard let engine, let baseline = rehearsal?.result.input else { return }
        latestRunID += 1
        let runID = latestRunID
        isWorking = true
        defer { if runID == latestRunID { isWorking = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try engine.compare(baseline, applying: intervention) }.value
            guard runID == latestRunID, isCurrent(result.baseline.input) else { return }
            comparison = result
        } catch {
            guard runID == latestRunID else { return }
            lastError = String(describing: error)
        }
    }

    private func isCurrent(_ input: RehearsalInput) -> Bool {
        input.household.id == household?.id && input.household.revision == household?.revision
            && input.home.id == home?.id && input.home.revision == home?.revision
    }

    // MARK: - Plans

    /// Builds a plan for the selected scenarios by running each deterministically, then saves it in the vault.
    func generatePlan(scenarioIDs: [String], includePrivateNotes: Bool) async {
        guard let household, let home, let content, let scenarios, let engine else { return }
        latestPlanID += 1
        let planID = latestPlanID
        let locale = self.locale
        let localizer = content.localizer(for: locale)
        let resources = content.resources(forRegion: household.regionID)
        let inputs = scenarioIDs.compactMap { id -> RehearsalInput? in
            guard let s = scenarios.scenarios.first(where: { $0.id == id }) else { return nil }
            return RehearsalInput(household: household, home: home, scenarioID: id, scenarioVersion: s.version,
                                  contentVersion: content.contentVersion, seed: 1)
        }
        isWorking = true
        defer { if planID == latestPlanID { isWorking = false } }
        do {
            let doc = try await Task.detached(priority: .userInitiated) {
                let results = try inputs.map { try engine.run($0) }
                return PlanBuilder.build(household: household, home: home, results: results, localizer: localizer,
                                         resources: resources, contentVersion: content.contentVersion, generatedAt: Date(),
                                         options: .init(includePrivateNotes: includePrivateNotes))
            }.value
            guard planID == latestPlanID, !doc.isStale(household: self.household ?? household, home: self.home ?? home,
                                                       contentVersion: content.contentVersion), doc.locale == self.locale
            else { return }
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
        latestRunID += 1
    }

    private func invalidatePlans() { latestPlanID += 1 }

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
            latestRunID += 1; latestPlanID += 1
            phase = .onboarding
        } catch {
            lastError = String(describing: error)
        }
    }
}

/// Cursor over a deterministic result. The simulated clock is a teaching control, not a game timer.
struct RehearsalSession: Equatable {
    private(set) var result: RehearsalResult
    /// Number of events revealed so far.
    var revealed: Int = 0

    init(result: RehearsalResult) { self.result = result }

    mutating func replace(result: RehearsalResult) {
        self.result = result
        revealed = min(revealed, result.events.count)
    }

    var visibleEvents: ArraySlice<SimulationEvent> { result.events.prefix(revealed) }
    var currentMinute: Int { revealed == 0 ? 0 : result.events[revealed - 1].simMinute }
    var isFinished: Bool { revealed >= result.events.count && pendingDecision == nil }

    /// The first unanswered decision whose time has been reached (or is next).
    var pendingDecision: DecisionPoint? {
        let nextMinute = revealed < result.events.count ? result.events[revealed].simMinute : Int.max
        return result.decisions
            .filter { result.input.choices[$0.id] == nil && $0.simMinute <= nextMinute }
            .min { ($0.simMinute, $0.id) < ($1.simMinute, $1.id) }
    }

    mutating func advance() {
        guard pendingDecision == nil, revealed < result.events.count else { return }
        revealed += 1
    }

    mutating func revealAll() {
        while pendingDecision == nil && revealed < result.events.count { revealed += 1 }
    }

    var snapshotAtCursor: SimulationSnapshot? {
        result.snapshots.last { $0.simMinute <= currentMinute } ?? result.snapshots.first
    }
}
