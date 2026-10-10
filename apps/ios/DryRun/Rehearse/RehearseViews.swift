import SwiftUI
import DryRunCore

struct RehearseTabView: View {
    @Environment(AppModel.self) private var model
    static let scenarioIDs = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]
    static let symbols = ["freeze-power-loss": "snowflake", "heat-grid-strain": "thermometer.sun", "tornado": "tornado",
                          "flash-flood": "water.waves", "home-fire": "flame", "water-outage": "drop.triangle"]

    var body: some View {
        let l = model.localizer
        List {
            Section {
                Label(l("common.practiceDisclaimer"), systemImage: "info.circle")
                    .font(.footnote)
                if !model.capabilities.isOnline {
                    Label(l("common.offline"), systemImage: "wifi.slash").font(.footnote)
                }
            }
            Section(l("common.chooseScenario")) {
                ForEach(Self.scenarioIDs, id: \.self) { id in
                    NavigationLink(value: id) {
                        Label(l("common.scenario.\(id)"), systemImage: Self.symbols[id] ?? "exclamationmark.triangle")
                            .padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("scenario.\(id)")
                }
            }
        }
        .navigationTitle(l("common.tab.rehearse"))
        .navigationDestination(for: String.self) { RehearsalView(scenarioID: $0) }
    }
}

struct RehearsalView: View {
    let scenarioID: String
    @Environment(AppModel.self) private var model
    @State private var showDebrief = false

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PracticeBanner(text: l("common.practiceLabel"))
                if let session = model.rehearsal, session.result.input.scenarioID == scenarioID {
                    clock(session)
                    if let snapshot = session.snapshotAtCursor { ServiceStateGrid(snapshot: snapshot) }
                    ForEach(session.visibleEvents.reversed()) { EventCard(event: $0) }
                    if let decision = session.pendingDecision {
                        DecisionCard(decision: decision) { option in
                            Task { await model.choose(option: option, at: decision.id) }
                        }
                    }
                    controls(session)
                    if !session.result.routes.isEmpty {
                        RouteSummaryView(routes: session.result.routes)
                    }
                } else if model.isWorking {
                    ProgressView()
                } else {
                    Button(l("common.action.start")) { Task { await model.startRehearsal(scenarioID: scenarioID) } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding()
        }
        .background(Theme.background)
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

    private func clock(_ session: RehearsalCursor) -> some View {
        let minute = session.currentMinute
        let text = String(format: "+%dh %02dm", minute / 60, minute % 60)
        return Label(model.localizer("common.simClock", ["time": text]), systemImage: "clock")
            .font(.headline.monospacedDigit())
            .accessibilityLabel("Exercise time \(minute / 60) hours \(minute % 60) minutes after the scenario starts")
    }

    private func controls(_ session: RehearsalCursor) -> some View {
        let l = model.localizer
        return HStack {
            Button(l("common.action.advance"), systemImage: "forward.frame") {
                model.rehearsal?.advance()
            }
            .accessibilityIdentifier("rehearsal.next")
            .disabled(session.pendingDecision != nil || session.revealed >= session.result.events.count)
            Button(l("common.action.replay"), systemImage: "arrow.counterclockwise") {
                Task { await model.startRehearsal(scenarioID: scenarioID, variants: session.result.input.variants) }
            }
            Spacer()
            Button(l("common.debrief"), systemImage: "list.bullet.clipboard") { showDebrief = true }
                .accessibilityIdentifier("rehearsal.debrief")
                .buttonStyle(.borderedProminent)
                .disabled(!session.isFinished)
        }
        .buttonStyle(.bordered)
    }
}

struct PracticeBanner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "figure.walk.motion")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .accessibilityAddTraits(.isHeader)
    }
}

