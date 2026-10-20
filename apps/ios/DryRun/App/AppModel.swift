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
    /// Explicitly saved geographic planning places. Coordinates remain separate from indoor floor-plan geometry.
    var savedPlaces: [SavedPlace] = []
    /// Confirmed inventory, concern reviews, exercise sessions, practice attempts and scorecards, saved atomically
    /// with the household. Changed only after `save(snapshot:)` succeeds so a failed write never publishes new state.
    private(set) var aiState = IntegratedAIState()
    var locale: String = "en" { didSet { if locale != oldValue { invalidatePlans() } } }
    var savedPlan: PlanDocument?
    /// The family's choice of what the card shows, shared by the card view, Plan, Share/Print and saved plans so the
    /// preview always matches what is sent. Only these on/off choices are kept (in UserDefaults), never any content.
    var cardSelection: FamilyCardSelection = AppModel.storedCardSelection() {
        didSet { if cardSelection != oldValue { AppModel.storeCardSelection(cardSelection) } }
    }
    private static let cardSelectionKey = "familyCardSelection.v1"
    static func storedCardSelection() -> FamilyCardSelection {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestingInMemory"),
              let data = UserDefaults.standard.data(forKey: cardSelectionKey),
              let value = try? JSONDecoder().decode(FamilyCardSelection.self, from: data) else { return FamilyCardSelection() }
        return value
    }
    static func storeCardSelection(_ value: FamilyCardSelection) {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestingInMemory") else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: cardSelectionKey)
    }
    /// Every scenario run once with default choices, for the Next steps screen. Tied to the household/home revision
    /// like other derived results; completions are applied on read, so marking one done does not re-run anything.
    var nextStepResults: [RehearsalResult]?
    var rehearsal: RehearsalCursor?
    /// The open adaptive exercise: an incremental Core session whose receipts drive the scene. Unlike `rehearsal` it
    /// is saved (in `aiState.sessions`) after every committed turn, so it resumes after a relaunch.
    private(set) var adaptive: AdaptiveExercise?
    var comparison: RehearsalComparison?
    var lastError: String?
    /// Requests in flight (rehearsal runs, comparisons, plan builds). A count, not a flag, so one request finishing
    /// cannot hide another that is still running, and a superseded request cannot leave the spinner on.
    private var workInFlight = 0
    var isWorking: Bool { workInFlight > 0 }
    let capabilities = CapabilityService()
    let store: PrivateDataStore
    /// Shared validated public-resource snapshot used by Help and map planning. Browsing a different county never
    /// changes the household's region or the resources selected for a saved plan.
    var regionalResources: RegionalResourcesStore?
    /// Public-only client (region ID in, public data out). Backed by an atomic known-good cache.
    let publicClient: PublicAPIClient = AppModel.makePublicClient()

    private var runGate = LatestRequestGate()
    private var planGate = LatestRequestGate()
    private var nextGate = LatestRequestGate()
    private var scoreGate = LatestRequestGate()
    /// Versioned draft rubric (content/ai/rubric-v0.json). The numbers are product policy, not safety thresholds.
    private(set) var rubric: RubricDefinition?
    /// Deterministic, local: accepted household facts, confirmed inventory, the reviewed fire stress envelope and
    /// eligible practice. No model output can change it. Recomputed per revision; nil until computed.
    private(set) var scorecard: Scorecard?

    struct Scorecard: Sendable {
        let key: RevisionKey
        let card: PreparednessScorecard
        let assessments: [CriterionAssessment]
        /// The reviewed home-fire envelope run against this home; hypothetical, never a household fact.
        let fireStress: StressTestFinding?
    }

    /// The score's inputs: household/home/content plus confirmed inventory and practice attempts.
    var scoreKey: RevisionKey? {
        guard var key = currentKey, let rubric else { return nil }
        let answers = aiState.practiceAttempts.reduce(0) { $0 + ($1.observations?.count ?? $1.answers.count) }
        key.algorithmVersion = "score/\(rubric.version)/inv\(aiState.inventory.revision)/practice\(aiState.practiceAttempts.count)-\(answers)"
        return key
    }

    /// Computes the scorecard off the main actor unless the current one already matches every input.
    func refreshScorecard() async {
        guard let household, let scenarios, let rubric, let key = scoreKey, scorecard?.key != key else { return }
        let home = self.home, places = savedPlaces, state = aiState
        let ticket = scoreGate.begin(for: key)
        do {
            let result = try await Task.detached(priority: .utility) { () -> Scorecard in
                let date = Date()
                var fire: StressTestFinding?
                if let home, let scenario = scenarios.scenario("home-fire") {
                    let input = RehearsalInput(household: household, home: home, scenarioID: scenario.id, scenarioVersion: scenario.version,
                                               contentVersion: key.contentVersion, seed: 1)
                    // The reviewed baseline envelope only: the alarm and the fire's origin, no extra blockages.
                    fire = try? PlanStressTester.execute(initial: input, profileIDs: ["evt.home-fire.alarm", "evt.home-fire.fire-origin"],
                                                         library: scenarios)
                }
                let assessments = try HouseholdAssessment.assess(household: household, home: home, inventory: state.inventory,
                                                                 places: places, stressFindings: fire.map { [$0] } ?? [], at: date)
                let card = try state.compileScorecard(rubric: rubric, assessments: assessments, library: scenarios)
                return Scorecard(key: key, card: card, assessments: assessments, fireStress: fire)
            }.value
            guard scoreGate.shouldApply(ticket, current: scoreKey) else { return }
            scorecard = result
        } catch {
            guard scoreGate.shouldApply(ticket, current: scoreKey) else { return }
            lastError = String(describing: error)
        }
    }
    private var privateWriteInFlight = false

    /// Identity of the current household/home/content. Results computed for anything else are discarded.
    var currentKey: RevisionKey? {
        guard let household, let content else { return nil }
        return RevisionKey(householdID: household.id, householdRevision: household.revision, homeID: home?.id ?? household.stableHomeID,
                           homeRevision: home?.revision ?? 0, contentVersion: content.contentVersion, algorithmVersion: "app/1")
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
                let r = try JSONDecoder().decode(RubricDefinition.self, from: Data(contentsOf: root.appendingPathComponent("ai/rubric-v0.json")))
                return (c, s, r)
            }.value
            rubric = loaded.2
            content = loaded.0
            scenarios = loaded.1
            engine = RehearsalEngine(library: loaded.1, planner: EgressPlanner())
            configureRegionalResources()
        } catch {
            phase = .contentFailed(String(describing: error))
            return
        }
        await loadPrivateData()
        await applyDemoLaunch(DemoLaunch.current)
    }

    // MARK: - Demo / screenshot mode (fictional data, in-memory store only)

    func applyDemoLaunch(_ d: DemoLaunch) async {
        if let l = d.locale { locale = l }
        guard d.isActive, let sample = SampleHouseholds.all.first(where: { $0.id == d.householdID }) else { return }
        let demoHome = d.homeID.flatMap { id in SampleHomes.all.first { $0.id == id } }
        await useSampleHousehold(sample, demoHome: demoHome)
        if let l = d.locale { locale = l }
        if !d.planScenarios.isEmpty { await generatePlan(scenarioIDs: d.planScenarios, includePrivateNotes: false, selection: cardSelection) }
        #if DEBUG
        if d.writePlanPDFs { await writeDemoPlanArtifacts() }
        #endif
    }

    /// Advances the open rehearsal for screenshots. `.end` answers each decision with its recommended option.
    func demoAdvance(_ step: DemoLaunch.Step) async {
        switch step {
        case .start:
            return
        case .decision:
            rehearsal?.advanceUntilDecisionOrEnd()
        case .end:
            for _ in 0..<12 {
                rehearsal?.advanceUntilDecisionOrEnd()
                guard let decision = rehearsal?.pendingDecision else { break }
                let option = decision.options.first(where: \.isRecommended) ?? decision.options[0]
                await choose(option: option.id, at: decision.id)
            }
            rehearsal?.advanceUntilDecisionOrEnd()
        }
    }

    #if DEBUG
    /// Writes EN/ES/VI plan PDFs and PlanDocument JSON for the demo household to Documents/demo-plans,
    /// then a DONE marker. Verification tooling copies them out of the simulator container.
    func writeDemoPlanArtifacts() async {
        guard let household else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-plans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = locale
        var report: [String] = []
        for l in ["en", "es", "vi"] {
            locale = l
            // Fictional data only: every selectable family-card field is included so reviewers see the full layout.
            let selection = FamilyCardSelection(includeCriticalInformation: true, includeMedication: true, includeResponderInstructions: true, includeContacts: true)
            await generatePlan(scenarioIDs: DemoLaunch.allScenarios, includePrivateNotes: false, selection: selection)
            guard let plan = savedPlan, plan.locale == l else { report.append("\(l): plan not generated"); continue }
            var panels: [PlanMapPanel] = []
            if let snapshot = plan.visualSnapshot {
                panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: localizer("map.neighborhood"), localizer: localizer)
            }
            let base = "plan-\(household.id)-\(l)"
            for paper in PlanPDFRenderer.Paper.allCases where l == "en" || paper == .letter {
                let output = PlanPDFRenderer().render(plan, paper: paper, mapPanels: panels)
                let suffix = paper == .letter ? "" : "-a4"
                try? output.data.write(to: dir.appendingPathComponent("\(base)\(suffix).pdf"))
                let issues = PlanValidator.validate(plan, household: household)
                report.append("\(l)\(suffix): pages=\(output.pageCount) maps=\(panels.count) continued=\(output.continuedPageIDs.joined(separator: ",")) issues=\(issues.map(\.description))")
            }
            if let card = outageCard(selection: selection) {
                let output = PlanPDFRenderer().render(card)
                try? output.data.write(to: dir.appendingPathComponent("plan-\(household.id)-card-\(l).pdf"))
                report.append("\(l) card: pages=\(output.pageCount)")
            }
            try? DryRunJSON.encoder().encode(plan).write(to: dir.appendingPathComponent("\(base).json"))
        }
        locale = original
        try? report.joined(separator: "\n").write(to: dir.appendingPathComponent("DONE-\(household.id).txt"), atomically: true, encoding: .utf8)
    }
    #endif

    #if DEBUG
    /// Synchronous, fully offline model for SwiftUI previews (fictional household, in-memory store).
    static func preview(householdID: String = "hh-oak", locale: String? = nil,
                        scenarioID: String? = nil, step: DemoLaunch.Step = .end, planScenarios: [String] = []) -> AppModel {
        let model = AppModel(store: InMemoryPrivateDataStore())
        guard let root = try? ContentLocator.contentRoot(),
              let content = try? ContentLibrary.load(from: root),
              let scenarios = try? ScenarioLibrary.load(from: root.appendingPathComponent("scenarios")),
              let household = SampleHouseholds.all.first(where: { $0.id == householdID }) else {
            model.phase = .contentFailed("Preview content unavailable")
            return model
        }
        let engine = RehearsalEngine(library: scenarios, planner: EgressPlanner())
        model.content = content
        model.scenarios = scenarios
        model.engine = engine
        model.household = household
        model.home = SampleHomes.ranch
        model.locale = locale ?? household.preferredLocale
        model.phase = .ready
        func input(_ id: String) -> RehearsalInput? {
            guard let s = scenarios.scenarios.first(where: { $0.id == id }) else { return nil }
            return RehearsalInput(household: household, home: SampleHomes.ranch, scenarioID: id, scenarioVersion: s.version,
                                  contentVersion: content.contentVersion, seed: 1)
        }
        if let scenarioID, var i = input(scenarioID), var result = try? engine.run(i) {
            var cursor = RehearsalCursor(result: result)
            if step != .start {
                cursor.advanceUntilDecisionOrEnd()
                while step == .end, let d = cursor.pendingDecision {
                    i.choices[d.id] = (d.options.first(where: \.isRecommended) ?? d.options[0]).id
                    guard let next = try? engine.run(i) else { break }
                    result = next
                    cursor.replace(result: result)
                    cursor.advanceUntilDecisionOrEnd()
                }
            }
            model.rehearsal = cursor
        }
        if !planScenarios.isEmpty {
            let results = planScenarios.compactMap(input).compactMap { try? engine.run($0) }
            model.savedPlan = PlanBuilder.build(household: household, home: SampleHomes.ranch, results: results,
                                                localizer: content.localizer(for: model.locale),
                                                resources: content.resources(forRegion: household.regionID),
                                                contentVersion: content.contentVersion, generatedAt: Date())
        }
        return model
    }
    #endif

    func loadPrivateData() async {
        switch await store.load() {
        case .empty:
            phase = .onboarding
        case .loaded(let snapshot):
            var restored = snapshot.household
            if restored.homeID == nil, let existingHome = snapshot.home { restored.homeID = existingHome.id }
            household = restored
            savedPlaces = HomeMeetingPlaces.placesIncludingLocalMeetup(home: snapshot.home, places: snapshot.savedPlaces, recordedAt: restored.updatedAt)
            home = snapshot.home.map { HomeMeetingPlaces.synchronize($0, places: savedPlaces) }
            savedPlan = snapshot.savedPlan
            aiState = snapshot.aiState ?? IntegratedAIState()
            locale = snapshot.household.preferredLocale
            configureRegionalResources()
            phase = .ready
        case .locked:
            phase = .vaultLocked
        case .needsRecovery(let message):
            // Never fall through to onboarding: that would look like a successful empty household.
            phase = .vaultNeedsRecovery(message)
        }
    }

    // MARK: - Household

    func useSampleHousehold(_ sample: HouseholdProfile, demoHome: HomeModel? = nil) async {
        var sample = sample
        let sampleHome = demoHome ?? SampleHomes.ranch
        sample.homeID = sampleHome.id
        if demoHome != nil {
            sample.housing.homeType = sampleHome.dwellingType ?? (sampleHome.id.contains("apartment") ? .apartment : .singleFamily)
            sample.housing.floorCount = sampleHome.floors.count
            sample.privateLocation = nil
            sample.siteHazards = nil
            for index in sample.people.indices where !sampleHome.spaces.contains(where: { $0.id == sample.people[index].sleepingSpaceID }) {
                sample.people[index].sleepingSpaceID = nil
            }
        }
        var extraPlaces: [SavedPlace] = []
        if sample.id == "hh-oak", sample.privateLocation == nil, demoHome == nil {
            // Demo-only map inputs: a public town-centre pin and a distant relative's town, both labelled fictional.
            // They show the neighborhood map and its separate distant panel; no real household address is implied.
            sample.privateLocation = PrivateLocation(addressLine: "Ranch road outside Stephenville, TX (fictional)", latitude: 32.2207, longitude: -98.2023,
                                                     city: "Stephenville", administrativeArea: "TX", countryCode: "US")
            extraPlaces = [SavedPlace(id: "demo-backup-meetup", homeID: sample.stableHomeID, purpose: .backupMeetingPlace,
                                      label: "Aunt's house in Abilene (fictional)", coordinate: GeographicCoordinate(latitude: 32.4487, longitude: -99.7331),
                                      addressText: "Abilene, TX (fictional household)", findingInstructions: "Call the aunt before driving; meet at her front porch.",
                                      provenance: .fixture, createdAt: sample.updatedAt ?? Date(), updatedAt: sample.updatedAt ?? Date())]
        }
        let places = HomeMeetingPlaces.placesIncludingLocalMeetup(home: sampleHome, places: extraPlaces, recordedAt: sample.updatedAt)
        let candidateHome = HomeMeetingPlaces.synchronize(sampleHome, places: places)
        let snapshot = PrivateSnapshot(household: sample, home: candidateHome, savedPlan: nil, savedPlaces: places, aiState: IntegratedAIState())
        guard await save(snapshot: snapshot) else { return }
        aiState = IntegratedAIState()
        adaptive = nil
        household = sample
        home = candidateHome
        savedPlaces = places
        configureRegionalResources()
        invalidateDerived()
        locale = sample.preferredLocale
        phase = .ready
    }

    /// Creates a personal household without fabricating geometry. The candidate is written before it becomes
    /// observable so an onboarding save failure leaves the user on the editable form rather than showing a false
    /// ready state.
    @discardableResult
    func useSampleHouseholdIfNoHome(_ candidateHousehold: HouseholdProfile) async -> Bool {
        // A fictional example household is replaced outright ("Set up my household" from the demo debrief):
        // nothing about the made-up family, its sample home or its places carries over.
        guard household == nil || household?.isFictional == true else {
            let saved = await updateHousehold(candidateHousehold)
            if saved { locale = candidateHousehold.preferredLocale }
            return saved
        }
        var candidateHousehold = candidateHousehold
        if candidateHousehold.homeID == nil { candidateHousehold.homeID = candidateHousehold.stableHomeID }
        // Nothing recorded for the fictional example (supplies, reviews, practice) carries into a real household.
        let snapshot = PrivateSnapshot(household: candidateHousehold, home: nil, savedPlan: nil, savedPlaces: [], aiState: IntegratedAIState())
        guard await save(snapshot: snapshot) else { return false }
        aiState = IntegratedAIState()
        adaptive = nil
        household = candidateHousehold
        home = nil
        savedPlaces = []
        savedPlan = nil
        // Clinical card content is opt-in for a real family, whatever the example household showed.
        cardSelection = FamilyCardSelection()
        configureRegionalResources()
        invalidateDerived()
        locale = candidateHousehold.preferredLocale
        phase = .ready
        return true
    }

    /// Set by "See how it works": the root view opens this rehearsal once the tabs are up, then clears it.
    var pendingScenarioID: String?
    /// Set by flows that end somewhere else (e.g. the debrief's "See what to prepare next"): the root view switches
    /// to this tab, pops the Rehearse stack, then clears it.
    var pendingTab: String?

    /// One tap from onboarding to the flagship rehearsal: the Oak household's freeze with power loss.
    func startDemo() async {
        await useSampleHousehold(SampleHouseholds.oak)
        // The example family's card shows everything it can, so the demo card is readable at a glance. A real
        // household created afterwards resets this to the opt-in default (see `useSampleHouseholdIfNoHome`).
        cardSelection = FamilyCardSelection(includeCriticalInformation: true, includeMedication: true, includeResponderInstructions: true, includeContacts: true)
        pendingScenarioID = "freeze-power-loss"
    }

    @discardableResult
    func updateHousehold(_ edit: (inout HouseholdProfile) -> Void) async -> Bool {
        guard let previous = household else { return false }
        var h = previous
        edit(&h)
        h.bumpRevision()
        let candidateHome = HouseholdEditing.homeAfterRemovingResidents(previous: previous, updated: h, home: home)
        let snapshot = PrivateSnapshot(household: h, home: candidateHome, savedPlan: savedPlan, savedPlaces: savedPlaces)
        guard await save(snapshot: snapshot) else { return false }
        household = h
        home = candidateHome
        configureRegionalResources()
        invalidateDerived()
        return true
    }

    /// Applies a local AI-state transaction (inventory confirmation, concern review, practice capture, scorecard) and the
    /// household it changes in one atomic save. A thrown or failed transaction publishes nothing.
    @discardableResult
    func updateAIState(_ transaction: (inout IntegratedAIState, inout HouseholdProfile) throws -> Void) async -> Bool {
        guard let previous = household else { return false }
        var state = aiState, h = previous
        do { try transaction(&state, &h) } catch { lastError = String(describing: error); return false }
        let householdChanged = h != previous
        guard await save(snapshot: PrivateSnapshot(household: h, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces, aiState: state)) else { return false }
        aiState = state
        if householdChanged {
            household = h
            invalidateDerived()
        }
        return true
    }

    /// One reviewed batch of typed supply items into the confirmed ledger, with the household projection (stored water)
    /// in the same atomic save. Bumps the household revision, so tasks, routes, resources and the score refresh.
    @discardableResult
    func confirmInventory(_ items: [InventoryItem]) async -> Bool {
        guard !items.isEmpty else { return false }
        let date = Date()
        return await updateAIState { state, household in
            try state.confirmInventory(items, household: &household, baseHouseholdRevision: household.revision,
                                       baseInventoryRevision: state.inventory.revision, at: date) { _, _ in }
        }
    }

    /// Deterministic gaps from confirmed inventory (water, household food days, reviewed flashlight/first-aid identity).
    var inventoryGaps: [SupplyGap] {
        guard let household else { return [] }
        return (try? aiState.inventory.preparationGaps(personIDs: household.people.map(\.id), at: Date())) ?? []
    }

    /// Focused forms retain their draft revision. A stale whole-household form must not overwrite later edits.
    @discardableResult
    func updateHousehold(_ candidate: HouseholdProfile) async -> Bool {
        guard let household, candidate.id == household.id, candidate.revision == household.revision else {
            lastError = localizer("family.staleDraft")
            return false
        }
        return await updateHousehold { $0 = candidate }
    }

    @discardableResult
    func updateSiteHazards(_ profile: SiteHazardProfile?) async -> Bool {
        await updateHousehold { household in SiteHazardEditing.stage(profile, in: &household) }
    }

    /// Moving is explicitly separate from correcting an address or rescanning this home.
    /// Family, contacts, equipment and supplies are retained; old geometry, room assignments and local destinations reset.
    @discardableResult
    func moveHome(to location: PrivateLocation) async -> Bool {
        guard var candidate = household else { return false }
        candidate.homeID = "home-\(UUID().uuidString)"
        candidate.privateLocation = location
        candidate.siteHazards = nil
        candidate.regionID = ""
        for index in candidate.people.indices { candidate.people[index].sleepingSpaceID = nil }
        candidate.preparedness?.items.removeValue(forKey: "clearExits")
        candidate.preparedness?.items.removeValue(forKey: "fireDrill")
        candidate.preparedness?.items.removeValue(forKey: "smokeAlarms")
        candidate.preparedness?.items.removeValue(forKey: "coAlarms")
        candidate.preparedness?.items.removeValue(forKey: "extinguisher")
        candidate.bumpRevision()
        // Supplies and practice history move with the family; reviews and exercises of the old home's rooms do not.
        var movedState = aiState
        movedState.concerns = ConcernLedger()
        movedState.sessions = []
        guard await save(snapshot: PrivateSnapshot(household: candidate, home: nil, savedPlan: nil, savedPlaces: [], aiState: movedState)) else { return false }
        aiState = movedState
        household = candidate
        home = nil
        savedPlaces = []
        savedPlan = nil
        configureRegionalResources()
        invalidateDerived()
        return true
    }

    @discardableResult
    func updateHome(_ newHome: HomeModel, expectedRevision: Int?) async -> Bool {
        guard let household else { return false }
        guard var h = HomeEditTransaction.prepare(newHome, baseRevision: expectedRevision, current: home, homeID: household.stableHomeID) else {
            lastError = "This home changed while you were editing. Your draft was kept; reopen the latest home before saving."
            return false
        }
        h.id = home?.id ?? household.stableHomeID
        h.dwellingType = household.housing.homeType
        let candidatePlaces = HomeMeetingPlaces.placesAfterHomeEdit(previous: home, updated: h, places: savedPlaces, editedAt: Date())
        h = HomeMeetingPlaces.synchronize(h, places: candidatePlaces)
        h.revision = (home?.revision ?? 0) + 1
        var candidateHousehold = household
        candidateHousehold.homeID = h.id
        if HomeGeometryEditor.requiresNewEscapeCheck(previous: home, updated: h) {
            candidateHousehold.preparedness?.items["clearExits"]?.checkedAt = nil
            candidateHousehold.preparedness?.items["fireDrill"]?.checkedAt = nil
        }
        // A scan ordinal is not room identity. Preserve only supported capture-lineage/manual
        // associations, and leave unrelated rescans explicitly unassigned for the focused review.
        for index in candidateHousehold.people.indices {
            candidateHousehold.people[index].sleepingSpaceID = HomeRoomAssociations.remappedRoomID(
                candidateHousehold.people[index].sleepingSpaceID, from: home, to: h)
        }
        if candidateHousehold != household { candidateHousehold.bumpRevision() }
        let snapshot = PrivateSnapshot(household: candidateHousehold, home: h, savedPlan: savedPlan,
                                       savedPlaces: candidatePlaces)
        guard await save(snapshot: snapshot) else { return false }
        self.household = candidateHousehold
        self.home = h
        self.savedPlaces = candidatePlaces
        invalidateDerived()
        return true
    }

    /// "Mark preparation completed": changes the REAL household state, only on explicit user action.
    /// A completion is a record of real-world action, not a simulation input (the engine never reads it), so it does
    /// not bump the revision or discard the rehearsal on screen. Facts the preparation changed (e.g. a confirmed
    /// backup) are edited through the household setup, which does invalidate derived results.
    @discardableResult
    func markPreparationCompleted(_ actionID: String, subjectID: String? = nil, factFingerprint: String? = nil) async -> Bool {
        let record = CompletedPreparation(actionID: actionID, completedAt: Date(), subjectID: subjectID, factFingerprint: factFingerprint)
        guard var h = household, !h.completedPreparations.contains(where: { $0.taskID == record.taskID }) else { return false }
        h.completedPreparations.append(record)
        h.updatedAt = Date()
        guard await save(snapshot: PrivateSnapshot(household: h, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces)) else { return false }
        household = h
        return true
    }

    @discardableResult
    func reopenPreparation(_ taskID: String) async -> Bool {
        guard var h = household else { return false }
        h.completedPreparations.removeAll { $0.taskID == taskID }
        h.updatedAt = Date()
        guard await save(snapshot: PrivateSnapshot(household: h, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces)) else { return false }
        household = h
        return true
    }

    /// Language pickers call this. The choice is stored with the household so it survives a relaunch (startup reads
    /// `preferredLocale`). Language is not a simulation input, so this does not bump the revision or discard the
    /// rehearsal on screen; a saved plan in another language is reported stale by `planIsStale`.
    func selectLocale(_ newLocale: String) async {
        guard newLocale != locale else { return }
        guard var h = household else { locale = newLocale; return }
        h.preferredLocale = newLocale
        h.updatedAt = Date()
        guard await save(snapshot: PrivateSnapshot(household: h, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces)) else { return }
        household = h
        locale = newLocale
    }

    /// Title of a preparation where no `Recommendation` is at hand (before/after sheet, completed list). Action titles
    /// have placeholders such as {device}; the values come from the rehearsal on screen when it has that action.
    func actionTitle(_ actionID: String) -> String {
        let fromComparison = comparison?.baseline.recommendations.first(where: { $0.actionID == actionID })
        let fromRehearsal = rehearsal?.result.recommendations.first(where: { $0.actionID == actionID })
        if let rec = fromComparison ?? fromRehearsal {
            return localizer(rec.titleKey, rec.localizedTemplateValues(household: household, localizer: localizer))
        }
        // No values available: never show a raw {placeholder} to the user.
        return localizer("action.\(actionID).title")
            .replacingOccurrences(of: "\\{[A-Za-z0-9_]+\\}", with: "…", options: .regularExpression)
    }

    // MARK: - Rehearsal

    func startRehearsal(scenarioID: String, variants: [String] = []) async {
        guard let household, let content, let scenarios,
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
        workInFlight += 1
        defer { workInFlight -= 1 }
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
        // Clear the previous comparison first: if this one fails, the sheet must not show the old change as the new one.
        comparison = nil
        guard let engine, let baseline = rehearsal?.result.input, let key = currentKey else { return }
        let ticket = runGate.begin(for: key)
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try engine.compare(baseline, applying: intervention) }.value
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            comparison = result
        } catch {
            guard runGate.shouldApply(ticket, current: currentKey) else { return }
            lastError = String(describing: error)
        }
    }

    // MARK: - Adaptive exercise

    enum DirectorSource: String, Sendable { case local, gemini }

    struct AdaptiveExercise: Sendable {
        var session: SimulationSession
        var receipt: SessionReceipt
        /// The receipt before the newest commit, so the scene can say what this turn changed.
        var previous: SessionReceipt?
        /// Who proposed the newest director turn, and its unverified narration (Gemini only).
        var lastDirector: DirectorSource?
        var narration: String?
        /// Household/home/content revision the session's frozen snapshot was taken from.
        let sourceKey: RevisionKey
    }

    /// Exercises kept for resume/history; older finished ones are dropped first.
    static let retainedSessions = 8

    /// Opens the newest unfinished exercise of this scenario taken from the current household/home revision, or a new one.
    func openAdaptive(scenarioID: String, restart: Bool = false) async {
        guard let household, let content, let scenarios, let key = currentKey,
              let scenario = scenarios.scenario(scenarioID) else { return }
        if !restart, adaptive?.session.initial.scenarioID == scenarioID, adaptive?.sourceKey == key { return }
        let home = self.home
        if !restart, let resumable = aiState.sessions.last(where: { s in
            s.initial.scenarioID == scenarioID && s.initial.household == household && s.initial.home == home
                && s.initial.contentVersion == content.contentVersion && s.initial.scenarioVersion == scenario.version
        }) {
            let library = scenarios
            let replay = Task.detached(priority: .userInitiated) { try resumable.query(library: library) }
            if let receipt = try? await replay.value, !receipt.finished {
                adaptive = AdaptiveExercise(session: resumable, receipt: receipt, previous: nil, lastDirector: nil, narration: nil, sourceKey: key)
                return
            }
        }
        let input = RehearsalInput(household: household, home: home, scenarioID: scenarioID, scenarioVersion: scenario.version,
                                   contentVersion: content.contentVersion, seed: 1)
        let library = scenarios
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            let (session, receipt) = try await Task.detached(priority: .userInitiated) {
                let session = try SimulationSession.initialize(id: "exercise-\(UUID().uuidString)", initial: input, library: library)
                return (session, try session.query(library: library))
            }.value
            guard currentKey == key else { return }
            adaptive = AdaptiveExercise(session: session, receipt: receipt, previous: nil, lastDirector: nil, narration: nil, sourceKey: key)
            await advanceAdaptive()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// The family's action. Validated by the Core reducer; an infeasible action is reported, never mapped to a default.
    @discardableResult
    func submitAdaptive(_ commands: [SessionCommand]) async -> Bool {
        guard let exercise = adaptive, !exercise.receipt.finished else { return false }
        let commit = SessionCommit(id: "user-\(UUID().uuidString)", actor: "user", baseRevision: exercise.session.revision, commands: commands)
        guard let scenarios else { return false }
        return await commitAdaptive(director: nil, narration: nil) { session in try session.commit(commit, library: scenarios) }
    }

    // MARK: - Gemini preparation (fictional households, development gateway)

    enum PreparationAIState: Equatable {
        case working
        case ready(PreparationFeatureBridge.Personalization)
        case unavailable(String)
    }
    /// Bound to the household/home revisions and confirmed inventory it was computed from; any edit retires it.
    struct PreparationAIKey: Equatable { var revision: RevisionKey; var inventoryRevision: Int }
    private(set) var preparationAI: (key: PreparationAIKey, state: PreparationAIState)?

    private var preparationAIKey: PreparationAIKey? {
        currentKey.map { PreparationAIKey(revision: $0, inventoryRevision: aiState.inventory.revision) }
    }
    var preparationAIAvailable: Bool { DirectorGatewayClient.current != nil && household?.isFictional == true && rubric != nil }
    /// The current state, or nil when nothing was asked for these exact inputs.
    var preparationAIState: PreparationAIState? {
        guard let preparationAI, preparationAI.key == preparationAIKey else { return nil }
        return preparationAI.state
    }
    var preparationPersonalization: PreparationFeatureBridge.Personalization? {
        if case .ready(let p) = preparationAIState { return p }
        return nil
    }

    /// Asks Gemini (through the gateway) to choose, order and explain preparations for this household. Only an explicit
    /// tap starts it. The answer is applied only if the inputs did not change meanwhile and only as Core accepts it.
    func personalizePreparation() async {
        guard preparationAIAvailable, let client = DirectorGatewayClient.current, let household, let rubric,
              let key = preparationAIKey, nextStepResults != nil, preparationAIState != .working else { return }
        let request: PreparationFeatureBridge.Request
        do {
            request = try PreparationFeatureBridge.request(requestID: "prep-\(UUID().uuidString)", household: household, home: home,
                                                           inventory: aiState.inventory, rubric: rubric)
        } catch {
            preparationAI = (key, .unavailable("context"))
            return
        }
        preparationAI = (key, .working)
        workInFlight += 1
        let outcome = await client.preparation(request)
        workInFlight -= 1
        guard preparationAIKey == key, let summary = nextSteps else { return }
        switch outcome {
        case .completed(let output, let revision) where revision == household.revision:
            preparationAI = (key, .ready(PreparationFeatureBridge.accept(output, summary: summary, household: household)))
        case .completed:
            preparationAI = (key, .unavailable("stale"))
        case .unavailable(let reason):
            preparationAI = (key, .unavailable(reason))
        }
    }

    /// Returns the Prepare list to the app's own order for these inputs.
    func clearPreparationPersonalization() { preparationAI = nil }

    /// Opt-in for this app session only: Gemini directs the next moments of a fictional household's exercise.
    /// Requires a development gateway (launch arguments); real households never use it until production authorization.
    var cloudDirectorEnabled = false
    /// Why the last cloud turn fell back to this phone, shown beside the scene; nil when it did not.
    private(set) var directorFallbackNote: String?

    var cloudDirectorAvailable: Bool { DirectorGatewayClient.current != nil && household?.isFictional == true }

    /// One director turn. With the cloud director enabled, Gemini proposes through the gateway (tool calls run
    /// read-only on this phone at the same revision); otherwise, or whenever that fails, the local director proposes.
    /// Either way Core validates the proposal before anything is saved or shown.
    func advanceAdaptive() async {
        guard let exercise = adaptive, let scenarios, !exercise.receipt.finished,
              exercise.receipt.directorState?.awaitingUserAction != true else { return }
        directorFallbackNote = nil
        if cloudDirectorEnabled, cloudDirectorAvailable, let client = DirectorGatewayClient.current,
           exercise.session.initial.household.isFictional {
            workInFlight += 1
            let outcome = await geminiProposal(client: client, exercise: exercise, library: scenarios)
            workInFlight -= 1
            switch outcome {
            case .success(let proposal, let binding):
                let applied = await commitAdaptive(director: .gemini, narration: proposal.purpose) { session in
                    try proposal.commit(to: &session, binding: binding, library: scenarios, persist: { _ in })
                }
                if applied { return }
                directorFallbackNote = localizer("adaptive.fallback.rejected")
            case .waitingForFamily:
                return
            case .failure(let stage):
                directorFallbackNote = localizer("adaptive.fallback.unavailable")
                #if DEBUG
                // Development builds name the failing stage (never payloads) so the wired-device loop can be diagnosed.
                directorFallbackNote? += " [\(stage)]"
                #endif
            }
        }
        guard let current = adaptive, current.session.revision == exercise.session.revision,
              let commit = LocalDirector.nextCommit(session: current.session, receipt: current.receipt, library: scenarios) else { return }
        await commitAdaptive(director: .local, narration: nil) { session in try session.commit(commit, library: scenarios) }
    }

    private enum GeminiOutcome: Sendable { case success(DirectorProposal, AgentContextBinding), waitingForFamily, failure(String) }

    /// Runs one gateway operation to completion. Each tool call executes through Core on the unchanged session; if the
    /// family acts or the exercise changes meanwhile, the operation is cancelled and nothing from it is applied.
    private func geminiProposal(client: DirectorGatewayClient, exercise: AdaptiveExercise, library: ScenarioLibrary) async -> GeminiOutcome {
        let session = exercise.session, receipt = exercise.receipt
        guard let request = try? DirectorGatewayBridge.operationRequest(requestID: "op-\(UUID().uuidString)", session: session,
                                                                         receipt: receipt, library: library) else { return .failure("context") }
        let binding = request.context.binding
        var outcome = await client.start(request)
        // The gateway allows at most 6 provider calls per operation (up to 5 model tool calls), then asks this phone
        // to validate the final proposal's suggested actions once (validateSuggestedActions) before completing.
        for _ in 0..<6 {
            guard case .needsTools(let token, let toolBinding, let call) = outcome else { break }
            guard toolBinding == binding, adaptive?.session.id == session.id, adaptive?.session.revision == session.revision else {
                await client.cancel(token: token)
                return .failure("stale")
            }
            let execution = Task.detached(priority: .userInitiated) {
                try DirectorGatewayBridge.execute(call, session: session, binding: binding, library: library)
            }
            let result: DirectorGatewayBridge.ToolResult
            do { result = try await execution.value } catch {
                await client.cancel(token: token)
                return .failure("tool \(call.name): \(error)")
            }
            outcome = await client.resume(token: token, binding: binding, callID: call.id, result: result)
        }
        switch outcome {
        case .completed(let proposal):
            guard adaptive?.session.id == session.id, adaptive?.session.revision == session.revision else { return .failure("stale") }
            return .success(proposal, binding)
        case .needsUserAction: return .waitingForFamily
        case .unavailable(let reason): return .failure(reason)
        case .needsTools: return .failure("tool_budget")
        }
    }

    /// Whether a candidate user action is accepted by the host right now (preview only; nothing is committed).
    func adaptiveAccepts(_ commands: [SessionCommand]) -> Bool {
        guard let exercise = adaptive, let scenarios, !commands.isEmpty else { return false }
        let commit = SessionCommit(id: "preview", actor: "user", baseRevision: exercise.session.revision, commands: commands)
        return (try? exercise.session.preview(commit, library: scenarios)) != nil
    }

    /// Commit → save session with the household snapshot → publish. A failed save leaves the exercise unchanged.
    @discardableResult
    private func commitAdaptive(director: DirectorSource?, narration: String?,
                                _ apply: @escaping @Sendable (inout SimulationSession) throws -> SessionReceipt) async -> Bool {
        guard let exercise = adaptive, let household else { return false }
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            let (session, receipt) = try await Task.detached(priority: .userInitiated) {
                var candidate = exercise.session
                let receipt = try apply(&candidate)
                return (candidate, receipt)
            }.value
            var state = aiState
            state.sessions.removeAll { $0.id == session.id }
            state.sessions.append(session)
            if state.sessions.count > Self.retainedSessions {
                // Drop the oldest exercises first; the open one is always kept.
                let overflow = state.sessions.count - Self.retainedSessions
                // Practice sources are frozen evidence for recorded answers; they are never trimmed.
                let practice = Set(state.practiceAttempts.flatMap { ($0.phaseSources ?? []) + ($0.source.map { [$0] } ?? []) }.map(\.sessionID))
                let removable = state.sessions.filter { $0.id != session.id && !practice.contains($0.id) }.prefix(overflow).map(\.id)
                state.sessions.removeAll { removable.contains($0.id) }
            }
            guard adaptive?.session.id == exercise.session.id, adaptive?.session.revision == exercise.session.revision else { return false }
            guard await save(snapshot: PrivateSnapshot(household: household, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces, aiState: state)) else { return false }
            aiState = state
            adaptive = AdaptiveExercise(session: session, receipt: receipt, previous: exercise.receipt,
                                        lastDirector: director ?? exercise.lastDirector, narration: director == nil ? exercise.narration : narration,
                                        sourceKey: exercise.sourceKey)
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    // MARK: - Practice check (four frozen situations, graded before feedback)

    /// The newest check, complete or not. A newer incomplete check is the current practice result.
    var latestPracticeCheck: PracticeAttempt? {
        aiState.practiceAttempts.filter { $0.phaseSources != nil && $0.archivedUnverified != true }.max { $0.sequence < $1.sequence }
    }

    /// The next frozen situation and its competency, or nil when the check is complete.
    func practiceStep() -> (attempt: PracticeAttempt, session: SimulationSession, competency: String)? {
        guard let attempt = latestPracticeCheck, let scenarios,
              let session = try? aiState.activePracticeCheckSession(attemptID: attempt.id, library: scenarios) else { return nil }
        let order = IntegratedAIState.practiceOrder(attempt.variantID)
        let index = attempt.observations?.count ?? 0
        guard order.indices.contains(index) else { return nil }
        return (attempt, session, order[index])
    }

    /// Builds the four situations from the current household and home and freezes them with the attempt in one save.
    /// An unfinished check is resumed instead; nothing is re-rolled.
    @discardableResult
    func beginPracticeCheck() async -> Bool {
        guard let household, let content, let scenarios else { return false }
        if let latest = latestPracticeCheck, (latest.observations?.count ?? 0) < 4 { return true }
        let home = self.home, library = scenarios, contentVersion = content.contentVersion
        let variant = PracticeCheckSources.variant(previousAttempts: aiState.practiceAttempts.count)
        let id = "check-\(UUID().uuidString)"
        workInFlight += 1
        defer { workInFlight -= 1 }
        let build = Task.detached(priority: .userInitiated) {
            try PracticeCheckSources.prepare(attemptID: id, variantID: variant, household: household, home: home,
                                             contentVersion: contentVersion, library: library)
        }
        guard let sources = try? await build.value else { lastError = localizer("practice.unavailable"); return false }
        return await updateAIState { state, _ in
            state.sessions.append(contentsOf: sources)
            try state.beginPracticeCheck(id: id, variantID: variant, sessionIDs: sources.map(\.id), library: library)
        }
    }

    /// Records the family's first answer for the current situation before any feedback. Returns the stored observation.
    func submitPracticeAnswer(_ command: SessionCommand) async -> PracticeObservation? {
        guard let step = practiceStep(), let scenarios else { return nil }
        let commit = SessionCommit(id: "answer-\(UUID().uuidString)", actor: "user", baseRevision: step.session.revision, commands: [command])
        var observation: PracticeObservation?
        let saved = await updateAIState { state, _ in
            observation = try state.submitPracticeAction(attemptID: step.attempt.id, competencyID: step.competency, commit: commit, library: scenarios)
        }
        return saved ? observation : nil
    }

    /// Feedback is recorded as revealed (never changing the answer) before the screen shows it.
    @discardableResult
    func revealPracticeFeedback(attemptID: String, actionID: String) async -> Bool {
        await updateAIState { state, _ in
            _ = try state.revealPracticeFeedback(attemptID: attemptID, actionID: actionID)
        }
    }

    func closeAdaptive() { adaptive = nil; directorFallbackNote = nil }

    // MARK: - Plans

    /// Builds a plan for the selected scenarios by running each deterministically, then saves it in the vault.
    /// Returns only this request's committed document. A retained older plan is never a successful result.
    @discardableResult
    func generatePlan(scenarioIDs: [String], includePrivateNotes: Bool, selection explicitSelection: FamilyCardSelection? = nil) async -> PlanDocument? {
        let selection = explicitSelection ?? cardSelection
        guard let household, let content, let scenarios, let engine, let key = planKey else { return nil }
        let ticket = planGate.begin(for: key)
        let locale = self.locale
        let localizer = content.localizer(for: locale)
        let resources = regionalResources?.resources(for: household.regionID) ?? content.resources(forRegion: household.regionID)
        let places = savedPlaces
        let home = self.home
        // A matching real exercise retains its recorded seed/origin/starts/choices. Hypothetical
        // comparisons are never adopted as household facts or silently exported as actual readiness.
        let practicedInput = rehearsal?.result.input
        let inputs = Array(Set(scenarioIDs)).sorted().compactMap { id -> RehearsalInput? in
            guard let s = scenarios.scenarios.first(where: { $0.id == id }) else { return nil }
            if let practicedInput, practicedInput.scenarioID == id, practicedInput.household == household,
               practicedInput.home == home, practicedInput.contentVersion == content.contentVersion,
               practicedInput.scenarioVersion == s.version, practicedInput.interventions.isEmpty {
                return practicedInput
            }
            return RehearsalInput(household: household, home: home, scenarioID: id, scenarioVersion: s.version,
                                  contentVersion: content.contentVersion, seed: 1)
        }
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            let doc = try await Task.detached(priority: .userInitiated) {
                let results = try inputs.map { try engine.run($0) }
                return PlanBuilder.build(household: household, home: home, savedPlaces: places, results: results, localizer: localizer,
                                         resources: resources, contentVersion: content.contentVersion, generatedAt: Date(),
                                         options: .init(includePrivateNotes: includePrivateNotes, familyCardSelection: selection, timeZone: .current))
            }.value
            // Language or household changed while building: drop this plan rather than save a mismatched one.
            guard planGate.shouldApply(ticket, current: planKey) else { return nil }
            guard await save(snapshot: PrivateSnapshot(household: household, home: home, savedPlan: doc, savedPlaces: places)),
                  planGate.shouldApply(ticket, current: planKey) else { return nil }
            savedPlan = doc
            return doc
        } catch {
            guard planGate.shouldApply(ticket, current: planKey) else { return nil }
            lastError = String(describing: error)
            return nil
        }
    }

    /// Snapshot preparation can await Apple services; refuse publication after any relevant input changes.
    func documentIsCurrent(_ document: PlanDocument) -> Bool {
        guard let household, let content, document.locale == locale else { return false }
        return !document.isStale(household: household, home: home, contentVersion: content.contentVersion, savedPlaces: savedPlaces)
    }

    var planIsStale: Bool {
        guard let savedPlan, let household, let content else { return false }
        return savedPlan.isStale(household: household, home: home, contentVersion: content.contentVersion, savedPlaces: savedPlaces) || savedPlan.locale != locale
    }

    private func invalidateDerived() {
        // Routes, rehearsal results, and comparisons are tied to revisions; drop them so nothing stale is shown.
        rehearsal = nil
        comparison = nil
        nextStepResults = nil
        runGate.invalidate()
        nextGate.invalidate()
        planGate.invalidate()
        scorecard = nil
        scoreGate.invalidate()
    }

    // MARK: - Next steps and outage card

    /// Inputs of the last summary. The summary merges six rehearsals and evaluates baseline preparedness three times,
    /// and views read it several times per render; it is recomputed only when an input (or the day) changes.
    private struct NextStepsInputs: Equatable {
        var household: HouseholdProfile; var home: HomeModel?; var savedPlaces: [SavedPlace]; var results: [RehearsalResult]?; var day: Date
    }
    @ObservationIgnored private var nextStepsCache: (inputs: NextStepsInputs, summary: NextStepsSummary)?

    var nextSteps: NextStepsSummary? {
        guard let household else { return nil }
        let now = Date()
        let inputs = NextStepsInputs(household: household, home: home, savedPlaces: savedPlaces, results: nextStepResults,
                                     day: Calendar.current.startOfDay(for: now))
        if let cache = nextStepsCache, cache.inputs == inputs { return cache.summary }
        let summary = NextSteps.summarize(nextStepResults ?? [], household: household, home: home, savedPlaces: savedPlaces, referenceDate: now)
        nextStepsCache = (inputs, summary)
        return summary
    }

    /// Runs every scenario with default choices (off the main actor) unless results for this revision exist.
    func refreshNextSteps() async {
        guard nextStepResults == nil, let household, let content, let scenarios, let engine,
              let key = currentKey else { return }
        let home = self.home
        let ticket = nextGate.begin(for: key)
        let inputs = RehearseTabView.scenarioIDs.compactMap { id -> RehearsalInput? in
            guard let s = scenarios.scenarios.first(where: { $0.id == id }) else { return nil }
            return RehearsalInput(household: household, home: home, scenarioID: id, scenarioVersion: s.version,
                                  contentVersion: content.contentVersion, seed: 1)
        }
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            // The six runs are independent: run them concurrently and keep the planner's scenario order.
            let results = try await withThrowingTaskGroup(of: (Int, RehearsalResult).self) { group in
                for (index, input) in inputs.enumerated() {
                    group.addTask(priority: .userInitiated) { (index, try engine.run(input)) }
                }
                var ordered = [RehearsalResult?](repeating: nil, count: inputs.count)
                for try await (index, result) in group { ordered[index] = result }
                return ordered.compactMap { $0 }
            }
            guard nextGate.shouldApply(ticket, current: currentKey) else { return }
            nextStepResults = results
        } catch {
            guard nextGate.shouldApply(ticket, current: currentKey) else { return }
            lastError = String(describing: error)
        }
    }

    /// "Try this change" from Next steps: the intervention belongs to the step's source scenario, so that scenario is
    /// opened (default choices) before comparing. Returns whether a comparison was produced.
    func tryChange(for step: NextStep) async -> Bool {
        guard let intervention = step.recommendation.tryIntervention else { return false }
        let input = rehearsal?.result.input
        if input?.scenarioID != step.sourceScenarioID || input?.choices.isEmpty == false || input?.variants.isEmpty == false {
            await startRehearsal(scenarioID: step.sourceScenarioID)
        }
        await tryChange(intervention)
        return comparison != nil
    }

    /// A live plan works with saved facts even before geometry or an exercise exists.
    func currentPlan(selection: FamilyCardSelection = FamilyCardSelection(), includePrivateNotes: Bool = false) -> PlanDocument? {
        guard let household, let content else { return nil }
        return PlanBuilder.build(household: household, home: home, savedPlaces: savedPlaces, results: [],
                                 localizer: localizer,
                                 resources: regionalResources?.resources(for: household.regionID) ?? content.resources(forRegion: household.regionID),
                                 contentVersion: content.contentVersion, generatedAt: Date(),
                                 options: .init(includePrivateNotes: includePrivateNotes, familyCardSelection: selection, timeZone: .current))
    }

    /// Family card is universal; device continuity details remain optional supporting content.
    func outageCard(includePrivateNotes: Bool = false, selection: FamilyCardSelection = FamilyCardSelection()) -> PlanDocument? {
        guard var doc = currentPlan(selection: selection, includePrivateNotes: includePrivateNotes) else { return nil }
        doc.pages = doc.pages.filter { $0.id == "family-card" }
        // A card-only preview must not retain hidden indoor/map data for another renderer.
        doc.visualSnapshot = nil
        return doc
    }

    private func invalidatePlans() { planGate.invalidate() }

    private func configureRegionalResources() {
        guard let content else { return }
        guard let regionID = household?.regionID, PublicDataPolicy.isAllowedRegionID(regionID) else {
            regionalResources = nil
            return
        }
        if let regionalResources {
            regionalResources.select(regionID: regionID)
        } else {
            regionalResources = RegionalResourcesStore(content: content, client: publicClient, regionID: regionID)
        }
    }

    // MARK: - Persistence

    func persist() async {
        guard let household else { return }
        _ = await save(snapshot: PrivateSnapshot(household: household, home: home, savedPlan: savedPlan,
                                                  savedPlaces: savedPlaces))
    }

    /// Saves a complete candidate before publishing it to observable state. This keeps failed home/place writes
    /// from presenting a success state while the previous committed snapshot remains intact.
    @discardableResult
    private func save(snapshot: PrivateSnapshot) async -> Bool {
        guard !privateWriteInFlight else {
            lastError = "Another edit is still saving. Your draft was kept; try Save again."
            return false
        }
        privateWriteInFlight = true
        defer { privateWriteInFlight = false }
        var snapshot = snapshot
        if snapshot.aiState == nil { snapshot.aiState = aiState }
        do {
            try await store.save(snapshot)
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// Canonical digest of the saved AI state, used by adapters that must reject a late response.
    var aiStateDigest: String? { PrivateSnapshot.encoded(aiState).map(StableDigest.of) }

    /// Native AI/practice adapters stage the portable reducer here. The digest rejects late
    /// responses; the encrypted write completes before any observing screen sees new evidence.
    @discardableResult
    func updateIntegratedAIState(expectedDigest: String?, _ change: (inout IntegratedAIState) throws -> Void) async -> Bool {
        guard household != nil, aiStateDigest == expectedDigest else {
            lastError = "The recorded evidence changed. Refresh this result before saving."
            return false
        }
        return await updateAIState { state, _ in try change(&state) }
    }

    // MARK: - Private map places

    @discardableResult
    func savePlace(_ place: SavedPlace) async -> Bool {
        guard let household, place.homeID == (home?.id ?? household.stableHomeID), !place.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var candidate = savedPlaces.filter { $0.id != place.id }
        candidate.append(place)
        var candidateHome = home.map { HomeMeetingPlaces.synchronize($0, places: candidate) }
        if candidateHome != home { candidateHome?.bumpRevision() }
        let snapshot = PrivateSnapshot(household: household, home: candidateHome, savedPlan: savedPlan, savedPlaces: candidate)
        guard await save(snapshot: snapshot) else { return false }
        savedPlaces = candidate
        home = candidateHome
        invalidateDerived()
        invalidatePlans()
        return true
    }

    func deletePlace(id: String) async {
        guard let household else { return }
        let candidate = savedPlaces.filter { $0.id != id }
        guard candidate.count != savedPlaces.count else { return }
        var candidateHome = home.map { HomeMeetingPlaces.synchronize($0, places: candidate) }
        if candidateHome != home { candidateHome?.bumpRevision() }
        let snapshot = PrivateSnapshot(household: household, home: candidateHome, savedPlan: savedPlan, savedPlaces: candidate)
        guard await save(snapshot: snapshot) else { return }
        savedPlaces = candidate
        home = candidateHome
        invalidateDerived()
        invalidatePlans()
    }

    /// Delete everything private: vault, derived caches, temporary exports, and the key.
    @discardableResult
    func deleteAllPrivateData() async -> Bool {
        guard !privateWriteInFlight else { lastError = "An edit is still saving. Try again."; return false }
        privateWriteInFlight = true
        defer { privateWriteInFlight = false }
        do {
            try await store.deleteAll()
            LocalReviewReminderScheduler.shared.cancel()
            TemporaryExports.purgeAll()
            household = nil; home = nil; savedPlan = nil; savedPlaces = []; rehearsal = nil; comparison = nil; nextStepResults = nil
            aiState = IntegratedAIState(); adaptive = nil
            cardSelection = FamilyCardSelection()
            runGate.invalidate(); planGate.invalidate(); nextGate.invalidate()
            phase = .onboarding
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }
}
