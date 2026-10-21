import SwiftUI
import DryRunCore

struct RehearseTabView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    // Spatial exercises first, home fire as the flagship; all six hazards stay available.
    static let scenarioIDs = ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"]
    static let symbols = ["freeze-power-loss": "snowflake", "heat-grid-strain": "thermometer.sun", "tornado": "tornado",
                          "flash-flood": "water.waves", "home-fire": "flame", "water-outage": "drop.triangle"]
    static let tints: [String: Color] = ["freeze-power-loss": .blue, "heat-grid-strain": .orange, "tornado": .purple,
                                         "flash-flood": .teal, "home-fire": .red, "water-outage": .cyan]

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label(l("common.practiceDisclaimer"), systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.capabilities.isOnline {
                    Label(l("common.offline"), systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
                }
                if let home = model.home {
                    SectionCard(title: home.label, systemImage: "house") {
                        if home.isFictional { Label(s("Example home"), systemImage: "sparkles").font(.caption) }
                        FloorPlanView(home: home, routes: [], highlightedFloorID: nil).frame(height: 210)
                    }
                } else {
                    Label(s("Add and review a home layout to practice spatial routes. Other scenarios remain available."), systemImage: "house")
                        .font(.callout).foregroundStyle(.secondary)
                }
                NavigationLink(value: "practice:check") {
                    SectionCard(title: l("practice.title"), systemImage: "checklist.checked") {
                        Text(l("practice.cardDetail")).font(.footnote).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("practice.open")
                Text(l("common.chooseScenario")).font(.headline).padding(.top, Theme.Space.s)
                ForEach(Self.scenarioIDs, id: \.self) { id in
                    NavigationLink(value: id) { ScenarioCard(id: id) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scenario.\(id)")
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.tab.rehearse"))
        .navigationDestination(for: String.self) { id in
            if id.hasPrefix("adaptive:") { AdaptiveRehearsalView(scenarioID: String(id.dropFirst("adaptive:".count))) }
            else if id == "practice:check" { PracticeCheckView() }
            else { RehearsalView(scenarioID: id) }
        }
    }
}

struct ScenarioCard: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        let l = model.localizer
        let tint = RehearseTabView.tints[id] ?? Theme.accent
        HStack(spacing: Theme.Space.m) {
            Image(systemName: RehearseTabView.symbols[id] ?? "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(l("common.scenario.\(id)")).font(.body.weight(.semibold))
                Text(l("ui.scenario.\(id).blurb")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(Theme.Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One rehearsal, one step at a time. The newest event is the hero; the decision (when one is pending) comes right
/// after it; only the services that just changed are shown, with the full list one tap away.
struct RehearsalView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    let scenarioID: String
    @Environment(AppModel.self) private var model
    @State private var showDebrief = false
    @State private var showAllServices = false
    @State private var showEarlier = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var originID = ""
    @State private var waterEntryID = ""
    @State private var refugeID = ""
    @State private var householdLeak = false
    @State private var daytimeStarts: [String: String] = [:]

    var body: some View {
        let l = model.localizer
        let session = model.rehearsal.flatMap { $0.result.input.scenarioID == scenarioID ? $0 : nil }
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PracticeBanner(text: l("common.practiceLabel")).id("top")
                    if session?.result.input.effectiveSpatialOptions.floodIsHouseholdLeak == true {
                        Label(l("scenario.household-leak.title"), systemImage: "drop").font(.headline)
                    }
                    if let session { stepLabel(session) }
                }
                if let session {
                    if let home = session.result.input.home, ["home-fire", "flash-flood", "tornado"].contains(scenarioID) {
                        SpatialRehearsalScene(home: home, household: session.result.input.household,
                                              state: session.snapshotAtCursor?.spatialState,
                                              previous: session.spatialStateBeforeCursor)
                            .accessibilityIdentifier("rehearsal.scene")
                    }
                    if session.result.input.home == nil { Label(model.localizer("map.layoutMissing"), systemImage: "house").font(.callout).foregroundStyle(.secondary) }
                    let events = session.visibleEvents
                    if let latest = events.last {
                        EventCard(event: latest, isCurrent: true, result: session.result)
                        changedServices(latest)
                        if session.pendingDecision == nil, let (_, option) = answeredChoice(session, latest: latest) {
                            choiceFeedback(option)
                        }
                    } else {
                        intro(session)
                    }
                    if let decision = session.pendingDecision {
                        DecisionCard(decision: decision) { option in
                            Task { await model.choose(option: option, at: decision.id) }
                        }
                        .id("decision")
                    }
                    if let home = session.result.input.home, ["home-fire", "flash-flood", "tornado"].contains(scenarioID) {
                        sceneOptions(session, home: home)
                    }
                    if session.isFinished && !["home-fire", "flash-flood", "tornado"].contains(scenarioID) && !session.result.routes.isEmpty {
                        RouteSummaryView(routes: session.result.routes)
                    }
                    if let snapshot = session.snapshotAtCursor {
                        DisclosureGroup(isExpanded: $showAllServices) {
                            ServiceStateGrid(snapshot: snapshot).padding(.top, Theme.Space.s)
                        } label: {
                            Label(l("ui.rehearse.allServices"), systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                        }
                        .padding(Theme.Space.l)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .accessibilityIdentifier("rehearsal.allServices")
                    }
                    if events.count > 1 {
                        SectionCard {
                            DisclosureGroup(isExpanded: $showEarlier) {
                                ForEach(events.dropLast().reversed()) { e in TimelineRow(event: e, result: session.result) }
                            } label: {
                                Label(l("ui.rehearse.earlier"), systemImage: "clock.arrow.circlepath").font(.subheadline.weight(.semibold))
                            }
                            .accessibilityIdentifier("rehearsal.earlier")
                        }
                    }
                } else if model.isWorking {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xxl)
                } else {
                    Button(l("common.action.start")) { Task { await model.startRehearsal(scenarioID: scenarioID) } }
                        .buttonStyle(.primary)
                }
            }
            .padding()
        }
        // A new decision must be fully visible above the bottom bar, not hidden behind it.
        .onChange(of: session?.pendingDecision?.id) { _, id in
            guard id != nil else { return }
            withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("decision", anchor: .bottom) }
        }
        .onChange(of: session?.revealed) { _, _ in
            if session?.pendingDecision == nil { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("top", anchor: .top) } }
        }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { if let session { controls(session) } }
        .navigationTitle(l(session?.result.input.effectiveSpatialOptions.floodIsHouseholdLeak == true ? "scenario.household-leak.title" : "common.scenario.\(scenarioID)"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.rehearsal?.result.input.scenarioID != scenarioID {
                await model.startRehearsal(scenarioID: scenarioID)
                let demo = DemoLaunch.current
                if demo.scenarioID == scenarioID { await model.demoAdvance(demo.step) }
            }
        }
        .sheet(isPresented: $showDebrief) { NavigationStack { DebriefView() } }
        .onChange(of: session?.result.input, initial: true) { _, input in
            guard let input else { return }
            let options = input.effectiveSpatialOptions
            originID = options.originSpaceID ?? ""
            waterEntryID = options.floodAffectedSpaceIDs.first ?? ""
            refugeID = options.refugeSpaceID ?? ""
            householdLeak = options.floodIsHouseholdLeak
            daytimeStarts = options.startingSpaceIDs
        }
    }

    private func sceneOptions(_ session: RehearsalCursor, home: HomeModel) -> some View {
        DisclosureGroup(s("Exercise starting assumptions")) {
            if scenarioID == "home-fire" {
                Picker(s("Fire starts in one room"), selection: $originID) {
                    Text(s("Use the authored default")).tag("")
                    ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                }
            }
            if scenarioID == "flash-flood" {
                Toggle(s("Local household leak exercise"), isOn: $householdLeak)
                Picker(s("Water-affected room (optional)"), selection: $waterEntryID) {
                    Text(householdLeak ? model.localizer("spatial.leak-location-unknown") : s("Regional warning; indoor extent unknown")).tag("")
                    ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                }
                if !householdLeak {
                    Picker(s("Higher refuge to review (optional)"), selection: $refugeID) {
                        Text(s("No refuge established")).tag("")
                        ForEach(home.spaces.filter { $0.kind != .closet }) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                    }
                }
            }
            ForEach(session.result.input.household.people) { person in
                Picker(model.localizer("spatial.start-person", ["name": person.localizedLabel(model.localizer)]), selection: Binding(get: { daytimeStarts[person.id] ?? "" }, set: { daytimeStarts[person.id] = $0 })) {
                    Text(s("Use recorded assignment")).tag("")
                    ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                }
            }
            Button(s("Restart with these assumptions")) {
                var variants = session.result.input.variants.filter { !$0.hasPrefix("origin:") && !$0.hasPrefix("waterEntry:") && !$0.hasPrefix("refuge:") && !$0.hasPrefix("start:") && $0 != "householdLeak" }
                if !originID.isEmpty { variants.append("origin:\(originID)") }
                if !waterEntryID.isEmpty { variants.append("waterEntry:\(waterEntryID)") }
                if !householdLeak && !refugeID.isEmpty { variants.append("refuge:\(refugeID)") }
                if householdLeak { variants.append("householdLeak") }
                for key in daytimeStarts.keys.sorted() { if let room = daytimeStarts[key], !room.isEmpty { variants.append("start:\(key)|\(room)") } }
                Task { await model.startRehearsal(scenarioID: scenarioID, variants: variants) }
            }
        }
        .font(.callout)
        .accessibilityIdentifier("rehearsal.assumptions")
    }

    /// "Step 2 of 6": progress through the exercise. Exercise minutes are not shown up front, so nothing reads as a
    /// countdown or a prediction of how much time a household has. Before the first step only the total is shown.
    private func stepLabel(_ session: RehearsalCursor) -> some View {
        let text = session.revealed == 0
            ? model.localizer("ui.rehearse.stepCount", ["total": "\(session.keyMomentCount)"])
            : model.localizer("ui.rehearse.step", ["step": "\(max(session.keyMomentsRevealed, 1))", "total": "\(session.keyMomentCount)"])
        return Label(text, systemImage: "list.number")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("rehearsal.step")
    }

    /// Who the family is and what is about to happen, so the first screen is not an empty box. The scenario blurb
    /// is the same one shown on the Rehearse list; the household line matches onboarding.
    private func intro(_ session: RehearsalCursor) -> some View {
        let l = model.localizer
        let household = session.result.input.household
        return SectionCard(title: l("ui.rehearse.introTitle"), systemImage: "info.circle") {
            Text(l("ui.scenario.\(scenarioID).blurb")).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(l("ui.rehearse.introHousehold", ["household": household.displayName, "summary": OnboardingView.summary(household, localizer: l)]))
                .font(.callout)
            if household.isFictional { StatusPill(text: l("family.example"), systemImage: "house", tint: Theme.caution) }
            Text(l("ui.rehearse.introHow")).font(.footnote).foregroundStyle(.secondary)
            NavigationLink(value: "adaptive:\(scenarioID)") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Label(l("adaptive.open"), systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.callout.weight(.semibold))
                    Text(l("adaptive.openDetail")).font(.footnote).foregroundStyle(.secondary)
                }.frame(minHeight: Theme.minTap)
            }.accessibilityIdentifier("rehearsal.adaptive")
        }
        .accessibilityIdentifier("rehearsal.intro")
    }

    /// The decision answered at the current step, until the exercise moves past that minute. The same option text and
    /// feedback appear again in the debrief.
    private func answeredChoice(_ session: RehearsalCursor, latest: SimulationEvent) -> (DecisionPoint, DecisionPoint.Option)? {
        let result = session.result
        let next = session.revealed < result.events.count ? result.events[session.revealed] : nil
        // A decision just answered is one the cursor has reached but not moved past (same test that made it pending),
        // or one whose outcome event is the newest thing on screen.
        func current(_ d: DecisionPoint) -> Bool {
            if latest.id == "evt.\(d.id)" { return true }
            guard d.simMinute >= latest.simMinute else { return false }
            guard let next else { return true }
            return next.id == "evt.\(d.id)" || next.simMinute > d.simMinute
        }
        guard let decision = result.decisions
                .filter({ result.input.choices[$0.id] != nil && current($0) })
                .max(by: { ($0.simMinute, $0.id) < ($1.simMinute, $1.id) }),
              let chosen = result.input.choices[decision.id],
              let option = decision.options.first(where: { $0.id == chosen }) else { return nil }
        return (decision, option)
    }

    private func choiceFeedback(_ option: DecisionPoint.Option) -> some View {
        let l = model.localizer
        return SectionCard(title: l("ui.rehearse.youChose"), systemImage: "arrow.turn.down.right", tint: Theme.accent) {
            Text(l(option.labelKey)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(l(option.feedbackKey)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("rehearsal.choiceFeedback")
    }

    private func clock(_ session: RehearsalCursor) -> some View {
        let minute = session.currentMinute
        let text = RehearsalPresentation.compactTime(minutes: minute, localizer: model.localizer)
        return Label(model.localizer("common.simClock", ["time": text]), systemImage: "clock")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(RehearsalPresentation.spokenTime(minutes: minute, localizer: model.localizer))
    }

    /// Services and resources the newest event changed, as status pills.
    @ViewBuilder
    private func changedServices(_ event: SimulationEvent) -> some View {
        if !event.serviceChanges.isEmpty {
            let l = model.localizer
            SectionCard(title: l("ui.rehearse.whatChanged"), systemImage: "arrow.triangle.swap") {
                ForEach(event.serviceChanges.keys.sorted(), id: \.self) { id in
                    let state = event.serviceChanges[id] ?? .unknown
                    HStack {
                        Text(ServiceNames.name(id, household: model.household, localizer: model.localizer))
                        Spacer()
                        StatusPill(text: l("common.status.\(state.rawValue)"), systemImage: Theme.symbol(for: state),
                                   tint: Theme.color(for: state))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func controls(_ session: RehearsalCursor) -> some View {
        let l = model.localizer
        let canAdvance = session.pendingDecision == nil && session.revealed < session.result.events.count
        return AdaptiveStack(spacing: Theme.Space.s) {
            Button {
                Task { await model.startRehearsal(scenarioID: scenarioID, variants: session.result.input.variants, restart: true) }
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .accessibilityLabel(l("common.action.replay"))
            .accessibilityIdentifier("rehearsal.replay")
            // Both stay visible so the next step is always obvious: "Next" until the end, then "Debrief".
            Button { model.rehearsal?.advanceToNextKeyEvent() } label: {
                Label(session.pendingDecision != nil ? l("ui.rehearse.chooseAbove") : l("common.action.advance"),
                      systemImage: session.pendingDecision != nil ? "hand.point.up" : "forward.frame")
            }
            .buttonStyle(PrimaryButtonStyle(tint: session.isFinished ? Color.secondary : Theme.accent))
            .disabled(!canAdvance)
            .accessibilityIdentifier("rehearsal.next")
            Button { showDebrief = true } label: { Label(l("common.debrief"), systemImage: "list.bullet.clipboard") }
                .buttonStyle(PrimaryButtonStyle(tint: session.isFinished ? Theme.accent : Color.secondary))
                .disabled(!session.isFinished)
                .accessibilityIdentifier("rehearsal.debrief")
        }
        .padding(.horizontal).padding(.vertical, Theme.Space.s)
        // The bar stays readable but capped, so at the largest sizes it does not cover most of the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }
}

struct SpatialRehearsalScene: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let home: HomeModel
    let household: HouseholdProfile
    let state: SpatialExerciseState?
    var previous: SpatialExerciseState? = nil
    @State private var personID: String?
    @State private var show3D = false
    @State private var selectedFloorID: String?
    private var selectedPersonID: String? { personID ?? household.people.first?.id }
    private var occupant: ExerciseOccupantState? { state?.occupants?.first { $0.personID == selectedPersonID } }
    private var route: RouteResult? {
        guard occupant?.exteriorExitPortalID == nil else { return nil }
        return state?.routes.first { $0.request.personID == selectedPersonID }
    }
    private var previousRoute: RouteResult? { previous?.routes.first { $0.request.personID == (personID ?? household.people.first?.id) } }
    /// Only the selected person's current routes. An earlier route that is no longer valid is never drawn as available.
    private var currentPaths: [RoutePath] { [route?.primary, route?.alternative].compactMap { $0 } }

    /// Planning only: a current indoor route can link to the outdoor gathering plan, never prove arrival.
    /// The exited occupant case deliberately has no route and cannot reuse the previous stage's path.
    private var plannedMapHandoff: PlannedExteriorHandoff? {
        guard let state, state.hazard == .homeFire || state.hazard == .flashFlood,
              model.household == household, model.home == home,
              model.rehearsal?.snapshotAtCursor?.spatialState == state,
              let route else { return nil }
        return PlannedExteriorHandoff(route: route, home: home, household: household, places: model.savedPlaces)
    }

    private func mapPlanningLinkTitle(hasMeetingPoint: Bool) -> String {
        switch model.locale {
        case "es": hasMeetingPoint ? "Revisar el punto de reunión en el mapa" : "Elegir un punto de reunión exterior"
        case "vi": hasMeetingPoint ? "Xem điểm tập trung trên bản đồ" : "Chọn điểm tập trung ngoài trời"
        default: hasMeetingPoint ? "Review gathering point on map" : "Choose outdoor gathering point"
        }
    }

    @ViewBuilder private func plannedMapDestination(_ handoff: PlannedExteriorHandoff, hazard: HazardKind, scopeID: String) -> some View {
        // Navigation destinations can outlive their source row. Recheck both the canonical scene and scope.
        if model.scopeSessionID == scopeID, let currentHandoff = plannedMapHandoff,
           handoff.isCurrent(home: home, household: household, places: model.savedPlaces) {
            if let store = model.regionalResources {
                MapPlanningView(store: store, purpose: .outsideMeetingPoint, embedInNavigation: false,
                    context: MapPlanningContext(hazard: hazard, phase: .simulation), plannedExteriorHandoff: currentHandoff)
            } else if let content = model.content {
                MapPlanningView(content: content, client: model.publicClient, regionID: household.regionID,
                    purpose: .outsideMeetingPoint, embedInNavigation: false,
                    context: MapPlanningContext(hazard: hazard, phase: .simulation), plannedExteriorHandoff: currentHandoff)
            }
        } else {
            Text(model.locale == "es" ? "El plan cambió. Vuelva al ensayo para revisar la ruta actual." :
                model.locale == "vi" ? "Kế hoạch đã thay đổi. Quay lại luyện tập để xem tuyến hiện tại." :
                "The plan changed. Return to rehearsal to review the current route.")
                .font(.callout).padding()
        }
    }

    /// What this stage changed compared with the previous one, in words.
    private var changes: [String] {
        guard let state else { return [] }
        let l = model.localizer
        var out: [String] = []
        let newRooms = state.affectedSpaceIDs.filter { !(previous?.affectedSpaceIDs.contains($0) ?? false) }.compactMap { id in home.space(id).map { _ in HomeScenePresentation.roomLabel(id, in: home) } }
        if !newRooms.isEmpty { out.append(l("ui.scene.newAffected", ["rooms": newRooms.joined(separator: ", ")])) }
        let newPortals = state.affectedPortalIDs.filter { !(previous?.affectedPortalIDs.contains($0) ?? false) }
        if !newPortals.isEmpty { out.append(l("ui.scene.newBlocked", ["count": "\(newPortals.count)"])) }
        if let before = previousRoute?.primary, before != route?.primary {
            out.append(l(route?.primary == nil ? "ui.scene.routeLost" : "ui.scene.routeChanged"))
        }
        return out
    }

    private var sceneFloorID: String? {
        HomeScenePresentation.sceneFloorID(in: home, selected: selectedFloorID, route: route, destinationID: state?.destinationSpaceID)
    }

    var body: some View {
        SectionCard(title: s("Current exercise scene"), systemImage: "house") {
            if home.isFictional { Label(s("Example home"), systemImage: "sparkles").font(.caption.weight(.semibold)) }
            if household.people.count > 1 {
                Picker(s("Person"), selection: Binding(get: { personID ?? household.people.first?.id ?? "" }, set: { personID = $0 })) {
                    ForEach(household.people) { Text($0.localizedLabel(model.localizer)).tag($0.id) }
                }
                .accessibilityIdentifier("rehearsal.person")
            }
            if let occupant, let person = household.people.first(where: { $0.id == occupant.personID }) {
                if occupant.exteriorExitPortalID != nil {
                    Label(model.localizer(occupant.accountedOutside ? "ui.scene.accountedOutside" : "ui.scene.exitedNeedsAccounting",
                                          ["person": person.localizedLabel(model.localizer)]),
                          systemImage: occupant.accountedOutside ? "person.crop.circle.badge.checkmark" : "figure.walk.arrival")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("rehearsal.occupantOutside")
                } else if let roomID = occupant.shelteredSpaceID {
                    Label(model.localizer("ui.scene.reachedShelter", ["person": person.localizedLabel(model.localizer), "room": HomeScenePresentation.roomLabel(roomID, in: home)]),
                          systemImage: "person.fill.checkmark")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("rehearsal.occupantSheltered")
                }
            }
            if home.floors.count > 1 {
                Picker(model.localizer("spatial.floor"), selection: Binding(get: { sceneFloorID ?? "" }, set: { selectedFloorID = $0 })) {
                    ForEach(home.floors) { Text($0.label).tag($0.id) }
                }.accessibilityIdentifier("rehearsal.floor")
            }
            FloorPlanView(home: home, routes: currentPaths, highlightedFloorID: sceneFloorID,
                          highlightedElementID: nil, spatialState: state, selectedRoute: route)
                .frame(height: 300)
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.localizer("ui.scene.newThisStep")).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(changes, id: \.self) { Label($0, systemImage: "arrow.turn.down.right").font(.callout.weight(.semibold)) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("rehearsal.changes")
            }
            if let room = HomeScenePresentation.startingRoom(in: home, route: route) {
                Label(model.localizer("spatial.recorded-start-room", ["room": HomeScenePresentation.roomLabel(room.id, in: home)]), systemImage: "person.crop.circle")
                    .font(.footnote)
            } else if route != nil {
                // Only when this stage has a route request: before the first route there is nothing to contradict later.
                Text(model.localizer("spatial.start-room-unknown")).font(.footnote)
            }
            if state?.hazard == .homeFire && (household.housing.homeType == .apartment || home.connectors.contains { $0.kind == .elevator }) {
                Label(model.localizer("spatial.fire-no-elevators"), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.caution)
                    .accessibilityIdentifier("rehearsal.noElevators")
            }
            if let state {
                Text(state.assumptionKey.map { model.localizer($0) } ?? state.assumption).font(.footnote).foregroundStyle(.secondary)
                if !state.affectedSpaceIDs.isEmpty {
                    Label(state.affectedSpaceIDs.compactMap { id in home.space(id).map { _ in HomeScenePresentation.roomLabel(id, in: home) } }.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
            if let exposed = state?.exposedSpaceIDs, !exposed.isEmpty {
                Label(model.localizer("spatial.window-exposure", ["rooms": exposed.compactMap { id in home.space(id).map { _ in HomeScenePresentation.roomLabel(id, in: home) } }.joined(separator: ", ")]), systemImage: "window.vertical.closed")
                    .font(.footnote)
            }
            if let route {
                if let path = route.primary {
                    Label(path.spaceSequence.map { HomeScenePresentation.roomLabel($0, in: home) }.joined(separator: " → "), systemImage: "figure.walk.departure")
                        .font(.callout.weight(.semibold))
                    Label(model.localizer(HomeScenePresentation.alternativeKey(route)), systemImage: HomeScenePresentation.alternativeSymbol(route))
                        .font(.footnote).foregroundStyle(route.alternativeStatus == .independent ? Theme.accent : Theme.caution)
                        .accessibilityIdentifier("rehearsal.routeRedundancy")
                    if !path.verificationNeeded.isEmpty { Text(model.localizer("spatial.opening.review-required")).font(.footnote) }
                    if let handoff = plannedMapHandoff, let hazard = state?.hazard {
                        let scopeID = model.scopeSessionID
                        NavigationLink {
                            plannedMapDestination(handoff, hazard: hazard, scopeID: scopeID)
                        } label: {
                            Text(mapPlanningLinkTitle(hasMeetingPoint: handoff.meetingPlaceID != nil))
                                .font(.callout.weight(.semibold))
                        }
                        .accessibilityIdentifier("rehearsal.plannedGatheringMap")
                    }
                } else {
                    Label(s(route.noRouteReason == .blockedByScenario ? "No supported route: the starting room or a required connection is affected." : "No supported route from the recorded starting room. Review the layout, destination and this person's access needs."), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            } else if occupant?.exteriorExitPortalID == nil {
                Text(s("No route has been established for this stage.")).font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup(s("Room list")) { HomeRoomListView(home: home, spatialState: state, selectedRoute: route) }
            DisclosureGroup(s("3D layout"), isExpanded: $show3D) {
                if show3D {
                    DollhouseView(home: home, routes: currentPaths, floorID: sceneFloorID, spatialState: state, selectedRoute: route).frame(height: 230)
                    DollhouseKey(home: home, floorID: sceneFloorID, spatialState: state, selectedRoute: route, hasRoutes: currentPaths.contains { path in path.legs.contains { sceneFloorID == nil || $0.floorID == sceneFloorID } })
                }
            }
        }
        .onChange(of: personID) { _, _ in selectedFloorID = nil }
        .onChange(of: state?.stageID) { _, _ in selectedFloorID = nil }
    }
}

struct PracticeBanner: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let text: String
    var body: some View {
        Label(text, systemImage: "figure.walk.motion")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .accessibilityAddTraits(.isHeader)
    }
}

struct ServiceStateGrid: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let snapshot: SimulationSnapshot

    var body: some View {
        let l = model.localizer
        // Problems first, then unknowns, then working: what needs attention is at the top.
        let rank: [ServiceState: Int] = [.unavailable: 0, .degraded: 1, .unknown: 2, .operational: 3]
        let ids = snapshot.services.keys.sorted {
            (rank[snapshot.services[$0] ?? .unknown] ?? 9, ServiceNames.name($0, household: model.household, localizer: model.localizer))
                < (rank[snapshot.services[$1] ?? .unknown] ?? 9, ServiceNames.name($1, household: model.household, localizer: model.localizer))
        }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(ids, id: \.self) { id in
                let state = snapshot.services[id] ?? .unknown
                HStack {
                    Image(systemName: Theme.symbol(for: state)).foregroundStyle(Theme.color(for: state)).accessibilityHidden(true)
                    Text(ServiceNames.name(id, household: model.household, localizer: model.localizer))
                    Spacer()
                    Text(l("common.status.\(state.rawValue)")).foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
            ForEach(snapshot.resources.keys.sorted(), id: \.self) { id in
                let q = snapshot.resources[id]!
                HStack {
                    Image(systemName: "shippingbox").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(ServiceNames.name(id, household: model.household, localizer: model.localizer))
                    Spacer()
                    Text(q.amount.map { ServiceNames.quantity($0, unit: q.unit, localizer: l, countryCode: model.household?.privateLocation?.countryCode) } ?? l("common.status.unknown"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// An event. The current one is large; earlier ones use `TimelineRow`. "Why did this happen?" names the household
/// facts, the events that caused it, and the sources — never raw rule or fact IDs.
struct EventCard: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let event: SimulationEvent
    var isCurrent = false
    var result: RehearsalResult?
    @State private var expanded = false

    var body: some View {
        let l = model.localizer
        let tint = Theme.color(for: event.severity)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(RehearsalPresentation.compactTime(minutes: event.simMinute, localizer: model.localizer))
                    .accessibilityLabel(RehearsalPresentation.spokenTime(minutes: event.simMinute, localizer: model.localizer))
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                if event.severity != .info {
                    StatusPill(text: event.severity == .critical ? l("common.critical") : l("common.caution"),
                               systemImage: Theme.symbol(for: event.severity), tint: tint)
                }
            }
            Text(l(event.titleKey, event.localizedTemplateValues(household: model.household, localizer: model.localizer)))
                .font(isCurrent ? .title3.weight(.bold) : .body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = event.detailKey { Text(l(detail, event.localizedTemplateValues(household: model.household, localizer: model.localizer))).font(.callout) }
            DisclosureGroup(l("common.whyHappened"), isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    if !event.evidence.factIDs.isEmpty {
                        Text(l("ui.basedOn", ["facts": event.evidence.factIDs.map { UnknownNames.describe($0, household: model.household, localizer: model.localizer) }.joined(separator: "; ")]))
                    }
                    let causes = event.evidence.causedByEventIDs.compactMap { id in result?.events.first { $0.id == id } }
                    if !causes.isEmpty {
                        Text(l("ui.causedBy", ["events": causes.map { l($0.titleKey, $0.localizedTemplateValues(household: model.household, localizer: l)) }.joined(separator: "; ")]))
                    }
                    let sources = event.evidence.sourceIDs.compactMap { model.content?.source($0) }
                    if !sources.isEmpty {
                        Text(l("ui.sourcesLine", ["sources": sources.map { "\($0.publisher): \($0.title)" }.joined(separator: "; ")]))
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .font(.footnote.weight(.semibold))
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card, bottomLeadingRadius: Theme.Radius.card)
                .fill(tint).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct TimelineRow: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let event: SimulationEvent
    var result: RehearsalResult?
    @State private var expanded = false

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(RehearsalPresentation.compactTime(minutes: event.simMinute, localizer: model.localizer))
                    .accessibilityLabel(RehearsalPresentation.spokenTime(minutes: event.simMinute, localizer: model.localizer))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: Theme.symbol(for: event.severity)).font(.caption).foregroundStyle(Theme.color(for: event.severity))
                    .accessibilityHidden(true)
                Text(model.localizer(event.titleKey, event.localizedTemplateValues(household: model.household, localizer: model.localizer))).font(.callout).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(model.localizer(expanded ? "spatial.hide-details" : "spatial.show-details"))
        if expanded {
            EventCard(event: event, result: result)
        }
    }
}

struct DecisionCard: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let decision: DecisionPoint
    let onChoose: (String) -> Void

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label(l("common.decision"), systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            Text(l(decision.promptKey)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            // Options look the same: the app never styles a choice as "right" before the household makes it.
            ForEach(decision.options) { option in
                Button { onChoose(option.id) } label: {
                    Text(l(option.labelKey)).multilineTextAlignment(.leading)
                }
                .buttonStyle(.choice)
                .accessibilityIdentifier("decision.option.\(option.id)")
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2))
        .accessibilityElement(children: .contain)
    }
}

struct RouteSummaryView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let routes: [RouteResult]

    var body: some View {
        let l = model.localizer
        SectionCard(title: l("common.practiceRoutes"), systemImage: "figure.walk.departure") {
            if let home = model.home {
                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                    let start = RehearsalPresentation.startingRoom(route.request.startSpaceID, in: home, localizer: l)
                    VStack(alignment: .leading, spacing: 4) {
                        if let p = route.primary {
                            Text(l("ui.route.from", ["start": start, "steps": p.spaceSequence.compactMap { id in home.space(id).map { _ in HomeScenePresentation.roomLabel(id, in: home) } }.joined(separator: " → ")]))
                            switch route.alternativeStatus {
                            case .independent: Text(l("common.route.independent")).font(.footnote).foregroundStyle(.secondary)
                            case .sharesChokepoint: Text(l("common.route.shared")).font(.footnote).foregroundStyle(Theme.caution)
                            case .none: Text(l("common.route.none")).font(.footnote).foregroundStyle(Theme.caution)
                            }
                        } else {
                            Text(l("ui.route.none", ["start": start, "reason": l("plan.route.reason.\((route.noRouteReason ?? .incompleteConnectivity).rawValue)")]))
                                .foregroundStyle(Theme.critical)
                        }
                    }
                    .font(.callout)
                }
                FloorPlanView(home: home, routes: routes.compactMap(\.primary), highlightedFloorID: nil)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .accessibilityLabel(l("spatial.route-scene-summary"))
            }
            Text(l("plan.route.caveat")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DebriefView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false
    @State private var settingUp = false

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let result = model.rehearsal?.result {
                    let recs = Array(result.recommendations.prefix(showAll ? result.recommendations.count : 3))
                    Text(l("ui.debrief.intro")).font(.callout).foregroundStyle(.secondary)
                    SectionCard(title: l("common.topPreparations"), systemImage: "star") {
                        ForEach(recs) { rec in
                            NavigationLink {
                                RecommendationDetailView(recommendation: rec, openPreparations: {
                                    model.pendingTab = RootView.Tab.prepare.rawValue
                                    dismiss()
                                })
                            } label: {
                                RecommendationRow(recommendation: rec)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recommendation.\(rec.actionID)")
                            if rec.id != recs.last?.id { Divider() }
                        }
                        if result.recommendations.count > 3 {
                            Button(showAll ? l("common.showTop3") : l("common.showAll", ["count": "\(result.recommendations.count)"])) { showAll.toggle() }
                                .font(.callout.weight(.semibold))
                                .frame(minHeight: Theme.minTap)
                                .accessibilityIdentifier("debrief.showAll")
                        }
                    }
                    if !result.decisions.isEmpty {
                        SectionCard(title: l("common.yourChoices"), systemImage: "arrow.triangle.branch") {
                            ForEach(result.decisions) { d in
                                if let chosen = result.input.choices[d.id], let option = d.options.first(where: { $0.id == chosen }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(l(d.promptKey)).font(.footnote).foregroundStyle(.secondary)
                                        Text(l(option.labelKey)).font(.body.weight(.semibold))
                                        Text(l(option.feedbackKey)).font(.callout)
                                    }
                                }
                            }
                        }
                    }
                    if !result.unknowns.isEmpty {
                        SectionCard(title: l("common.unconfirmed"), systemImage: "questionmark.circle", tint: Theme.caution) {
                            ForEach(result.unknowns, id: \.self) {
                                IconRow(systemImage: "questionmark", tint: Theme.caution, title: UnknownNames.describe($0, household: model.household, localizer: model.localizer))
                            }
                        }
                    }
                    nextAction
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.debrief"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } } }
        // Pushed inside the debrief's own stack, so there is no sheet on a sheet. Saving replaces the example household.
        .navigationDestination(isPresented: $settingUp) { HouseholdSetupView(mode: .create) }
    }

    /// The debrief ends with a way forward instead of a dead end: the example family offers "Set up my household";
    /// a real household goes straight to its preparation list.
    private var nextAction: some View {
        let l = model.localizer
        return VStack(spacing: Theme.Space.s) {
            if model.household?.isFictional == true {
                Button { settingUp = true } label: { Label(l("ui.debrief.setUpOwn"), systemImage: "person.2.badge.plus") }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("debrief.setUpOwn")
                Text(l("ui.debrief.setUpOwnWhy")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { model.pendingTab = RootView.Tab.prepare.rawValue; dismiss() } label: { Label(l("ui.debrief.goPrepare"), systemImage: "checklist") }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("debrief.goPrepare")
            } else {
                Button { model.pendingTab = RootView.Tab.prepare.rawValue; dismiss() } label: { Label(l("ui.debrief.goPrepare"), systemImage: "checklist") }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("debrief.goPrepare")
            }
        }
        .padding(.top, Theme.Space.s)
    }
}

struct RecommendationRow: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let recommendation: Recommendation
    var body: some View {
        let l = model.localizer
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l(recommendation.titleKey, recommendation.localizedTemplateValues(household: model.household, localizer: l))).font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(l(recommendation.whyKey, recommendation.localizedTemplateValues(household: model.household, localizer: l))).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    .multilineTextAlignment(.leading)
                StatusPill(text: l("common.effort.\(recommendation.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct RecommendationDetailView: View {
    @Environment(AppModel.self) private var model
    let recommendation: Recommendation
    let openPreparations: () -> Void
    @State private var showComparison = false
    @State private var comparing = false

    private var preparation: NextStep? {
        guard let summary = model.nextSteps else { return nil }
        return NextSteps.matchingPreparation(for: recommendation, in: summary)
    }

    var body: some View {
        if let preparation {
            PreparationTaskEditor(step: preparation)
                .toolbar {
                    if preparation.recommendation.tryIntervention != nil {
                        ToolbarItem(placement: .bottomBar) {
                            Button(model.localizer("common.action.tryChange")) {
                                comparing = true
                                Task { showComparison = await model.tryChange(for: preparation); comparing = false }
                            }.disabled(comparing)
                        }
                    }
                }
                // Pushed within the debrief stack: a comparison never opens as a sheet on top of a sheet.
                .navigationDestination(isPresented: $showComparison) { ComparisonView() }
        }
        else {
            ScrollView {
                SectionCard(title: model.localizer("ui.task.changedTitle"), systemImage: "arrow.triangle.2.circlepath") {
                    Text(model.localizer("ui.task.changedBody")).foregroundStyle(.secondary)
                    Text(model.localizer(recommendation.titleKey, recommendation.localizedTemplateValues(household: model.household, localizer: model.localizer)))
                        .font(.headline)
                    Button(action: openPreparations) {
                        Label(model.localizer("ui.debrief.goPrepare"), systemImage: "checklist")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("recommendation.currentPreparations")
                }.padding()
            }
            .background(Theme.background)
        }
    }
}

/// Before and after "Try this change": the same scenario with one change. Hypothetical; the household is unchanged.
struct ComparisonView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let c = model.comparison {
                    Label(l("common.sameScenarioOneChange", ["change": model.actionTitle(c.intervention.actionID)]), systemImage: "wand.and.stars")
                        .font(.callout)
                        .padding(Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    let d = c.diff
                    let empty = d.serviceChanges.isEmpty && d.resolvedRequirements.isEmpty && d.newRequirements.isEmpty
                        && d.resourceChanges.isEmpty && d.addedEventIDs.isEmpty && d.removedEventIDs.isEmpty
                    SectionCard(title: l("common.whatChanged"), systemImage: "arrow.left.arrow.right") {
                        if empty { Text(l("common.noDifference")) }
                        ForEach(d.serviceChanges.keys.sorted(), id: \.self) { id in
                            let states = d.serviceChanges[id] ?? []
                            if states.count == 2 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ServiceNames.name(id, household: model.household, localizer: model.localizer)).font(.body.weight(.semibold))
                                    HStack(spacing: Theme.Space.s) {
                                        StatusPill(text: l("common.status.\(states[0].rawValue)"), systemImage: Theme.symbol(for: states[0]), tint: Theme.color(for: states[0]))
                                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel(l("spatial.becomes"))
                                        StatusPill(text: l("common.status.\(states[1].rawValue)"), systemImage: Theme.symbol(for: states[1]), tint: Theme.color(for: states[1]))
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        ForEach(d.resourceChanges.keys.sorted(), id: \.self) { id in
                            let q = d.resourceChanges[id] ?? []
                            if q.count == 2 {
                                let name = ServiceNames.name(id, household: model.household, localizer: l)
                                let before = q[0].amount.map { ServiceNames.quantity($0, unit: q[0].unit, localizer: l, countryCode: model.household?.privateLocation?.countryCode) } ?? l("common.status.unknown")
                                let after = q[1].amount.map { ServiceNames.quantity($0, unit: q[1].unit, localizer: l, countryCode: model.household?.privateLocation?.countryCode) } ?? l("common.status.unknown")
                                Text("\(name): \(before) → \(after)")
                                    .accessibilityLabel(RehearsalPresentation.transition(name: name, before: before, after: after, localizer: l))
                            }
                        }
                        ForEach(d.resolvedRequirements, id: \.self) {
                            IconRow(systemImage: "checkmark", tint: Theme.success, title: l("common.resolved", ["item": UnknownNames.describe($0, household: model.household, localizer: model.localizer)]))
                        }
                        ForEach(d.newRequirements, id: \.self) {
                            IconRow(systemImage: "exclamationmark.triangle", tint: Theme.caution, title: l("common.newGap", ["item": UnknownNames.describe($0, household: model.household, localizer: model.localizer)]))
                        }
                    }
                    if !d.removedEventIDs.isEmpty || !d.addedEventIDs.isEmpty {
                        SectionCard(title: l("common.events"), systemImage: "list.bullet") {
                            ForEach(d.removedEventIDs, id: \.self) { id in
                                if let e = c.baseline.events.first(where: { $0.id == id }) {
                                    IconRow(systemImage: "minus.circle", tint: Theme.success, title: l(e.titleKey, e.localizedTemplateValues(household: model.household, localizer: l)), subtitle: l("ui.compare.noLonger"))
                                }
                            }
                            ForEach(d.addedEventIDs, id: \.self) { id in
                                if let e = c.modified.events.first(where: { $0.id == id }) {
                                    IconRow(systemImage: "plus.circle", tint: Theme.caution, title: l(e.titleKey, e.localizedTemplateValues(household: model.household, localizer: l)), subtitle: l("ui.compare.new"))
                                }
                            }
                        }
                    }
                    Text(l("ui.compare.footer")).font(.footnote).foregroundStyle(.secondary)
                } else if model.isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.beforeAfter"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } } }
    }
}

extension RehearsalCursor {
    /// The spatial state one revealed event earlier, so a scene can say what this step changed.
    var spatialStateBeforeCursor: SpatialExerciseState? {
        guard revealed > 1 else { return nil }
        let earlier = revealed - 1
        let minute = result.events[earlier - 1].simMinute
        return result.snapshots.last { ($0.revealedEventCount.map { $0 <= earlier } ?? ($0.simMinute <= minute)) }?.spatialState
    }
}