struct ServiceStateGrid: View {
    @Environment(AppModel.self) private var model
    let snapshot: SimulationSnapshot

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: 6) {
            ForEach(snapshot.services.keys.sorted(), id: \.self) { id in
                let state = snapshot.services[id] ?? .unknown
                HStack {
                    Image(systemName: Theme.symbol(for: state)).foregroundStyle(Theme.color(for: state))
                    Text(ServiceNames.name(id, household: model.household))
                    Spacer()
                    Text(l("common.status.\(state.rawValue)")).foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
            ForEach(snapshot.resources.keys.sorted(), id: \.self) { id in
                let q = snapshot.resources[id]!
                HStack {
                    Image(systemName: "shippingbox")
                    Text(ServiceNames.name(id, household: model.household))
                    Spacer()
                    Text(q.amount.map { "\(PlanFormatting.number($0)) \(q.unit)" } ?? l("common.status.unknown"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

enum ServiceNames {
    static let names = [
        "svc.grid": "Grid power", "svc.heat": "Heat", "svc.cooling": "Cooling", "svc.refrigeration": "Refrigeration",
        "svc.wellPump": "Well pump", "svc.water.supply": "Water supply", "svc.water.safety": "Water safety",
        "svc.wifi": "Home Wi-Fi", "svc.cellular": "Cell service", "svc.handset": "Phone battery", "svc.roads": "Roads",
        "svc.transport": "Transport", "res.water.stored": "Stored water", "res.handset.charge": "Phone charge",
        "res.food.days": "Food", "res.handset.hours": "Phone battery time",
        "res.handset.powerBankCharges": "Power bank charges", "svc.power.home": "Home power", "svc.alerts": "Warnings received",
        "svc.destination": "Place to go", "svc.relocated": "Relocated", "svc.water.municipal": "City water supply",
        "svc.water.utilitySafety": "Utility water safety", "svc.water.wellSafety": "Well water safety",
        "svc.wellPump.mechanical": "Well pump (equipment)", "svc.internet": "Internet",
    ]
    /// Device and backup IDs become the labels the household gave them; raw IDs never reach the screen.
    static func name(_ id: String, household: HouseholdProfile?) -> String {
        if let n = names[id] { return n }
        if id.hasPrefix("svc.device.") { return HouseholdLabels.equipment(String(id.dropFirst("svc.device.".count)), in: household) }
        if id.hasPrefix("res.backup.") {
            return "Backup energy: \(HouseholdLabels.backup(String(id.dropFirst("res.backup.".count)), in: household))"
        }
        if id.hasPrefix("res.device."), id.hasSuffix(".runtime") {
            let eid = String(id.dropFirst("res.device.".count).dropLast(".runtime".count))
            return "\(HouseholdLabels.equipment(eid, in: household)) runtime"
        }
        return UnknownNames.fallback(id)
    }
}

/// Household-given names for equipment and backup sources, looked up by ID.
enum HouseholdLabels {
    static func equipment(_ id: String, in household: HouseholdProfile?) -> String {
        household?.equipment.first { $0.id == id }?.label ?? "Essential device"
    }
    static func backup(_ id: String, in household: HouseholdProfile?) -> String {
        household?.backupPower.first { $0.id == id }?.label ?? "backup power source"
    }
}

enum PlanFormatting {
    static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

struct EventCard: View {
    @Environment(AppModel.self) private var model
    let event: SimulationEvent
    @State private var expanded = false

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "+%dh %02dm", event.simMinute / 60, event.simMinute % 60))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if event.severity != .info {
                    Text(event.severity == .critical ? l("common.critical") : l("common.caution"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: event.severity))
                }
            }
            Text(l(event.titleKey, event.templateValues)).font(.body.weight(.semibold))
            if let detail = event.detailKey { Text(l(detail, event.templateValues)).font(.callout) }
            DisclosureGroup(l("common.whyHappened"), isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rule: \(event.evidence.ruleID)")
                    if !event.evidence.factIDs.isEmpty { Text("Household facts: \(event.evidence.factIDs.joined(separator: ", "))") }
                    if !event.evidence.causedByEventIDs.isEmpty { Text("Caused by: \(event.evidence.causedByEventIDs.joined(separator: ", "))") }
                    if !event.evidence.sourceIDs.isEmpty { Text("Sources: \(event.evidence.sourceIDs.joined(separator: ", "))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.color(for: event.severity)).frame(width: 4).clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

struct DecisionCard: View {
    @Environment(AppModel.self) private var model
    let decision: DecisionPoint
    let onChoose: (String) -> Void

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: 10) {
            Label(l("common.decision"), systemImage: "arrow.triangle.branch").font(.caption.weight(.semibold))
            Text(l(decision.promptKey)).font(.headline)
            ForEach(decision.options) { option in
                Button { onChoose(option.id) } label: {
                    Text(l(option.labelKey)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("decision.option.\(option.id)")
            }
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

struct RouteSummaryView: View {
    @Environment(AppModel.self) private var model
    let routes: [RouteResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.localizer("common.practiceRoutes")).font(.headline)
            if let home = model.home {
                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                    let start = home.space(route.request.startSpaceID)?.label ?? route.request.startSpaceID
                    if let p = route.primary {
                        Text("From \(start): \(p.spaceSequence.compactMap { home.space($0)?.label }.joined(separator: " → ")) → outside")
                        switch route.alternativeStatus {
                        case .independent: Text(model.localizer("common.route.independent")).foregroundStyle(.secondary)
                        case .sharesChokepoint: Text(model.localizer("common.route.shared")).foregroundStyle(Theme.caution)
                        case .none: Text(model.localizer("common.route.none")).foregroundStyle(Theme.caution)
                        }
                    } else {
                        Text("From \(start): no verified route (\(model.localizer("plan.route.reason.\((route.noRouteReason ?? .incompleteConnectivity).rawValue)")))")
                            .foregroundStyle(Theme.critical)
                    }
                }
                FloorPlanView(home: home, routes: routes.compactMap(\.primary), highlightedFloorID: home.floors.first?.id)
                    .frame(height: 260)
                    .accessibilityLabel("Floor plan with practice routes. The route is also described in text above.")
            }
            Text(model.localizer("plan.route.caveat")).font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DebriefView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false

    var body: some View {
        let l = model.localizer
        List {
            if let result = model.rehearsal?.result {
                Section(l("common.yourChoices")) {
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
                Section(l("common.topPreparations")) {
                    ForEach(result.recommendations.prefix(showAll ? result.recommendations.count : 3)) { rec in
                        NavigationLink { RecommendationDetailView(recommendation: rec) } label: {
                            RecommendationRow(recommendation: rec)
                        }
                        .accessibilityIdentifier("recommendation.\(rec.actionID)")
                    }
                    if result.recommendations.count > 3 {
                        Button(showAll ? l("common.showTop3") : l("common.showAll", ["count": "\(result.recommendations.count)"])) { showAll.toggle() }
                            .accessibilityIdentifier("debrief.showAll")
                    }
                }
                if !result.unknowns.isEmpty {
                    Section(l("common.unconfirmed")) {
                        ForEach(result.unknowns, id: \.self) { Text(UnknownNames.describe($0, household: model.household)) }
                    }
                }
            }
        }
        .navigationTitle(l("common.debrief"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } } }
    }
}

/// Plain-language names for the household facts a rehearsal or preparation depends on (IDs from the core engine).
enum UnknownNames {
    static let names = [
        "housing.heatingNeedsElectricity": "Whether your heating needs electricity",
        "housing.heatingFuel": "What fuel your heating uses",
        "housing.cooling": "How your home is cooled",
        "housing.homeType": "Your type of home",
        "housing.waterSource": "Where your water comes from",
        "housing.wellPumpElectric": "Whether your well pump needs electricity",
        "housing.wellPressureTankGallons": "How much water your well pressure tank holds",
        "supplies.storedWaterGallons": "How much water you have stored",
        "supplies.coolerAndIcePacks": "Whether you have a cooler and ice packs",
        "pets.waterNeeds": "How much water your pets need",
        "home.smokeAlarms": "Whether your smoke alarms work",
        "home.portals": "Your home's doors and windows",
        "home.spaces": "Your home's rooms",
        "home.annotations": "Your meeting point and shelter spot",
        "people.needs.usesWheelchair": "Whether someone uses a wheelchair",
        "communications.batteryOrCrankRadio": "Whether you have a battery or crank radio",
        "communications.handsetRuntimeHours": "How long your phones last on battery",
        "communications.powerBankCharges": "How many phone charges your power banks hold",
        "communications.routerOnBackup": "Whether your internet router has backup power",
    ]

    static func describe(_ id: String, household: HouseholdProfile?) -> String {
        if let n = names[id] { return n }
        let parts = id.split(separator: ".", maxSplits: 2).map(String.init)
        if parts.count >= 2, parts[0] == "equipment" {
            let device = HouseholdLabels.equipment(parts[1], in: household)
            switch parts.count > 2 ? parts[2] : "" {
            case "backup": return "A backup that works with \(device)"
            case "runtime", "documentedBackupRuntimeHours": return "How long \(device) runs on its backup"
            case "backupOutcome": return "Whether \(device)'s backup lasts through the outage"
            default: return device
            }
        }
        if parts.count >= 2, parts[0] == "backup" {
            let backup = HouseholdLabels.backup(parts[1], in: household)
            switch parts.count > 2 ? parts[2] : "" {
            case "setupConfirmed": return "Whether \(backup) is set up and tested"
            case "usableEnergyWh": return "How much energy \(backup) holds"
            case "safeOutdoorPlacementConfirmed": return "A safe outdoor spot for \(backup)"
            default: return backup
            }
        }
        if parts.count >= 2, parts[0] == "person" {
            let name = household?.people.first { $0.id == parts[1] }?.alias ?? "A household member"
            switch parts.count > 2 ? parts[2] : "" {
            case "sleepingSpaceID": return "Where \(name) sleeps"
            case "helperPersonID": return "Who helps \(name)"
            case "needs": return "What \(name) needs"
            default: return name
            }
        }
        return ServiceNames.names[id] ?? fallback(id)
    }

    /// Last resort for an ID with no name yet: the final segment, de-camel-cased ("routerOnBackup" → "router on backup").
    static func fallback(_ id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        let spaced = last.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}

struct RecommendationRow: View {
    @Environment(AppModel.self) private var model
    let recommendation: Recommendation
    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: 4) {
            Text(l(recommendation.titleKey, recommendation.templateValues)).font(.body.weight(.semibold))
            Text(l(recommendation.whyKey, recommendation.templateValues)).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            Text(l("common.effort.\(recommendation.effort.rawValue)")).font(.caption).foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

struct RecommendationDetailView: View {
    @Environment(AppModel.self) private var model
    let recommendation: Recommendation
    @State private var showComparison = false
    @State private var tryFailed = false
    @State private var explanation: String?

    var body: some View {
        let l = model.localizer
        let r = recommendation
        let completed = model.household?.completedPreparations.contains { $0.actionID == r.actionID } ?? false
        List {
            Section { Text(l(r.titleKey, r.templateValues)).font(.title3.weight(.semibold)) }
            Section(l("common.why")) {
                Text(l(r.whyKey, r.templateValues))
                if let explanation { Text(explanation).font(.callout).foregroundStyle(.secondary) }
                if !r.matchedFactIDs.isEmpty {
                    Text("Based on: \(r.matchedFactIDs.map { UnknownNames.describe($0, household: model.household) }.joined(separator: "; "))")
                        .font(.caption)
                }
                let causes = r.causeEventIDs.compactMap { id in model.rehearsal?.result.events.first { $0.id == id } }
                if !causes.isEmpty {
                    Text("Rehearsal events: \(causes.map { l($0.titleKey, $0.templateValues) }.joined(separator: "; "))").font(.caption)
                }
            }
            if let effect = r.modeledEffectKey { Section(l("common.whatChanges")) { Text(l(effect, r.templateValues)) } }
            if !r.unconfirmed.isEmpty || !r.feasibilityNotes.isEmpty {
                Section(l("common.unconfirmed")) {
                    ForEach(r.unconfirmed, id: \.self) { Text(UnknownNames.describe($0, household: model.household)) }
                    ForEach(r.feasibilityNotes, id: \.self) { Text(l($0)) }
                }
            }
            Section(l("common.sources")) {
                ForEach(r.sourceIDs, id: \.self) { id in
                    if let s = model.content?.source(id), let url = URL(string: s.url) {
                        Link("\(id): \(s.publisher) — \(s.title)", destination: url)
                    } else {
                        Text(id)
                    }
                }
            }
            Section {
                if let intervention = r.tryIntervention {
                    Button(l("common.action.tryChange"), systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await model.tryChange(intervention)
                            // Only open the sheet for a comparison that was actually produced.
                            tryFailed = model.comparison == nil
                            showComparison = model.comparison != nil
                        }
                    }
                    .accessibilityIdentifier("recommendation.tryChange")
                    if tryFailed {
                        // Shown here because the app-wide error alert cannot appear over this sheet.
                        Text("Dry Run could not run that comparison. Your household was not changed.")
                            .font(.footnote).foregroundStyle(Theme.caution)
                    }
                }
                Button(completed ? l("common.completed") : l("common.action.markDone"), systemImage: completed ? "checkmark.circle.fill" : "checkmark.circle") {
                    Task { await model.markPreparationCompleted(r.actionID) }
                }
                .disabled(completed)
            } footer: {
                Text(l("common.tryVsDone"))
            }
        }
        .navigationTitle(l("common.preparation"))
        .sheet(isPresented: $showComparison) { NavigationStack { ComparisonView() } }
        .task {
            explanation = await ExplanationService.explain(templateText: l(r.whyKey, r.templateValues), recommendation: r, locale: model.locale)
        }
    }
}

struct ComparisonView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = model.localizer
        List {
            if let c = model.comparison {
                Section {
                    Text(l("common.sameScenarioOneChange", ["change": model.actionTitle(c.intervention.actionID)]))
                        .font(.callout)
                }
                Section(l("common.whatChanged")) {
                    if c.diff.serviceChanges.isEmpty && c.diff.resolvedRequirements.isEmpty && c.diff.newRequirements.isEmpty
                        && c.diff.resourceChanges.isEmpty && c.diff.addedEventIDs.isEmpty && c.diff.removedEventIDs.isEmpty {
                        Text(l("common.noDifference"))
                    }
                    ForEach(c.diff.serviceChanges.keys.sorted(), id: \.self) { id in
                        let states = c.diff.serviceChanges[id] ?? []
                        if states.count == 2 {
                            Text("\(ServiceNames.name(id, household: model.household)): \(l("common.status.\(states[0].rawValue)")) → \(l("common.status.\(states[1].rawValue)"))")
                        }
                    }
                    ForEach(c.diff.resourceChanges.keys.sorted(), id: \.self) { id in
                        let q = c.diff.resourceChanges[id] ?? []
                        if q.count == 2 {
                            Text("\(ServiceNames.name(id, household: model.household)): \(q[0].amount.map(PlanFormatting.number) ?? "unknown") → \(q[1].amount.map(PlanFormatting.number) ?? "unknown") \(q[1].unit)")
                        }
                    }
                    ForEach(c.diff.resolvedRequirements, id: \.self) { Label(l("common.resolved", ["item": UnknownNames.describe($0, household: model.household)]), systemImage: "checkmark") }
                    ForEach(c.diff.newRequirements, id: \.self) { Label(l("common.newGap", ["item": UnknownNames.describe($0, household: model.household)]), systemImage: "exclamationmark.triangle") }
                }
                Section(l("common.events")) {
                    ForEach(c.diff.removedEventIDs, id: \.self) { id in
                        if let e = c.baseline.events.first(where: { $0.id == id }) { Label(l(e.titleKey, e.templateValues), systemImage: "minus.circle") }
                    }
                    ForEach(c.diff.addedEventIDs, id: \.self) { id in
                        if let e = c.modified.events.first(where: { $0.id == id }) { Label(l(e.titleKey, e.templateValues), systemImage: "plus.circle") }
                    }
                }
            } else if model.isWorking {
                ProgressView()
            }
        }
        .navigationTitle(l("common.beforeAfter"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } } }
    }
}
