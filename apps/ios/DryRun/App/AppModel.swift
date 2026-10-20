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
    var locale: String = "en" { didSet { if locale != oldValue { invalidatePlans() } } }
    var savedPlan: PlanDocument?
    /// Opaque versioned portable state is retained even before native AI screens are integrated.
    private(set) var integratedAIState: Data?
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
                return (c, s)
            }.value
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
            integratedAIState = snapshot.integratedAIState
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
        let snapshot = PrivateSnapshot(household: sample, home: candidateHome, savedPlan: nil, savedPlaces: places)
        guard await save(snapshot: snapshot) else { return }
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
        let snapshot = PrivateSnapshot(household: candidateHousehold, home: nil, savedPlan: nil, savedPlaces: [])
        guard await save(snapshot: snapshot) else { return false }
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
        guard await save(snapshot: PrivateSnapshot(household: candidate, home: nil, savedPlan: nil, savedPlaces: [])) else { return false }
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
    }

    // MARK: - Next steps and outage card

    var nextSteps: NextStepsSummary? {
        guard let household else { return nil }
        return NextSteps.summarize(nextStepResults ?? [], household: household, home: home, savedPlaces: savedPlaces)
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
            let results = try await Task.detached(priority: .userInitiated) { try inputs.map { try engine.run($0) } }.value
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
    private func save(snapshot: PrivateSnapshot, preserveIntegratedAIState: Bool = true) async -> Bool {
        guard !privateWriteInFlight else {
            lastError = "Another edit is still saving. Your draft was kept; try Save again."
            return false
        }
        privateWriteInFlight = true
        defer { privateWriteInFlight = false }
        do {
            var candidate = snapshot
            if preserveIntegratedAIState {
                candidate.integratedAIState = household?.id == snapshot.household.id ? integratedAIState : snapshot.integratedAIState
            }
            try await store.save(candidate)
            integratedAIState = candidate.integratedAIState
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// Native AI/practice adapters stage the portable reducer here. The digest rejects late
    /// responses; the encrypted write completes before any observing screen sees new evidence.
    @discardableResult
    func updateIntegratedAIState(expectedDigest: String?, _ change: (inout IntegratedAIState) throws -> Void) async -> Bool {
        guard let household, integratedAIState.map(StableDigest.of) == expectedDigest else {
            lastError = "The recorded evidence changed. Refresh this result before saving."
            return false
        }
        do {
            var candidate = try integratedAIState.map { try DryRunJSON.decoder().decode(IntegratedAIState.self, from: $0) } ?? IntegratedAIState()
            try change(&candidate)
            let data = try DryRunJSON.encoder().encode(candidate)
            return await save(snapshot: PrivateSnapshot(household: household, home: home, savedPlan: savedPlan,
                savedPlaces: savedPlaces, integratedAIState: data), preserveIntegratedAIState: false)
        } catch {
            lastError = String(describing: error)
            return false
        }
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
            integratedAIState = nil; household = nil; home = nil; savedPlan = nil; savedPlaces = []; rehearsal = nil; comparison = nil; nextStepResults = nil
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
