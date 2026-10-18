import SwiftUI
import DryRunCore

struct RehearseTabView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    static let scenarioIDs = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]
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
        .navigationDestination(for: String.self) { RehearsalView(scenarioID: $0) }
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
                    if let session { clock(session) }
                }
                if let session {
                    if ["home-fire", "flash-flood", "tornado"].contains(scenarioID) {
                        sceneOptions(session)
                        SpatialRehearsalScene(home: session.result.input.home, household: session.result.input.household,
                                              state: session.snapshotAtCursor?.spatialState)
                            .accessibilityIdentifier("rehearsal.scene")
                    }
                    let events = session.visibleEvents
                    if let latest = events.last {
                        EventCard(event: latest, isCurrent: true, result: session.result)
                        changedServices(latest)
                    } else {
                        SectionCard { Text(l("ui.rehearse.ready")).foregroundStyle(.secondary) }
                    }
                    if let decision = session.pendingDecision {
                        DecisionCard(decision: decision) { option in
                            Task { await model.choose(option: option, at: decision.id) }
                        }
                        .id("decision")
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
                        SectionCard(title: l("ui.rehearse.earlier"), systemImage: "clock.arrow.circlepath") {
                            ForEach(events.dropLast().reversed()) { e in TimelineRow(event: e, result: session.result) }
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
            withAnimation { proxy.scrollTo("decision", anchor: .bottom) }
        }
        .onChange(of: session?.revealed) { _, _ in
            if session?.pendingDecision == nil { withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { if let session { controls(session) } }
        .navigationTitle(l("common.scenario.\(scenarioID)"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.rehearsal?.result.input.scenarioID != scenarioID {
                await model.startRehearsal(scenarioID: scenarioID)
                let demo = DemoLaunch.current
                if demo.scenarioID == scenarioID { await model.demoAdvance(demo.step) }
            }
        }
        .sheet(isPresented: $showDebrief) { NavigationStack { DebriefView() } }
    }

    private func sceneOptions(_ session: RehearsalCursor) -> some View {
        DisclosureGroup(s("Exercise starting assumptions")) {
            let home = session.result.input.home
            if scenarioID == "home-fire" {
                Picker(s("Fire starts in one room"), selection: $originID) {
                    Text(s("Use the authored default")).tag("")
                    ForEach(home.spaces) { Text($0.label).tag($0.id) }
                }
            }
            if scenarioID == "flash-flood" {
                Toggle(s("Local household leak exercise"), isOn: $householdLeak)
                Picker(s("Water-affected room (optional)"), selection: $waterEntryID) {
                    Text(s("Regional warning; indoor extent unknown")).tag("")
                    ForEach(home.spaces) { Text($0.label).tag($0.id) }
                }
                Picker(s("Higher refuge to review (optional)"), selection: $refugeID) {
                    Text(s("No refuge established")).tag("")
                    ForEach(home.spaces.filter { $0.kind != .closet }) { Text($0.label).tag($0.id) }
                }
            }
            ForEach(session.result.input.household.people) { person in
                Picker(model.localizer("spatial.start-person", ["name": person.alias]), selection: Binding(get: { daytimeStarts[person.id] ?? "" }, set: { daytimeStarts[person.id] = $0 })) {
                    Text(s("Use recorded assignment")).tag("")
                    ForEach(home.spaces) { Text($0.label).tag($0.id) }
                }
            }
            Button(s("Restart with these assumptions")) {
                var variants = session.result.input.variants.filter { !$0.hasPrefix("origin:") && !$0.hasPrefix("waterEntry:") && !$0.hasPrefix("refuge:") && !$0.hasPrefix("start:") && $0 != "householdLeak" }
                if !originID.isEmpty { variants.append("origin:\(originID)") }
                if !waterEntryID.isEmpty { variants.append("waterEntry:\(waterEntryID)") }
                if !refugeID.isEmpty { variants.append("refuge:\(refugeID)") }
                if householdLeak { variants.append("householdLeak") }
                for key in daytimeStarts.keys.sorted() { if let room = daytimeStarts[key], !room.isEmpty { variants.append("start:\(key)|\(room)") } }
                Task { await model.startRehearsal(scenarioID: scenarioID, variants: variants) }
            }
        }
        .font(.callout)
        .accessibilityIdentifier("rehearsal.assumptions")
    }

    private func clock(_ session: RehearsalCursor) -> some View {
        let minute = session.currentMinute
        let text = String(format: "+%dh %02dm", minute / 60, minute % 60)
        return Label(model.localizer("common.simClock", ["time": text]), systemImage: "clock")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Exercise time \(minute / 60) hours \(minute % 60) minutes after the scenario starts")
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
                Task { await model.startRehearsal(scenarioID: scenarioID, variants: session.result.input.variants) }
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
            Button { model.rehearsal?.advance() } label: {
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
    @State private var personID: String?
    @State private var show3D = false
    @State private var selectedFloorID: String?
    private var route: RouteResult? { state?.routes.first { $0.request.personID == (personID ?? household.people.first?.id) } }

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
            if home.floors.count > 1 {
                Picker(model.localizer("spatial.floor"), selection: Binding(get: { sceneFloorID ?? "" }, set: { selectedFloorID = $0 })) {
                    ForEach(home.floors) { Text($0.label).tag($0.id) }
                }.accessibilityIdentifier("rehearsal.floor")
            }
            FloorPlanView(home: home, routes: route?.primary.map { [$0] } ?? [], highlightedFloorID: sceneFloorID,
                          highlightedElementID: state?.destinationSpaceID, spatialState: state, selectedRoute: route).frame(height: 260)
            if let room = HomeScenePresentation.startingRoom(in: home, route: route) {
                Label(model.localizer("spatial.recorded-start-room", ["room": room.label]), systemImage: "person.crop.circle")
                    .font(.footnote)
            } else { Text(model.localizer("spatial.start-room-unknown")).font(.footnote) }
            if let state {
                Text(state.assumptionKey.map { model.localizer($0) } ?? state.assumption).font(.footnote).foregroundStyle(.secondary)
                if !state.affectedSpaceIDs.isEmpty {
                    Label(state.affectedSpaceIDs.compactMap { home.space($0)?.label }.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
            if let exposed = state?.exposedSpaceIDs, !exposed.isEmpty {
                Label(model.localizer("spatial.window-exposure", ["rooms": exposed.compactMap { home.space($0)?.label }.joined(separator: ", ")]), systemImage: "window.vertical.closed")
                    .font(.footnote)
            }
            if let route {
                if let path = route.primary {
                    Text(path.spaceSequence.compactMap { id in
                        guard let room = home.space(id) else { return nil }
                        let floor = home.floors.first(where: { $0.id == room.floorID })?.label ?? ""
                        return home.floors.count > 1 ? "\(room.label) (\(floor))" : room.label
                    }.joined(separator: " → ")).font(.callout.weight(.semibold))
                    if !path.verificationNeeded.isEmpty { Text(s("Some opening measurements still need confirmation.")).font(.footnote) }
                } else {
                    Label(s(route.noRouteReason == .blockedByScenario ? "No supported route: the starting room or a required connection is affected." : "No supported route from the recorded starting room. Review the layout, destination and this person's access needs."), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            } else { Text(s("No route has been established for this stage.")).font(.footnote).foregroundStyle(.secondary) }
            DisclosureGroup(s("Room list")) { HomeRoomListView(home: home, spatialState: state, selectedRoute: route) }
            DisclosureGroup(s("3D layout"), isExpanded: $show3D) {
                if show3D { DollhouseView(home: home, routes: route?.primary.map { [$0] } ?? [], floorID: sceneFloorID, spatialState: state, selectedRoute: route).frame(height: 230) }
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
                    Text(q.amount.map { ServiceNames.quantity($0, unit: q.unit, localizer: l) } ?? l("common.status.unknown"))
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
                Text(String(format: "+%dh %02dm", event.simMinute / 60, event.simMinute % 60))
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                if event.severity != .info {
                    StatusPill(text: event.severity == .critical ? l("common.critical") : l("common.caution"),
                               systemImage: Theme.symbol(for: event.severity), tint: tint)
                }
            }
            Text(l(event.titleKey, event.templateValues))
                .font(isCurrent ? .title3.weight(.bold) : .body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = event.detailKey { Text(l(detail, event.templateValues)).font(.callout) }
            DisclosureGroup(l("common.whyHappened"), isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    if !event.evidence.factIDs.isEmpty {
                        Text(l("ui.basedOn", ["facts": event.evidence.factIDs.map { UnknownNames.describe($0, household: model.household, localizer: model.localizer) }.joined(separator: "; ")]))
                    }
                    let causes = event.evidence.causedByEventIDs.compactMap { id in result?.events.first { $0.id == id } }
                    if !causes.isEmpty {
                        Text(l("ui.causedBy", ["events": causes.map { l($0.titleKey, $0.templateValues) }.joined(separator: "; ")]))
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
                Text(String(format: "+%dh %02dm", event.simMinute / 60, event.simMinute % 60))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Image(systemName: Theme.symbol(for: event.severity)).font(.caption).foregroundStyle(Theme.color(for: event.severity))
                    .accessibilityHidden(true)
                Text(model.localizer(event.titleKey, event.templateValues)).font(.callout).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows details")
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
                    let start = home.space(route.request.startSpaceID)?.label ?? route.request.startSpaceID
                    VStack(alignment: .leading, spacing: 4) {
                        if let p = route.primary {
                            Text(l("ui.route.from", ["start": start, "steps": p.spaceSequence.compactMap { home.space($0)?.label }.joined(separator: " → ")]))
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
                FloorPlanView(home: home, routes: routes.compactMap(\.primary), highlightedFloorID: home.floors.first?.id)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .accessibilityLabel("Floor plan with practice routes. The route is also described in text above.")
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

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let result = model.rehearsal?.result {
                    let recs = Array(result.recommendations.prefix(showAll ? result.recommendations.count : 3))
                    Text(l("ui.debrief.intro")).font(.callout).foregroundStyle(.secondary)
                    SectionCard(title: l("common.topPreparations"), systemImage: "star") {
                        ForEach(recs) { rec in
                            NavigationLink { RecommendationDetailView(recommendation: rec) } label: {
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
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.debrief"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } } }
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
    @State private var showComparison = false
    @State private var comparing = false

    private var preparation: NextStep? {
        let canonical = ["act.backup.confirm-medical-backup": "prep.medicalBackup", "act.medical.document-runtime": "prep.medicalBackup",
            "act.refrigeration.cooler-plan": "prep.coldStorage", "act.water.store-3day": "prep.water", "act.fire.meeting-point": "prep.nearMeetup",
            "act.fire.smoke-alarms": "prep.smokeAlarms", "act.assist.assign-helper": "prep.helper"][recommendation.actionID] ?? recommendation.actionID
        guard let summary = model.nextSteps else { return nil }
        return (summary.toDo + summary.completed).first {
            $0.recommendation.id == recommendation.id
                || ($0.recommendation.actionID == canonical && $0.recommendation.subjectID == recommendation.subjectID)
        }
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
                .sheet(isPresented: $showComparison) { NavigationStack { ComparisonView() } }
        }
        else {
            // A changed household can resolve an old rehearsal gap. The real facts remain editable;
            // a generic Done button never certifies a route or medical compatibility.
            FocusedHouseholdEditor(focus: .supplies)
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
                                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("becomes")
                                        StatusPill(text: l("common.status.\(states[1].rawValue)"), systemImage: Theme.symbol(for: states[1]), tint: Theme.color(for: states[1]))
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        ForEach(d.resourceChanges.keys.sorted(), id: \.self) { id in
                            let q = d.resourceChanges[id] ?? []
                            if q.count == 2 {
                                Text("\(ServiceNames.name(id, household: model.household, localizer: model.localizer)): \(q[0].amount.map { ServiceNames.quantity($0, unit: q[0].unit, localizer: l) } ?? l("common.status.unknown")) → \(q[1].amount.map { ServiceNames.quantity($0, unit: q[1].unit, localizer: l) } ?? l("common.status.unknown"))")
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
                                    IconRow(systemImage: "minus.circle", tint: Theme.success, title: l(e.titleKey, e.templateValues), subtitle: l("ui.compare.noLonger"))
                                }
                            }
                            ForEach(d.addedEventIDs, id: \.self) { id in
                                if let e = c.modified.events.first(where: { $0.id == id }) {
                                    IconRow(systemImage: "plus.circle", tint: Theme.caution, title: l(e.titleKey, e.templateValues), subtitle: l("ui.compare.new"))
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
