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
    private(set) var integratedAIState: Data?
    /// Distinguishes resets even when example IDs, revisions and addresses repeat.
    private(set) var scopeSessionID = UUID().uuidString
    /// Typed view over the one durable opaque sidecar. Mutations use updateAIState.
    var aiState: IntegratedAIState { (try? integratedStateForRehearsal()) ?? IntegratedAIState() }
    var locale: String = "en" { didSet { if locale != oldValue { invalidatePlans() } } }
    var savedPlan: PlanDocument?
    /// The family's choice of what the card shows, shared by the card view, Plan, Share/Print and saved plans so the
    /// preview always matches what is sent. Only these on/off choices are kept (in UserDefaults), never any content.
    var cardSelection: FamilyCardSelection = FamilyCardSelection() {
        didSet {
            guard cardSelection != oldValue, !suppressCardSelectionPersistence,
                  !(exampleStore != nil && household?.isFictional == true) else { return }
            personalCardSelection = cardSelection
            AppModel.storeCardSelection(cardSelection, preferences: preferences)
        }
    }
    private var personalCardSelection = FamilyCardSelection()
    private var suppressCardSelectionPersistence = false
    private let preferences: UserDefaults
    private static let cardSelectionKey = "familyCardSelection.v1"
    static func storedCardSelection(preferences: UserDefaults = .standard) -> FamilyCardSelection {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestingInMemory"),
              let data = preferences.data(forKey: cardSelectionKey),
              let value = try? JSONDecoder().decode(FamilyCardSelection.self, from: data) else { return FamilyCardSelection() }
        return value
    }
    static func storeCardSelection(_ value: FamilyCardSelection, preferences: UserDefaults = .standard) {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestingInMemory") else { return }
        preferences.set(try? JSONEncoder().encode(value), forKey: cardSelectionKey)
    }
    /// Every scenario run once with default choices, for the Next steps screen. Tied to the household/home revision
    /// like other derived results; completions are applied on read, so marking one done does not re-run anything.
    var nextStepResults: [RehearsalResult]?
    var rehearsal: RehearsalCursor?
    private(set) var rehearsalSessionID: String?
    private(set) var rehearsalReceipt: SessionReceipt?
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
    let exampleStore: PrivateDataStore?
    private(set) var hasPersonalHousehold = false
    /// Shared validated public-resource snapshot used by Help and map planning. Browsing a different county never
    /// changes the household's region or the resources selected for a saved plan.
    var regionalResources: RegionalResourcesStore?
    /// Public-only client (region ID in, public data out). Backed by an atomic known-good cache.
    let publicClient: PublicAPIClient = AppModel.makePublicClient()

    private var runGate = LatestRequestGate()
    private var planGate = LatestRequestGate()
    private var nextGate = LatestRequestGate()
    private var directorGate = LatestRequestGate()
    private var scoreGate = LatestRequestGate()
    /// Versioned draft rubric (content/ai/rubric-v0.json). The numbers are product policy, not safety thresholds.
    private(set) var rubric: RubricDefinition?
    /// Deterministic, local: accepted household facts, confirmed inventory, the reviewed fire stress envelope and
    /// eligible practice. No model output can change it. Recomputed per revision; nil until computed.
    private(set) var scorecard: Scorecard?

    struct Scorecard: Sendable {
        let key: RevisionKey
        let compiledAt: Date
        let card: PreparednessScorecard
        let assessments: [CriterionAssessment]
        /// The reviewed home-fire envelope run against this home; hypothetical, never a household fact.
        let fireStress: StressTestFinding?
    }

    /// The score's inputs: household/home/content plus confirmed inventory and practice attempts.
    var scoreKey: RevisionKey? {
        guard var key = currentKey, let rubric else { return nil }
        let answers = aiState.practiceAttempts.reduce(0) { $0 + ($1.observations?.count ?? $1.answers.count) }
        key.algorithmVersion = "score/\(rubric.version)/inv\(aiState.inventory.revision)/practice\(aiState.practiceAttempts.count)-\(answers)/scope\(scopeSessionID)"
        return key
    }

    /// Computes the scorecard off the main actor unless the current one already matches every input.
    func refreshScorecard(force: Bool = false) async {
        guard let household, let scenarios, let rubric, let key = scoreKey, force || scorecard?.key != key else { return }
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
                let card = try state.compileScorecard(rubric: rubric, assessments: assessments, library: scenarios,
                                                     currentHousehold: household, currentHome: home)
                return Scorecard(key: key, compiledAt: date, card: card, assessments: assessments, fireStress: fire)
            }.value
            guard scoreGate.shouldApply(ticket, current: scoreKey) else { return }
            scorecard = result
        } catch {
            guard scoreGate.shouldApply(ticket, current: scoreKey) else { return }
            lastError = String(describing: error)
        }
    }
    /// Derived host evidence is exported separately from persisted history, avoiding a scoring/save loop.
    var currentHostScorecard: PreparednessScorecard? {
        guard let scorecard, scorecard.key == scoreKey,
              (0..<60).contains(Date().timeIntervalSince(scorecard.compiledAt)) else { return nil }
        return scorecard.card
    }
    private var privateWriteInFlight = false
    private var privateStateGeneration = 0

    /// Identity of the current household/home/content. Results computed for anything else are discarded.
    var currentKey: RevisionKey? {
        guard let household, let content else { return nil }
        return RevisionKey(householdID: household.id, householdRevision: household.revision, homeID: home?.id ?? household.stableHomeID,
                           homeRevision: home?.revision ?? 0, contentVersion: content.contentVersion, algorithmVersion: "app/1")
    }

    init(store: PrivateDataStore, exampleStore: PrivateDataStore? = nil, preferences: UserDefaults = .standard) {
        self.store = store
        self.exampleStore = exampleStore
        self.preferences = preferences
        let selection = AppModel.storedCardSelection(preferences: preferences)
        cardSelection = selection
        personalCardSelection = selection
        demoAlertName = DemoLaunch.current.alert ?? (DemoLaunch.current.usesInMemoryStore ? nil : preferences.string(forKey: "demoAlert"))
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

    // MARK: - Shopping list

    /// The reviewed planning price table (content/prices), loaded once.
    @ObservationIgnored private var loadedPriceTable: ShoppingList.PriceTable??
    var priceTable: ShoppingList.PriceTable? {
        if let loaded = loadedPriceTable { return loaded }
        let table = (try? ContentLocator.contentRoot()).flatMap { try? Data(contentsOf: $0.appendingPathComponent("prices/tarrant-v1.json")) }
            .flatMap { try? JSONDecoder().decode(ShoppingList.PriceTable.self, from: $0) }
        loadedPriceTable = .some(table)
        return table
    }

    /// Core's ranked list for this household and its confirmed inventory (empty when it cannot be computed).
    var shoppingItems: [ShoppingList.Item] {
        guard let household, let priceTable else { return [] }
        return (try? ShoppingList.build(household: household, inventory: aiState.inventory, prices: priceTable, at: Date())) ?? []
    }

    func shoppingReason(_ item: ShoppingList.Item) -> String {
        let step = AlertResponse.Step(key: item.reasonKey, values: item.values, sourceIDs: item.sourceIDs)
        return alertStepText(step, prefix: "shop.reason.")
    }

    /// Records the purchase as confirmed inventory through the same path as supply intake.
    func markBought(_ item: ShoppingList.Item) async -> Bool {
        guard household != nil else { return false }
        let date = Date()
        return await updateAIState { state, household in
            try state.recordPurchase(item, household: &household, baseHouseholdRevision: household.revision, at: date) { _, _ in }
        }
    }

    // MARK: - Weather alerts (NWS, Tarrant County)

    /// The alert Prepare leads with: a chosen demo sample, else the most urgent live NWS alert. Nil when none.
    private(set) var weatherAlert: WeatherAlert?
    /// Settings → "Show a sample alert (demo)", or -demoAlert. Persisted per device so the filmed demo survives relaunch.
    /// In-memory (UI test / demo launch) runs ignore a sample chosen earlier in Settings unless -demoAlert asks for one.
    var demoAlertName: String? {
        didSet {
            if DemoLaunch.current.alert == nil { preferences.set(demoAlertName, forKey: "demoAlert") }
            Task { await refreshWeatherAlert() }
        }
    }

    func refreshWeatherAlert() async {
        if let name = demoAlertName, let sample = WeatherAlertService.sample(name) { weatherAlert = sample; return }
        // UI tests stay independent of the weather.
        guard !DemoLaunch.current.inMemory else { weatherAlert = nil; return }
        guard let live = await WeatherAlertService.fetchActive() else { return }
        if demoAlertName == nil { weatherAlert = WeatherAlerts.leading(live, now: Date()) }
    }

    /// Core's three immediate steps for the current alert and household, or none when it maps to no rehearsal.
    var alertSteps: [AlertResponse.Step] {
        guard let weatherAlert, let household, let scenario = WeatherAlerts.scenarioID(for: weatherAlert.event) else { return [] }
        return AlertResponse.steps(scenarioID: scenario, household: household, home: home)
    }

    func alertStepText(_ step: AlertResponse.Step, prefix: String = "alert.step.") -> String {
        let values = step.values.mapValues { ref -> String in
            switch ref {
            case .person(let id): household?.people.first { $0.id == id }?.localizedLabel(localizer) ?? ""
            case .equipment(let id): household?.equipment.first { $0.id == id }?.localizedLabel(localizer) ?? ""
            case .space(let id): home.map { HomeScenePresentation.roomLabel(id, in: $0) } ?? ""
            }
        }
        return localizer(prefix + step.key, values)
    }

    /// Whether Beacon's gateway answered its /health probe at launch (nil: not configured or not yet known).
    private(set) var beaconReachable: Bool?

    func start() async {
        capabilities.refresh()
        if let client = DirectorGatewayClient.current {
            Task { [weak self] in
                let reachable = await client.ping()
                self?.beaconReachable = reachable
            }
        }
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
        let demoHome = d.homeID.flatMap { id in (SampleHomes.all + [SampleHomes.scannedRanch]).first { $0.id == id } }
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
        guard !privateWriteInFlight else { return }
        let generation = privateStateGeneration
        let scope = scopeSessionID
        let result = await store.load()
        guard !privateWriteInFlight, privateStateGeneration == generation, scopeSessionID == scope else { return }
        switch result {
        case .empty:
            household = nil; home = nil; savedPlan = nil; savedPlaces = []; integratedAIState = nil
            scopeSessionID = UUID().uuidString
            hasPersonalHousehold = false
            invalidateDerived()
            adaptive = nil
            phase = .onboarding
        case .loaded(let snapshot):
            var restored = snapshot.household
            if restored.homeID == nil, let existingHome = snapshot.home { restored.homeID = existingHome.id }
            household = restored
            hasPersonalHousehold = !restored.isFictional
            if !restored.isFictional { cardSelection = personalCardSelection }
            savedPlaces = HomeMeetingPlaces.placesIncludingLocalMeetup(home: snapshot.home, places: snapshot.savedPlaces, recordedAt: restored.updatedAt)
            home = snapshot.home.map { HomeMeetingPlaces.synchronize($0, places: savedPlaces) }
            savedPlan = snapshot.savedPlan
            integratedAIState = snapshot.integratedAIState
            scopeSessionID = UUID().uuidString
            invalidateDerived()
            restorePersistedRehearsal()
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

    @discardableResult
    func restorePersonalHousehold() async -> Bool {
        guard !privateWriteInFlight else { return false }
        await loadPrivateData()
        return phase == .ready && household?.isFictional == false
    }

    // MARK: - Household

    func useSampleHousehold(_ sample: HouseholdProfile, demoHome: HomeModel? = nil) async {
        guard sample.isFictional, demoHome?.isFictional != false else {
            lastError = "Choose an example home for an example household. Your saved home was kept."
            return
        }
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
        if sample.id == "hh-lake", sample.privateLocation == nil, demoHome == nil {
            // Demo-only Tarrant County origin for the shelter and cooling-center map: a public downtown Fort Worth point,
            // labelled fictional. No real household address is implied.
            sample.privateLocation = PrivateLocation(addressLine: "Downtown Fort Worth, TX (fictional)", latitude: 32.7555, longitude: -97.3308,
                                                     city: "Fort Worth", administrativeArea: "TX", countryCode: "US")
        }
        let places = HomeMeetingPlaces.placesIncludingLocalMeetup(home: sampleHome, places: extraPlaces, recordedAt: sample.updatedAt)
        let candidateHome = HomeMeetingPlaces.synchronize(sampleHome, places: places)
        let snapshot = PrivateSnapshot(household: sample, home: candidateHome, savedPlan: nil, savedPlaces: places)
        guard await save(snapshot: snapshot, preservingIntegratedState: false) else { return }
        household = sample
        if exampleStore != nil { cardSelection = FamilyCardSelection() }
        home = candidateHome
        savedPlaces = places
        configureRegionalResources()
        invalidateDerived()
        locale = sample.preferredLocale
        phase = .ready
    }

    /// Settings → Try a sample family while the family's own scanned or drawn home is loaded: swap only the people and
    /// records, keep the home (and its places). Starting rooms are cleared because the sample's room IDs do not exist here.
    func useSampleFamilyKeepingHome(_ sample: HouseholdProfile) async {
        // Retained call compatibility; personal geometry is never labelled synthetic.
        await useSampleHousehold(sample)
    }

    /// Creates a personal household without fabricating geometry. The candidate is written before it becomes
    /// observable so an onboarding save failure leaves the user on the editable form rather than showing a false
    /// ready state.
    @discardableResult
    func useSampleHouseholdIfNoHome(_ candidateHousehold: HouseholdProfile) async -> Bool {
        guard !hasPersonalHousehold || household?.isFictional == false else {
            lastError = "Restore your saved household before editing it."
            return false
        }
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
        guard await save(snapshot: snapshot, preservingIntegratedState: false) else { return false }
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
        guard !privateWriteInFlight, let previous = household else { return false }
        let scope = scopeSessionID, key = currentKey
        guard var state = try? integratedStateForRehearsal() else { return false }
        var h = previous
        do { try transaction(&state, &h) } catch { lastError = String(describing: error); return false }
        let householdChanged = h != previous
        guard await save(snapshot: PrivateSnapshot(household: h, home: home, savedPlan: savedPlan, savedPlaces: savedPlaces, aiState: state)) else { return false }
        guard scopeSessionID == scope, currentKey == key else { return false }
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

    /// Records the family's decision on one reviewed photo concern in the atomic save. Only a confirmed concern links
    /// to an existing preparation (it never completes it or adds points); repeats of the same evidence are refused.
    @discardableResult
    func reviewConcern(_ proposal: HomeConcernProposal, decision: ConcernDecision, manifest: RoomImageManifest) async -> Bool {
        guard let home, let rubric, let scenarios else { return false }
        return await updateAIState { state, household in
            try state.reviewConcern(proposal, decision: decision, manifest: manifest, home: home, household: household,
                                    rubric: rubric, library: scenarios, at: Date())
        }
    }

    /// Confirmed concerns that still match the current home, as links to their preparation.
    var concernTasks: [ConcernTaskLink] { home.map { aiState.concerns.reviewed.isEmpty ? [] : aiState.concernTasks(currentHome: $0) } ?? [] }

    /// Offline nearby-resource plans for the open preparation tasks (reviewed category table in Core).
    var resourcePlans: [ResourceSearchPlan] {
        guard let household, let rubric else { return [] }
        let tasks = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: Date())
        return ResourceSuggestionPlanner.plans(tasks: tasks, gaps: inventoryGaps, transport: HouseholdContextSnapshot(household).transport,
                                               limitedBudget: household.supplies.limitedBudget)
    }

    // MARK: Gemini resource planning (optional, fictional households with the development gateway)

    /// Opt-in for this app session: Gemini plans the nearby searches for open tasks. Off: the offline plans are used.
    var cloudResourcesEnabled = false { didSet { resourceRefresh.setCloudOptIn(cloudResourcesEnabled && cloudDirectorAvailable) } }
    private var resourceRefresh = ResourceStrategyRefresh()
    /// Whether the plans in use came from Gemini (accepted by Core for the current inputs).
    private(set) var resourcePlansFromGemini = false
    private(set) var resourcePlanNote: String?

    /// Plans the map uses: Gemini's, only when accepted by Core for exactly the current inputs; otherwise offline plans.
    var activeResourcePlans: [ResourceSearchPlan] {
        guard cloudResourcesEnabled, let key = currentResourceKey, resourceRefresh.acceptedKey == key, !resourceRefresh.acceptedPlans.isEmpty
        else { return resourcePlans }
        return resourceRefresh.acceptedPlans
    }

    private var currentResourceKey: ResourceStrategyKey? {
        guard let household, let rubric else { return nil }
        let tasks = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: Date())
        guard var key = try? ResourceStrategyBridge.key(household: household, home: home, tasks: tasks, gaps: inventoryGaps) else { return nil }
        key.normalizedInputDigest = (key.normalizedInputDigest ?? "") + "|scope:" + scopeSessionID
            + "|state:" + (integratedAIState.map(StableDigest.of) ?? "empty") + "|locale:" + locale
        return key
    }

    /// Asks Gemini once per changed set of relevant inputs. Failure keeps the last accepted plans or the offline ones.
    func refreshCloudResourcePlans() async {
        resourcePlanNote = nil
        guard cloudResourcesEnabled, cloudDirectorAvailable, let client = DirectorGatewayClient.current,
              let household, household.isFictional, let rubric, let key = currentResourceKey else {
            resourcePlansFromGemini = false
            return
        }
        resourceRefresh.setCloudOptIn(true)
        guard let ticket = resourceRefresh.begin(key) else {
            resourcePlansFromGemini = resourceRefresh.acceptedKey == key && !resourceRefresh.acceptedPlans.isEmpty
            return
        }
        let tasks = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: Date())
        let scope = scopeSessionID
        await refreshScorecard(force: true)
        guard !Task.isCancelled, scopeSessionID == scope, currentResourceKey == key else {
            resourceRefresh.failed(ticket: ticket); return
        }
        let request: ResourceStrategyBridge.Request
        do {
            request = try ResourceStrategyBridge.authorizedRequest(requestID: "resources-\(UUID().uuidString)", household: household,
                home: home, tasks: tasks, gaps: inventoryGaps, state: aiState, places: savedPlaces,
                scopeSessionID: scope, locale: locale, currentScorecard: currentHostScorecard)
        } catch { resourceRefresh.failed(ticket: ticket); return }
        workInFlight += 1
        defer { workInFlight -= 1 }
        let response = await client.planResources(request)
        guard !Task.isCancelled, scopeSessionID == scope, currentResourceKey == key else {
            resourceRefresh.failed(ticket: ticket); return
        }
        switch response {
        case .success(let response):
            do {
                guard response.status == "completed", let proposed = response.proposal?.searchPlans else { throw SessionError.invalidCommand }
                let plans = ResourceStrategyBridge.reviewed(proposed, tasks: tasks, limitedBudget: household.supplies.limitedBudget)
                guard !plans.isEmpty else { throw SessionError.invalidCommand }
                try resourceRefresh.accept(plans, ticket: ticket)
                resourcePlansFromGemini = true
            } catch {
                resourceRefresh.failed(ticket: ticket)
                resourcePlansFromGemini = false
                resourcePlanNote = localizer("map.geminiRejected")
            }
        case .failure(let error):
            resourceRefresh.failed(ticket: ticket)
            resourcePlansFromGemini = false
            resourcePlanNote = localizer("map.geminiUnavailable")
        }
    }

    /// The open task a suggestion serves, by ID, for "Back to the task".
    func preparationTitle(taskID: String) -> String? {
        guard let summary = nextSteps, let step = (summary.toDo + summary.recorded).first(where: { $0.id == taskID }) else { return nil }
        let r = step.recommendation
        return localizer(r.titleKey, r.localizedTemplateValues(household: household, localizer: localizer))
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
        household = candidate
        home = nil
        savedPlaces = []
        savedPlan = nil
        configureRegionalResources()
        invalidateDerived()
        return true
    }

    /// A room editor can remain open while another capture or edit commits. Its
    /// original revision must still match before a whole-home draft is saved.
    @discardableResult
    func updateHome(_ newHome: HomeModel, baseRevision: Int?, scopeSessionID expectedScope: String) async -> Bool {
        guard scopeSessionID == expectedScope else {
            lastError = "The selected household changed. Reopen its home before saving."
            return false
        }
        return await updateHome(newHome, baseRevision: baseRevision)
    }

    @discardableResult
    func updateHome(_ newHome: HomeModel, baseRevision: Int?) async -> Bool {
        guard home?.revision == baseRevision else {
            lastError = "This home changed while you were editing. Your draft was kept; reopen the latest home before saving."
            return false
        }
        return await updateHome(newHome)
    }

    @discardableResult
    func updateHome(_ newHome: HomeModel) async -> Bool {
        await updateHome(newHome, expectedRevision: home?.revision)
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
        // Dwelling type already comes from the saved household. Filling that
        // metadata into an older home is not a new physical route condition.
        var previousGeometry = home
        previousGeometry?.dwellingType = household.housing.homeType
        if HomeGeometryEditor.requiresNewEscapeCheck(previous: previousGeometry, updated: h) {
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
        if recordsHomeHistory, let previous = home, previous.id == h.id {
            homeHistories[h.id, default: HomeEditHistory(homeID: h.id)].recordSave(replacing: previous)
        }
        self.household = candidateHousehold
        self.home = h
        self.savedPlaces = candidatePlaces
        invalidateDerived()
        return true
    }

    /// Undo/redo that survive Save: the last 20 saved versions per home, for this app session.
    private(set) var homeHistories: [String: HomeEditHistory] = [:]
    @ObservationIgnored private var recordsHomeHistory = true
    var canUndoHomeSave: Bool { home.flatMap { homeHistories[$0.id]?.canUndo } ?? false }
    var canRedoHomeSave: Bool { home.flatMap { homeHistories[$0.id]?.canRedo } ?? false }

    /// Saves the previous version again (a new revision); the replaced one can be redone.
    @discardableResult
    func undoHomeSave() async -> Bool { await stepHomeHistory { history, current in history.undo(from: current) } }
    @discardableResult
    func redoHomeSave() async -> Bool { await stepHomeHistory { history, current in history.redo(from: current) } }

    private func stepHomeHistory(_ step: (inout HomeEditHistory, HomeModel) -> HomeModel?) async -> Bool {
        guard let current = home, var history = homeHistories[current.id], let target = step(&history, current) else { return false }
        recordsHomeHistory = false
        defer { recordsHomeHistory = true }
        guard await updateHome(target, expectedRevision: current.revision) else { return false }
        homeHistories[current.id] = history
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

    func startRehearsal(scenarioID: String, variants: [String] = [], restart: Bool = false) async {
        guard !privateWriteInFlight, let household, let content, let scenarios, let engine, let key = currentKey,
              let scenario = scenarios.scenarios.first(where: { $0.id == scenarioID }) else { return }
        let input = RehearsalInput(household: household, home: home, scenarioID: scenarioID,
                                   scenarioVersion: scenario.version, contentVersion: content.contentVersion,
                                   seed: 1, variants: variants)
        let scope = scopeSessionID, previousSession = rehearsalSessionID, previousData = integratedAIState
        let ticket = runGate.begin(for: key)
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            var state = try integratedStateForRehearsal()
            let existing = restart ? nil : state.sessions.last { $0.id.hasPrefix(AuthoredRehearsalBridge.sessionPrefix) && $0.initial == input }
            let session = try existing ?? AuthoredRehearsalBridge.initialize(
                id: AuthoredRehearsalBridge.sessionPrefix + UUID().uuidString, input: input, library: scenarios)
            let result = try await Task.detached(priority: .userInitiated) {
                try AuthoredRehearsalBridge.projection(session, engine: engine, library: scenarios)
            }.value
            guard runGate.shouldApply(ticket, current: currentKey), scopeSessionID == scope else { return }
            if existing == nil { state.sessions.append(session) }
            guard await persistRehearsal(state, key: key, scope: scope, previousSession: previousSession, previousData: previousData),
                  runGate.shouldApply(ticket, current: currentKey) else { return }
            let cursor = resumedRehearsalCursor(result)
            rehearsalSessionID = session.id
            rehearsalReceipt = try session.query(library: scenarios)
            rehearsal = cursor
            comparison = nil
        } catch {
            guard runGate.shouldApply(ticket, current: currentKey), scopeSessionID == scope else { return }
            lastError = "Practice could not be saved. Your previous practice is unchanged. Try again."
        }
    }

    /// Commit through the domain session and durable sidecar before publishing any answer or feedback.
    func choose(option: String, at decisionID: String) async {
        guard !privateWriteInFlight, let engine, let scenarios, let key = currentKey, let id = rehearsalSessionID,
              let previousCursor = rehearsal, previousCursor.pendingDecision?.id == decisionID else { return }
        let scope = scopeSessionID, previousData = integratedAIState
        let ticket = runGate.begin(for: key)
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            var state = try integratedStateForRehearsal()
            guard let index = state.sessions.firstIndex(where: { $0.id == id }),
                  matchesCurrentRehearsal(state.sessions[index]) else { throw SessionError.stale }
            var session = state.sessions[index]
            let receipt = try AuthoredRehearsalBridge.choose(option, at: decisionID, in: &session, library: scenarios)
            let accepted = session
            let result = try await Task.detached(priority: .userInitiated) {
                try AuthoredRehearsalBridge.projection(accepted, engine: engine, library: scenarios)
            }.value
            guard runGate.shouldApply(ticket, current: currentKey), scopeSessionID == scope,
                  rehearsalSessionID == id else { return }
            state.sessions[index] = session
            guard await persistRehearsal(state, key: key, scope: scope, previousSession: id, previousData: previousData),
                  runGate.shouldApply(ticket, current: currentKey) else { return }
            var cursor = previousCursor
            cursor.replace(result: result)
            if let boundary = result.events.firstIndex(where: { $0.id == "evt.\(decisionID)" }) {
                while cursor.revealed <= boundary {
                    let before = cursor.revealed
                    cursor.advance()
                    if cursor.revealed == before { break }
                }
            }
            rehearsalReceipt = receipt
            rehearsal = cursor
        } catch {
            guard runGate.shouldApply(ticket, current: currentKey), scopeSessionID == scope, rehearsalSessionID == id else { return }
            lastError = "Your choice was not saved. Try again to continue practice."
        }
    }

    private func integratedStateForRehearsal() throws -> IntegratedAIState {
        guard let integratedAIState else { return IntegratedAIState() }
        return try DryRunJSON.decoder().decode(IntegratedAIState.self, from: integratedAIState)
    }

    private func resumedRehearsalCursor(_ result: RehearsalResult) -> RehearsalCursor {
        var cursor = RehearsalCursor(result: result)
        let lastAccepted = result.events.lastIndex { event in
            result.input.choices.keys.contains { event.id == "evt.\($0)" }
        }
        if let lastAccepted {
            while cursor.revealed <= lastAccepted {
                let before = cursor.revealed
                cursor.advance()
                if cursor.revealed == before { break }
            }
        }
        return cursor
    }

    private func matchesCurrentRehearsal(_ session: SimulationSession) -> Bool {
        session.id.hasPrefix(AuthoredRehearsalBridge.sessionPrefix) && session.initial.household == household &&
            session.initial.home == home && session.initial.contentVersion == content?.contentVersion &&
            scenarios?.scenario(session.initial.scenarioID)?.version == session.initial.scenarioVersion
    }

    private func persistRehearsal(_ state: IntegratedAIState, key: RevisionKey, scope: String,
                                  previousSession: String?, previousData: Data?) async -> Bool {
        guard currentKey == key, scopeSessionID == scope, rehearsalSessionID == previousSession, integratedAIState == previousData,
              let household else { return false }
        guard let data = try? DryRunJSON.encoder().encode(state) else { return false }
        let snapshot = PrivateSnapshot(household: household, home: home, savedPlan: savedPlan,
            savedPlaces: savedPlaces, integratedAIState: data)
        guard await save(snapshot: snapshot), currentKey == key, scopeSessionID == scope,
              rehearsalSessionID == previousSession else { return false }
        return true
    }

    /// Called after canonical private data and content have loaded. Never resumes a
    /// session with different family facts, home geometry, revisions or content.
    func restorePersistedRehearsal() {
        guard let engine, let scenarios else { return }
        do {
            let state = try integratedStateForRehearsal()
            guard let session = state.sessions.last(where: { matchesCurrentRehearsal($0) }) else {
                rehearsalSessionID = nil; rehearsalReceipt = nil
                rehearsal = nil
                return
            }
            let result = try AuthoredRehearsalBridge.projection(session, engine: engine, library: scenarios)
            let cursor = resumedRehearsalCursor(result)
            rehearsalSessionID = session.id
            rehearsalReceipt = try session.query(library: scenarios)
            rehearsal = cursor
        } catch {
            rehearsalSessionID = nil; rehearsalReceipt = nil
            rehearsal = nil
            // Preserve the opaque sidecar for recovery; do not replace unreadable saved state.
        }
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

    /// Who proposed a director turn. A gateway turn is labelled by the provider the gateway reports as having served
    /// it (`servedBy`); `beacon` is a gateway turn whose serving provider was not reported. Locale keys:
    /// adaptive.director.<rawValue>.
    enum DirectorSource: String, Sendable {
        case local, codex, gemini, groq, beacon
        init(servedBy: String?) {
            switch servedBy {
            case "codex": self = .codex
            case "gemini": self = .gemini
            case "groq": self = .groq
            default: self = .beacon
            }
        }
        /// A gateway (model) turn rather than this phone's local director.
        var isRemote: Bool { self != .local }
    }

    struct AdaptiveExercise: Sendable {
        var session: SimulationSession
        var receipt: SessionReceipt
        /// The receipt before the newest commit, so the scene can say what this turn changed.
        var previous: SessionReceipt?
        /// Who proposed the newest director turn, and its unverified narration (gateway turns only).
        var lastDirector: DirectorSource?
        var narration: String?
        /// Household/home/content revision the session's frozen snapshot was taken from.
        let sourceKey: RevisionKey
    }

    /// Exercises kept for resume/history; older finished ones are dropped first.
    static let retainedSessions = 8

    /// Opens the newest unfinished exercise of this scenario taken from the current household/home revision, or a new one.
    func openAdaptive(scenarioID: String, restart: Bool = false) async {
        guard !privateWriteInFlight, let household, let content, let scenarios, let key = currentKey,
              let scenario = scenarios.scenario(scenarioID) else { return }
        let scope = scopeSessionID, originalData = integratedAIState
        if !restart, adaptive?.session.initial.scenarioID == scenarioID, adaptive?.sourceKey == key { return }
        cancelDirectorTurn()
        let home = self.home
        if !restart, let resumable = aiState.sessions.last(where: { s in
            s.mechanicsVersion != nil && s.initial.scenarioID == scenarioID && s.initial.household == household && s.initial.home == home
                && s.initial.contentVersion == content.contentVersion && s.initial.scenarioVersion == scenario.version
        }) {
            let library = scenarios
            let replay = Task.detached(priority: .userInitiated) { try resumable.query(library: library) }
            if let receipt = try? await replay.value, !receipt.finished, currentKey == key,
               scopeSessionID == scope, integratedAIState == originalData {
                adaptive = AdaptiveExercise(session: resumable, receipt: receipt, previous: nil, lastDirector: nil, narration: nil, sourceKey: key)
                return
            }
        }
        let input = RehearsalInput(household: household, home: home, scenarioID: scenarioID, scenarioVersion: scenario.version,
                                   contentVersion: content.contentVersion, seed: 1)
        let library = scenarios
        workInFlight += 1
        var opened = false
        do {
            let (session, receipt) = try await Task.detached(priority: .userInitiated) {
                let session = try SimulationSession.initialize(id: "exercise-\(UUID().uuidString)", initial: input, library: library)
                return (session, try session.query(library: library))
            }.value
            if currentKey == key, scopeSessionID == scope, integratedAIState == originalData {
                var state = try integratedStateForRehearsal()
                state.sessions.append(session)
                if await save(snapshot: PrivateSnapshot(household: household, home: home, savedPlan: savedPlan,
                    savedPlaces: savedPlaces, aiState: state)), currentKey == key, scopeSessionID == scope {
                    adaptive = AdaptiveExercise(session: session, receipt: receipt, previous: nil, lastDirector: nil, narration: nil, sourceKey: key)
                    opened = true
                }
            }
        } catch {
            lastError = String(describing: error)
        }
        // The first director turn runs outside the opening work, so End stays available while Beacon answers.
        workInFlight -= 1
        if opened { await advanceAdaptive() }
    }

    /// The family's action. Validated by the Core reducer; an infeasible action is reported, never mapped to a default.
    @discardableResult
    func submitAdaptive(_ commands: [SessionCommand]) async -> Bool {
        guard let exercise = adaptive, !exercise.receipt.finished else { return false }
        let commit = SessionCommit(id: "user-\(UUID().uuidString)", actor: "user", baseRevision: exercise.session.revision, commands: commands)
        guard let scenarios else { return false }
        // The family's action (End included) always wins over a director turn still in flight.
        cancelDirectorTurn()
        return await commitAdaptive(director: nil, narration: nil) { session in try session.commit(commit, library: scenarios) }
    }

    // MARK: - Gemini preparation (fictional households, development gateway)

    enum PreparationAIState: Equatable {
        case working
        case ready(PreparationFeatureBridge.Personalization)
        case unavailable(String)
    }
    /// Bound to the household/home revisions and confirmed inventory it was computed from; any edit retires it.
    struct PreparationAIKey: Equatable {
        var revision: RevisionKey
        var inventoryRevision: Int
        var scopeSessionID: String
        var stateFingerprint: String
        var locale: String
    }
    private(set) var preparationAI: (key: PreparationAIKey, state: PreparationAIState)?

    private var preparationAIKey: PreparationAIKey? {
        currentKey.map { PreparationAIKey(revision: $0, inventoryRevision: aiState.inventory.revision,
            scopeSessionID: scopeSessionID, stateFingerprint: integratedAIState.map(StableDigest.of) ?? "empty", locale: locale) }
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

    /// The configured server provider chooses, orders and explains preparations. Core accepts the result
    /// only while the exact authorized inputs remain current.
    func personalizePreparation() async {
        guard preparationAIAvailable, let client = DirectorGatewayClient.current, let household, let rubric,
              let key = preparationAIKey, nextStepResults != nil, preparationAIState != .working else { return }
        preparationAI = (key, .working)
        defer {
            // A cancelled appearance task must leave these inputs eligible for a fresh request.
            if preparationAI?.key == key, preparationAI?.state == .working { preparationAI = nil }
        }
        await refreshScorecard(force: true)
        guard !Task.isCancelled, preparationAIKey == key, preparationAIState == .working else { return }
        var request: PreparationFeatureBridge.Request
        do {
            request = try PreparationFeatureBridge.request(requestID: "prep-\(UUID().uuidString)", household: household, home: home,
                                                           inventory: aiState.inventory, rubric: rubric, state: aiState,
                                                           places: savedPlaces, scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentHostScorecard)
            // The server selects only among the explicitly authorized providers.
            request.providerConsent = ["codex", "gemini", "groq"]
        } catch {
            preparationAI = (key, .unavailable("context"))
            return
        }
        preparationAI = (key, .working)
        preparationAIIsReplay = false
        preparationAIIsSaved = false
        workInFlight += 1
        let outcome = await client.preparation(request, householdID: household.id)
        workInFlight -= 1
        guard !Task.isCancelled, preparationAIKey == key, let summary = nextSteps else { return }
        switch outcome {
        case .completed(let output, let revision, let replay) where revision == household.revision:
            preparationAIIsReplay = replay
            if !replay { Self.saveBeaconAnswer(output, for: preparationCacheKey, preferences: preferences) }
            preparationAI = (key, .ready(PreparationFeatureBridge.accept(output, summary: summary, household: household)))
        case .completed:
            preparationAI = (key, .unavailable("stale"))
        case .unavailable(let reason):
            preparationAI = (key, .unavailable(reason))
        }
    }

    /// The shown answer is a recorded Beacon answer (gateway or provider unavailable), labelled in development builds.
    private(set) var preparationAIIsReplay = false
    /// Beacon tailors the top of Prepare by itself once per input state; "Use the app's order" opts out until it changes.
    private var preparationAIDeclined: PreparationAIKey?

    /// Called when Prepare appears or its inputs change: runs Beacon once for these inputs unless the family declined.
    /// A live answer already given for exactly these inputs is shown at once instead of asking again.
    func autoPersonalizePreparation() async {
        guard preparationAIAvailable, nextStepResults != nil, preparationAIState == nil,
              let key = preparationAIKey, preparationAIDeclined != key else { return }
        if let saved = Self.savedBeaconAnswer(for: preparationCacheKey, preferences: preferences), let household, let summary = nextSteps {
            preparationAIIsReplay = false
            preparationAIIsSaved = true
            preparationAI = (key, .ready(PreparationFeatureBridge.accept(saved, summary: summary, household: household)))
            return
        }
        preparationAIIsSaved = false
        await personalizePreparation()
    }

    /// Changes whenever Beacon's inputs change, so Prepare can ask again for the new state.
    var preparationAITrigger: String { preparationAIKey.map { String(describing: $0) } ?? "" }

    /// The shown answer came from an earlier live Beacon call for identical inputs (labelled in development builds).
    private(set) var preparationAIIsSaved = false

    /// Fictional sample households only (the only ones Beacon serves): household, home, inventory revisions and language.
    private var preparationCacheKey: String {
        guard let household, household.isFictional else { return "" }
        return "\(scopeSessionID)|\(household.id)|\(household.revision)|\(home?.id ?? "-")|\(home?.revision ?? 0)|\(aiState.inventory.revision)|\(locale)|\(integratedAIState.map(StableDigest.of) ?? "empty")"
    }

    private static let beaconAnswersKey = "beaconPreparationAnswers"

    private static func saveBeaconAnswer(_ output: PreparationFeatureBridge.Output, for key: String, preferences: UserDefaults) {
        guard !key.isEmpty, let data = try? JSONEncoder().encode(output) else { return }
        var all = preferences.dictionary(forKey: beaconAnswersKey) as? [String: Data] ?? [:]
        all[key] = data
        if all.count > 12 { all = Dictionary(uniqueKeysWithValues: all.sorted { $0.key < $1.key }.suffix(12).map { ($0.key, $0.value) }) }
        preferences.set(all, forKey: beaconAnswersKey)
    }

    private static func savedBeaconAnswer(for key: String, preferences: UserDefaults) -> PreparationFeatureBridge.Output? {
        // -noSavedBeacon: UI tests of the replay path must not be satisfied by an earlier live answer.
        guard !key.isEmpty, !ProcessInfo.processInfo.arguments.contains("-noSavedBeacon"), let data = (preferences.dictionary(forKey: beaconAnswersKey) as? [String: Data])?[key] else { return nil }
        return try? JSONDecoder().decode(PreparationFeatureBridge.Output.self, from: data)
    }

    /// Returns the Prepare list to the app's own order for these inputs.
    func clearPreparationPersonalization() { preparationAIDeclined = preparationAIKey; preparationAI = nil }

    // MARK: - Beacon drill setup (fictional households, development gateway)

    /// Why the last drill setup request produced nothing (shown in development builds only).
    private(set) var drillSetupFailure: String?

    /// Beacon's suggested setup for a drill about to start; the family sees and can change every choice.
    func beaconDrillSetup(scenarioID: String) async -> (DrillSetupBridge.Accepted, replay: Bool)? {
        guard preparationAIAvailable, let client = DirectorGatewayClient.current, let household, let home, let rubric,
              household.isFictional, let expectedKey = preparationAIKey else { return nil }
        await refreshScorecard(force: true)
        guard !Task.isCancelled, preparationAIKey == expectedKey else { return nil }
        // Rooms by type (with a number when repeated), never custom labels that may carry names.
        var counts: [SpaceKind: Int] = [:]
        var roomNames: [String: String] = [:]
        for space in home.spaces {
            counts[space.kind, default: 0] += 1
            // English for the model; Beacon's reason is shown as written (the app's own setup text stays localized).
            let base = DisplayNames.name(space.kind.rawValue, localizer: content?.localizer(for: "en") ?? localizer)
            // Fictional sample labels ("Kid's bedroom") carry no personal names and match what the family sees.
            roomNames[space.id] = home.isFictional ? HomeScenePresentation.roomLabel(space.id, in: home)
                : home.spaces.filter { $0.kind == space.kind }.count > 1 ? "\(base) \(counts[space.kind]!)" : base
        }
        guard var request = try? DrillSetupBridge.request(requestID: "drill-\(UUID().uuidString)", scenarioID: scenarioID,
                                                          readableRoom: { roomNames[$0] ?? "a room" }, household: household, home: home,
                                                          inventory: aiState.inventory, rubric: rubric, state: aiState,
                                                          places: savedPlaces, scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentHostScorecard) else { return nil }
        request.providerConsent = ["codex", "gemini", "groq"]
        // No workInFlight here: the setup screen treats the app as busy and would rebuild, dropping the answer.
        let scope = scopeSessionID, key = currentKey
        let response = await client.drillSetup(request, householdID: household.id, scenarioID: scenarioID)
        guard scopeSessionID == scope, currentKey == key, preparationAIKey == expectedKey, !Task.isCancelled else { return nil }
        switch response {
        case .failure(let failure):
            drillSetupFailure = failure.reason
            return nil
        case .success(let (output, replay)):
            guard let accepted = DrillSetupBridge.accept(output, request: request, home: home, household: household) else {
                drillSetupFailure = "refused by Core"
                return nil
            }
            drillSetupFailure = nil
            return (accepted, replay)
        }
    }

    // MARK: - Beacon debrief (fictional households, development gateway)

    enum BeaconDebriefState: Equatable { case working, ready(DebriefFeatureBridge.Accepted, replay: Bool), unavailable(String) }
    /// Bound to the exact finished rehearsal it describes.
    private(set) var beaconDebrief: (input: RehearsalInput, key: PreparationAIKey, state: BeaconDebriefState)?

    func beaconDebriefState(for input: RehearsalInput) -> BeaconDebriefState? {
        guard let beaconDebrief, beaconDebrief.input == input, beaconDebrief.key == preparationAIKey else { return nil }
        return beaconDebrief.state
    }

    /// Asks Beacon once per finished rehearsal for a short household summary of what it showed.
    func requestBeaconDebrief(for result: RehearsalResult) async {
        guard preparationAIAvailable, let client = DirectorGatewayClient.current, let household, let rubric,
              household.isFictional, beaconDebriefState(for: result.input) == nil, let expectedKey = preparationAIKey,
              result.input.household.id == household.id, result.input.household.revision == household.revision,
              result.input.home?.revision == home?.revision else { return }
        let input = result.input
        beaconDebrief = (input, expectedKey, .working)
        await refreshScorecard(force: true)
        guard !Task.isCancelled, preparationAIKey == expectedKey,
              beaconDebrief?.key == expectedKey else { return }
        let readable = Dictionary(result.recommendations.map { rec in
            let values = rec.localizedTemplateValues(household: household, localizer: localizer)
            return (rec.id, localizer(rec.titleKey, values) + ". " + localizer(rec.whyKey, values))
        }, uniquingKeysWith: { a, _ in a })
        // Host receipt labels: the app's own text for the rehearsal's events and the family's chosen options.
        var labels: [String: String] = [:]
        for event in result.events { labels[event.id] = localizer(event.titleKey, event.templateValues) }
        for decision in result.decisions { for option in decision.options { labels[option.labelKey] = localizer(option.labelKey) } }
        guard var request = try? DebriefFeatureBridge.request(requestID: "debrief-\(UUID().uuidString)", scenarioID: result.input.scenarioID,
                                                              recommendations: result.recommendations, readable: readable,
                                                              rehearsal: result, labels: labels, household: household,
                                                              home: home, inventory: aiState.inventory, rubric: rubric, state: aiState,
                                                              places: savedPlaces, scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentHostScorecard) else {
            beaconDebrief = (input, expectedKey, .unavailable("context")); return
        }
        request.providerConsent = ["codex", "gemini", "groq"]
        let scope = scopeSessionID
        let outcome = await client.debrief(request, householdID: household.id, scenarioID: input.scenarioID)
        guard scopeSessionID == scope, beaconDebrief?.input == input, preparationAIKey == expectedKey, !Task.isCancelled else { return }
        switch outcome {
        case .completed(let output, let replay):
            if let accepted = DebriefFeatureBridge.accept(output, request: request) { beaconDebrief = (input, expectedKey, .ready(accepted, replay: replay)) }
            else { beaconDebrief = (input, expectedKey, .unavailable("rejected")) }
        case .unavailable(let reason):
            beaconDebrief = (input, expectedKey, .unavailable(reason))
        }
    }

    /// Opt-in for this app session only: Beacon (the gateway: Codex first, then Gemini, then Groq) directs the next
    /// moments of a fictional household's exercise.
    /// Requires a development gateway (launch arguments); real households never use it until production authorization.
    /// On by default wherever Beacon is configured (fictional households only); the switch turns it off for the session.
    var cloudDirectorEnabled = DirectorGatewayClient.current != nil
    /// Why the last cloud turn fell back to this phone, shown beside the scene; nil when it did not.
    private(set) var directorFallbackNote: String?
    /// The director transport; the gateway client in the app, a fake in unit tests.
    var directorTransport: (any DirectorTransport)? = DirectorGatewayClient.current
    /// Whole-turn bound for a gateway director turn (all tool rounds). Past it, the turn is cancelled and this phone's
    /// local director takes the step, so a stalled provider never leaves the exercise stuck.
    var directorDeadline: Duration = .seconds(18)
    /// A gateway director turn is running. It does not count as `isWorking`, so End stays available; a second Next
    /// while it runs is ignored. The UI shows brief progress from this (adaptive.director.inFlight).
    var directorTurnInFlight: Bool { directorTurnID != nil }
    private var directorTurnID: UUID?
    private var directorRace: DirectorRace<GatewayDirectorOutcome>?

    var cloudDirectorAvailable: Bool { directorTransport != nil && household?.isFictional == true }

    /// Cancels a gateway director turn in flight (family action, End, restart or close). Its result is never applied.
    private func cancelDirectorTurn() {
        guard directorTurnInFlight else { return }
        directorGate.invalidate()
        directorTurnID = nil
        directorRace?.finish(.failure("cancelled"))
        directorRace = nil
    }

    /// One director turn. With the cloud director enabled, the gateway proposes (tool calls run read-only on this
    /// phone at the same revision) within `directorDeadline`; otherwise, or whenever that fails or runs out of time,
    /// the local director proposes. Either way Core validates the proposal before anything is saved or shown.
    func advanceAdaptive() async {
        guard !directorTurnInFlight, !privateWriteInFlight, let exercise = adaptive, let scenarios, let key = currentKey, !exercise.receipt.finished,
              exercise.receipt.directorState?.awaitingUserAction != true else { return }
        let scope = scopeSessionID
        let ticket = directorGate.begin(for: key)
        directorFallbackNote = nil
        if cloudDirectorEnabled, cloudDirectorAvailable, let transport = directorTransport,
           exercise.session.initial.household.isFictional {
            let turn = UUID()
            directorTurnID = turn
            let outcome = await boundedGatewayTurn(transport: transport, exercise: exercise, library: scenarios)
            if directorTurnID == turn { directorTurnID = nil }
            guard scopeSessionID == scope, directorGate.shouldApply(ticket, current: currentKey),
                  adaptive?.session.id == exercise.session.id, adaptive?.session.revision == exercise.session.revision else { return }
            switch outcome {
            case .success(let proposal, let binding, let source):
                let applied = await commitAdaptive(director: source, narration: proposal.purpose) { session in
                    try proposal.commit(to: &session, binding: binding, library: scenarios, persist: { _ in })
                }
                if applied { return }
                directorFallbackNote = localizer("adaptive.fallback.rejected")
            case .waitingForFamily:
                return
            case .deadline:
                directorFallbackNote = localizer("adaptive.fallback.deadline")
            case .failure:
                directorFallbackNote = localizer("adaptive.fallback.unavailable")
            }
        }
        guard scopeSessionID == scope, directorGate.shouldApply(ticket, current: currentKey),
              let current = adaptive, current.session.id == exercise.session.id, current.session.revision == exercise.session.revision,
              let commit = LocalDirector.nextCommit(session: current.session, receipt: current.receipt, library: scenarios) else { return }
        await commitAdaptive(director: .local, narration: nil) { session in try session.commit(commit, library: scenarios) }
    }

    enum GatewayDirectorOutcome: Sendable {
        case success(DirectorProposal, AgentContextBinding, DirectorSource)
        case waitingForFamily
        case deadline
        case failure(String)
    }

    /// Runs one gateway operation under `directorDeadline`. On the deadline the operation is cancelled (the request
    /// task, then a best-effort cancel of the latest gateway token) and `.deadline` returns at once, even if the
    /// transport ignores cancellation; its late result is discarded.
    private func boundedGatewayTurn(transport: any DirectorTransport, exercise: AdaptiveExercise, library: ScenarioLibrary) async -> GatewayDirectorOutcome {
        let tokens = DirectorTokenBox()
        let work = Task { @MainActor [weak self] () -> GatewayDirectorOutcome in
            guard let self else { return .failure("released") }
            return await self.gatewayProposal(transport: transport, exercise: exercise, library: library, tokens: tokens)
        }
        let race = DirectorRace(work, deadline: directorDeadline, timeout: GatewayDirectorOutcome.deadline)
        directorRace = race
        let outcome = await race.value
        if directorRace === race { directorRace = nil }
        if case .success = outcome {} else {
            // Deadline, family action or failure: stop the request and release the gateway job.
            work.cancel()
            if let token = tokens.current { Task { await transport.cancel(token: token) } }
        }
        return outcome
    }

    /// Runs one gateway operation to completion. Each tool call executes through Core on the unchanged session; if the
    /// family acts or the exercise changes meanwhile, the operation is cancelled and nothing from it is applied.
    private func gatewayProposal(transport: any DirectorTransport, exercise: AdaptiveExercise, library: ScenarioLibrary,
                                 tokens: DirectorTokenBox) async -> GatewayDirectorOutcome {
        let session = exercise.session, receipt = exercise.receipt
        guard let expectedKey = preparationAIKey, let rubric else { return .failure("context") }
        await refreshScorecard(force: true)
        guard !Task.isCancelled, preparationAIKey == expectedKey, currentKey == exercise.sourceKey,
              adaptive?.session.id == session.id, adaptive?.session.revision == session.revision else { return .failure("stale") }
        let tasks = PreparationTaskCatalog.build(household: session.initial.household, home: session.initial.home,
                                                rubric: rubric, at: Date())
        guard let request = try? DirectorGatewayBridge.operationRequest(requestID: "op-\(UUID().uuidString)", session: session,
                                                                         receipt: receipt, library: library, state: aiState, places: savedPlaces, tasks: tasks,
                                                                         scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentHostScorecard) else { return .failure("context") }
        let binding = request.context.binding
        var outcome = await transport.start(request)
        // The gateway allows at most 6 provider calls per operation (up to 5 model tool calls), then asks this phone
        // to validate the final proposal's suggested actions once (validateSuggestedActions) before completing.
        for _ in 0..<6 {
            guard case .needsTools(let token, let toolBinding, let call) = outcome else { break }
            tokens.current = token
            guard !Task.isCancelled, toolBinding == binding, preparationAIKey == expectedKey, adaptive?.session.id == session.id, adaptive?.session.revision == session.revision else {
                await transport.cancel(token: token)
                return .failure("stale")
            }
            let execution = Task.detached(priority: .userInitiated) {
                try DirectorGatewayBridge.execute(call, session: session, binding: binding, library: library)
            }
            let result: DirectorGatewayBridge.ToolResult
            do { result = try await execution.value } catch {
                await transport.cancel(token: token)
                return .failure("tool_rejected")
            }
            outcome = await transport.resume(token: token, binding: binding, callID: call.id, result: result, expectedContextBinding: request.context.contextBinding)
        }
        switch outcome {
        case .completed(let proposal, let servedBy):
            guard !Task.isCancelled, preparationAIKey == expectedKey, adaptive?.session.id == session.id, adaptive?.session.revision == session.revision else { return .failure("stale") }
            return .success(proposal, binding, DirectorSource(servedBy: servedBy))
        case .needsUserAction: return .waitingForFamily
        case .unavailable(let reason): return .failure(reason)
        case .needsTools(let token, _, _):
            await transport.cancel(token: token)
            return .failure("tool_budget")
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
        guard !privateWriteInFlight, let exercise = adaptive, let household, currentKey == exercise.sourceKey else { return false }
        let scope = scopeSessionID, originalData = integratedAIState
        workInFlight += 1
        defer { workInFlight -= 1 }
        do {
            let (session, receipt) = try await Task.detached(priority: .userInitiated) {
                var candidate = exercise.session
                let receipt = try apply(&candidate)
                return (candidate, receipt)
            }.value
            guard scopeSessionID == scope, currentKey == exercise.sourceKey, integratedAIState == originalData else { return false }
            var state = try integratedStateForRehearsal()
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
            guard scopeSessionID == scope, currentKey == exercise.sourceKey,
                  adaptive?.session.id == exercise.session.id, adaptive?.session.revision == exercise.session.revision else { return false }
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
        guard pendingPracticeFeedback == nil, let attempt = latestPracticeCheck, let scenarios,
              let session = try? aiState.activePracticeCheckSession(attemptID: attempt.id, library: scenarios) else { return nil }
        let order = IntegratedAIState.practiceOrder(attempt.variantID)
        let index = attempt.observations?.count ?? 0
        guard order.indices.contains(index) else { return nil }
        return (attempt, session, order[index])
    }

    var pendingPracticeFeedback: (attempt: PracticeAttempt, session: SimulationSession, observation: PracticeObservation)? {
        guard let attempt = latestPracticeCheck, let observations = attempt.observations,
              let index = observations.firstIndex(where: {
                  $0.feedbackAcknowledged == false || ($0.feedbackAcknowledged == nil && !$0.feedbackRevealed)
              }),
              let sources = attempt.phaseSources, sources.indices.contains(index),
              let session = aiState.sessions.first(where: { $0.id == sources[index].sessionID }) else { return nil }
        return (attempt, session, observations[index])
    }

    @discardableResult
    func acknowledgePracticeFeedback(attemptID: String, actionID: String, expectedScope: String, expectedLocale: String) async -> Bool {
        guard scopeSessionID == expectedScope, locale == expectedLocale,
              let pending = pendingPracticeFeedback, pending.attempt.id == attemptID,
              pending.observation.actionID == actionID, pending.observation.feedbackRevealed else { return false }
        return await updateAIState { state, _ in
            guard let a = state.practiceAttempts.firstIndex(where: { $0.id == attemptID }),
                  let i = state.practiceAttempts[a].observations?.firstIndex(where: { $0.actionID == actionID }) else { throw SessionError.stale }
            state.practiceAttempts[a].observations?[i].feedbackAcknowledged = true
        }
    }

    /// Builds the four situations from the current household and home and freezes them with the attempt in one save.
    /// An unfinished check is resumed instead; nothing is re-rolled.
    @discardableResult
    func beginPracticeCheck() async -> Bool {
        guard !privateWriteInFlight, let household, let content, let scenarios else { return false }
        let scope = scopeSessionID, key = currentKey, originalData = integratedAIState
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
        guard scopeSessionID == scope, currentKey == key, integratedAIState == originalData else { return false }
        return await updateAIState { state, _ in
            state.sessions.append(contentsOf: sources)
            try state.beginPracticeCheck(id: id, variantID: variant, sessionIDs: sources.map(\.id), library: library)
        }
    }

    /// Records the family's first answer for the current situation before any feedback. Returns the stored observation.
    struct PracticeStepIdentity: Hashable {
        let scope: String
        let attemptID: String
        let sessionID: String
        let revision: Int
        let locale: String
    }

    var practiceStepIdentity: PracticeStepIdentity? {
        guard let step = practiceStep() else { return nil }
        return .init(scope: scopeSessionID, attemptID: step.attempt.id,
                     sessionID: step.session.id, revision: step.session.revision, locale: locale)
    }

    func submitPracticeAnswer(_ command: SessionCommand, expected: PracticeStepIdentity) async -> PracticeObservation? {
        guard practiceStepIdentity == expected, let step = practiceStep(), let scenarios else { return nil }
        let commit = SessionCommit(id: "answer-\(UUID().uuidString)", actor: "user", baseRevision: step.session.revision, commands: [command])
        var observation: PracticeObservation?
        let saved = await updateAIState { state, _ in
            observation = try state.submitPracticeAction(attemptID: step.attempt.id, competencyID: step.competency, commit: commit, library: scenarios)
        }
        guard saved, scopeSessionID == expected.scope, locale == expected.locale,
              latestPracticeCheck?.id == expected.attemptID else { return nil }
        return observation
    }

    /// Feedback is recorded as revealed (never changing the answer) before the screen shows it.
    @discardableResult
    func revealPracticeFeedback(attemptID: String, actionID: String) async -> Bool {
        await updateAIState { state, _ in
            _ = try state.revealPracticeFeedback(attemptID: attemptID, actionID: actionID)
        }
    }

    func closeAdaptive() { cancelDirectorTurn(); adaptive = nil; directorFallbackNote = nil }

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
        rehearsalSessionID = nil
        rehearsalReceipt = nil
        adaptive = nil
        directorGate.invalidate()
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
    private func save(snapshot: PrivateSnapshot, preservingIntegratedState: Bool = true) async -> Bool {
        guard !privateWriteInFlight else {
            lastError = "Another edit is still saving. Your draft was kept; try Save again."
            return false
        }
        privateWriteInFlight = true
        defer { privateWriteInFlight = false }
        var candidate = snapshot
        if preservingIntegratedState, candidate.integratedAIState == nil,
           candidate.household.id == household?.id,
           candidate.household.isFictional == household?.isFictional {
            candidate.integratedAIState = integratedAIState
        }
        do {
            let destination = candidate.household.isFictional ? (exampleStore ?? store) : store
            try await destination.save(candidate)
            privateStateGeneration += 1
            if !preservingIntegratedState || candidate.household.id != household?.id || candidate.household.isFictional != household?.isFictional {
                scopeSessionID = UUID().uuidString
            }
            integratedAIState = candidate.integratedAIState
            if !candidate.household.isFictional { hasPersonalHousehold = true }
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

    /// Examples and isolated checks never alter the installation's real notification schedule.
    var managesPersonalReminders: Bool {
        guard household?.isFictional == false else { return false }
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.environment["XCTestConfigurationFilePath"] != nil ||
            DemoLaunch.current.usesInMemoryStore || process.arguments.contains("-uiTestingVaultID") { return false }
        #endif
        return true
    }

    /// Delete everything private: vault, derived caches, temporary exports, and the key.
    @discardableResult
    func deleteAllPrivateData() async -> Bool {
        guard !privateWriteInFlight else { lastError = "An edit is still saving. Try again."; return false }
        privateWriteInFlight = true
        defer { privateWriteInFlight = false }
        do {
            let deletingExample = household?.isFictional == true
            let destination = deletingExample ? (exampleStore ?? store) : store
            try await destination.deleteAll()
            if !deletingExample { hasPersonalHousehold = false }
            privateStateGeneration += 1
            if managesPersonalReminders { LocalReviewReminderScheduler.shared.cancel() }
            TemporaryExports.purgeAll()
            household = nil; home = nil; savedPlan = nil; savedPlaces = []; rehearsal = nil; comparison = nil; nextStepResults = nil
            integratedAIState = nil
            scopeSessionID = UUID().uuidString
            suppressCardSelectionPersistence = deletingExample
            cardSelection = FamilyCardSelection()
            suppressCardSelectionPersistence = false
            runGate.invalidate(); planGate.invalidate(); nextGate.invalidate()
            phase = .onboarding
            if deletingExample, exampleStore != nil, hasPersonalHousehold {
                // The example transaction is finished. Return to the untouched personal
                // store instead of stranding an existing family in new-household setup.
                privateWriteInFlight = false
                await loadPrivateData()
            }
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }
}
