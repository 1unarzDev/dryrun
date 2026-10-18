import SwiftUI
import DryRunCore

/// The first tab: what this household should do next, merged across all six rehearsals. Concrete items only —
/// to do, done, or still unknown. No score, no percentage (docs/FRONTEND_HANDOFF.md §3).
struct NextStepsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    /// One sheet slot (several `.sheet` modifiers on one view can fail to present right after another closes).
    @State private var sheet: Sheet?
    enum Sheet: String, Identifiable { case card, share, household, home, contacts, supplies; var id: String { rawValue } }
    var openRehearse: () -> Void = {}

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                if let summary = model.nextSteps {
                    toDo(summary)
                    quickActions
                    questions(summary)
                    done(summary)
                } else {
                    SectionCard {
                        HStack(spacing: Theme.Space.m) {
                            ProgressView()
                            Text(l("ui.next.loading")).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(l("ui.next.footer")).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.tab.prepare"))
        .navigationDestination(for: NextStep.self) { PreparationTaskEditor(step: $0) }
        .task(id: model.currentKey) { await model.refreshNextSteps() }
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .card: OutageCardView()
                case .share: ShareWithFamilyView()
                case .household: FocusedHouseholdEditor(focus: .family)
                case .home: HomeTabView()
                case .contacts: FocusedHouseholdEditor(focus: .contacts)
                case .supplies: FocusedHouseholdEditor(focus: .supplies)
                }
            }
        }
    }

    private var header: some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let h = model.household {
                Text(h.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            if model.household?.isFictional == true { StatusPill(text: l("family.example"), systemImage: "house", tint: Theme.caution) }
            Text(l("ui.next.headline")).font(.title2.weight(.bold))
            Text(l("ui.next.subhead")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var quickActions: some View {
        let l = model.localizer
        return SectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { familyHomeButtons }
                VStack(alignment: .leading, spacing: Theme.Space.s) { familyHomeButtons }
            }
            Divider()
            Button { sheet = .card } label: { Label(l("ui.card.open"), systemImage: "person.text.rectangle") }
                .accessibilityIdentifier("next.outageCard")
                .frame(minHeight: Theme.minTap)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { contactSupplyButtons }
                VStack(alignment: .leading, spacing: Theme.Space.s) { contactSupplyButtons }
            }
        }
    }
    @ViewBuilder private var familyHomeButtons: some View {
        Button { sheet = .household } label: { Label(model.localizer("family.edit"), systemImage: "person.2.fill") }
            .accessibilityIdentifier("next.family").frame(minHeight: Theme.minTap)
        Button { sheet = .home } label: { Label(model.localizer("family.home"), systemImage: "house.fill") }
            .accessibilityIdentifier("next.home").frame(minHeight: Theme.minTap)
    }
    @ViewBuilder private var contactSupplyButtons: some View {
        Button { sheet = .contacts } label: { Label(model.localizer("prep.contact.title"), systemImage: "person.crop.circle.badge.plus") }
            .accessibilityIdentifier("next.contacts").frame(minHeight: Theme.minTap)
        Button { sheet = .supplies } label: { Label(model.localizer("family.supplies"), systemImage: "checklist") }
            .accessibilityIdentifier("next.supplies").frame(minHeight: Theme.minTap)
    }

    @ViewBuilder
    private func toDo(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        let shown = showAll ? summary.toDo : Array(summary.toDo.prefix(3))
        SectionCard(title: l("ui.next.doNext") + " (\(summary.toDo.count))", systemImage: "list.bullet.clipboard") {
            if summary.toDo.isEmpty {
                Text(l("ui.next.nothingLeft")).foregroundStyle(.secondary)
            }
            ForEach(shown) { step in
                NavigationLink(value: step) { NextStepRow(step: step, isPrimary: step.id == shown.first?.id) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next.step.\(step.id)")
                if step.id != shown.last?.id { Divider() }
            }
            if summary.toDo.count > 3 {
                Button(showAll ? l("ui.showFewer") : l("common.showAll", ["count": "\(summary.toDo.count)"])) { showAll.toggle() }
                    .font(.callout.weight(.semibold))
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("next.showAll")
            }
        }
    }

    @ViewBuilder
    private func questions(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        if !summary.unknownFacts.isEmpty {
            SectionCard(title: l("ui.next.questions"), systemImage: "questionmark.circle", tint: Theme.caution) {
                Text(l("ui.next.questionsWhy")).font(.footnote).foregroundStyle(.secondary)
                ForEach(summary.unknownFacts.prefix(6), id: \.self) { id in
                    IconRow(systemImage: "questionmark", tint: Theme.caution,
                            title: UnknownNames.describe(id, household: model.household))
                }
                Button { sheet = .household } label: { Label(l("ui.next.answer"), systemImage: "square.and.pencil") }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("next.answerQuestions")
            }
        }
    }

    @ViewBuilder
    private func done(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        if !summary.completed.isEmpty {
            SectionCard(title: l("ui.next.done"), systemImage: "checkmark.circle", tint: Theme.success) {
                ForEach(summary.completed) { step in
                    IconRow(systemImage: "checkmark", tint: Theme.success,
                            title: l(step.recommendation.titleKey, step.recommendation.localizedTemplateValues(household: model.household, localizer: l)),
                            subtitle: step.completedAt.map { l("ui.next.doneOn", ["date": $0.formatted(date: .abbreviated, time: .omitted)]) })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("next.completedSection")
        }
    }
}

/// Icon over a short label: two of these sit side by side without wrapping awkwardly.
struct QuickTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, Theme.Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
        .contentShape(Rectangle())
    }
}

struct NextStepRow: View {
    @Environment(AppModel.self) private var model
    let step: NextStep
    var isPrimary = false

    var body: some View {
        let l = model.localizer
        let r = step.recommendation
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: r.tier == .unmetEssentialRequirement ? "exclamationmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(l(r.titleKey, r.localizedTemplateValues(household: model.household, localizer: l))).font(isPrimary ? .title3.weight(.bold) : .body.weight(.semibold)).multilineTextAlignment(.leading)
                Text(l(r.whyKey, r.localizedTemplateValues(household: model.household, localizer: l))).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                // Side by side when they fit; stacked at large text sizes instead of pushing the row off screen.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                        ScenarioIcons(ids: step.scenarioIDs)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                        ScenarioIcons(ids: step.scenarioIDs)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Small scenario symbols, with the scenario names for VoiceOver.
struct ScenarioIcons: View {
    @Environment(AppModel.self) private var model
    let ids: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ids, id: \.self) { id in
                Image(systemName: RehearseTabView.symbols[id] ?? "circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(ids.map { model.localizer("common.scenario.\($0)") }.joined(separator: ", "))
    }
}

/// One next step: why, what it changes, and the two clearly different actions — "Try this change" (hypothetical)
/// and "Mark completed" (a real-world record).
struct NextStepDetailView: View {
    @Environment(AppModel.self) private var model
    let step: NextStep
    @State private var showComparison = false
    @State private var tryFailed = false
    @State private var trying = false
    @State private var editing = false

    var body: some View {
        let l = model.localizer
        let r = step.recommendation
        let completed = model.household?.completedPreparations.contains { $0.taskID == r.id } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(l(r.titleKey, r.localizedTemplateValues(household: model.household, localizer: l))).font(.title2.weight(.bold))
                ViewThatFits(in: .horizontal) {
                    HStack { StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                             ScenarioIcons(ids: step.scenarioIDs) }
                    VStack(alignment: .leading) { StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                                                  ScenarioIcons(ids: step.scenarioIDs) }
                }
                SectionCard(title: l("common.why"), systemImage: "lightbulb") {
                    Text(l(r.whyKey, r.localizedTemplateValues(household: model.household, localizer: l)))
                    if !r.matchedFactIDs.isEmpty {
                        Text(l("ui.basedOn", ["facts": r.matchedFactIDs.map { UnknownNames.describe($0, household: model.household) }.joined(separator: "; ")]))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let effect = r.modeledEffectKey {
                    SectionCard(title: l("common.whatChanges"), systemImage: "arrow.triangle.2.circlepath") { Text(l(effect, r.localizedTemplateValues(household: model.household, localizer: l))) }
                }
                if !r.unconfirmed.isEmpty || !r.feasibilityNotes.isEmpty {
                    SectionCard(title: l("common.unconfirmed"), systemImage: "questionmark.circle", tint: Theme.caution) {
                        ForEach(r.unconfirmed, id: \.self) { Text(UnknownNames.describe($0, household: model.household)) }
                        ForEach(r.feasibilityNotes, id: \.self) { Text(l($0)) }
                    }
                }
                SourcesCard(sourceIDs: r.sourceIDs)
                VStack(spacing: Theme.Space.s) {
                    Button { editing = true } label: { Label(editorTitle, systemImage: "square.and.pencil") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("next.editFact")
                    if r.tryIntervention != nil {
                        Button {
                            trying = true
                            Task {
                                let ok = await model.tryChange(for: step)
                                trying = false
                                tryFailed = !ok
                                showComparison = ok
                            }
                        } label: {
                            if trying { ProgressView().tint(Theme.onAccent) } else {
                                Label(l("common.action.tryChange"), systemImage: "wand.and.stars")
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(trying)
                        .accessibilityIdentifier("next.tryChange")
                        if tryFailed {
                            Text(l("ui.tryFailed")).font(.footnote).foregroundStyle(Theme.caution)
                        }
                    }
                    if completed {
                        Button(l("family.reopen")) { Task { await model.reopenPreparation(step.id) } }
                            .buttonStyle(.secondary)
                    }
                    Text(l("common.tryVsDone")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.preparation"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showComparison) { NavigationStack { ComparisonView() } }
        .sheet(isPresented: $editing) { NavigationStack { taskEditor } }
    }
    private var editorTitle: String {
        let id = step.recommendation.actionID
        if id.contains("contact") || id.contains("Contact") { return model.localizer("prep.contact.title") }
        if id.contains("Meetup") || id.contains("meeting") { return model.localizer("family.nearMeetup") }
        return model.localizer("family.preparation")
    }
    private var taskEditor: some View { PreparationTaskEditor(step: step) }

}

struct PreparationTaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let step: NextStep
    @ViewBuilder var body: some View {
        let r = step.recommendation
        let id = r.actionID
        if id.contains("contact") || id.contains("Contact") { FocusedHouseholdEditor(focus: .contacts) }
        else if id.contains("Meetup") || id.contains("meeting") {
            if let store = model.regionalResources { MapPlanningView(store: store, purpose: id.lowercased().contains("backup") ? .backupMeetingPlace : .outsideMeetingPoint, dismissAfterSave: true) }
            else if let content = model.content { MapPlanningView(content: content, client: model.publicClient, regionID: model.household?.regionID ?? "", purpose: id.lowercased().contains("backup") ? .backupMeetingPlace : .outsideMeetingPoint, dismissAfterSave: true) }
        }
        else if let subject = r.subjectID, subject.hasPrefix("equipment.") { MedicalSetupView(equipmentID: String(subject.dropFirst("equipment.".count))) }
        else if r.subjectID?.hasPrefix("backup.") == true || id.contains("generator") { FocusedHouseholdEditor(focus: .backups) }
        else if id == "prep.transport" || id.contains("relocation") || id.contains("sturdy-building") { FocusedHouseholdEditor(focus: .transport) }
        else if (id.contains("exit") || id.contains("shelter")), let home = model.home {
            ManualHomeEditorView(home: home, selectedElementID: spatialSubject(r, in: home)) { candidate in
                Task { if await model.updateHome(candidate) { dismiss() } }
            }
        }
        else if id == "prep.layout" { HomeTabView() }
        else if id == "prep.helper" || id.contains("assign-helper") || id == "prep.reconnect" { FocusedHouseholdEditor(focus: .family) }
        else if id.hasPrefix("prep."), BaselinePreparedness.definitions.contains(where: { "prep." + $0.id == id }) {
            FocusedHouseholdEditor(focus: .preparation(String(id.dropFirst(5))))
        } else { FocusedHouseholdEditor(focus: .supplies) }
    }
    private func spatialSubject(_ recommendation: Recommendation, in home: HomeModel) -> String? {
        if let subject = recommendation.subjectID {
            for prefix in ["room.", "portal.", "space."] where subject.hasPrefix(prefix) {
                let id = String(subject.dropFirst(prefix.count))
                if home.space(id) != nil || home.portal(id) != nil { return id }
            }
        }
        if recommendation.actionID.contains("shelter") {
            return home.annotations.first { $0.kind == .tornadoShelterCandidate }?.spaceID
        }
        // Highlight an existing opening needing review; never invent an alternate exit.
        return home.portals.sorted { $0.id < $1.id }.first { $0.verification != .verified && $0.verification != .rejected }?.id
            ?? home.portals.sorted { $0.id < $1.id }.first { $0.sideA == .exterior || $0.sideB == .exterior }?.id
    }
}

/// Source citations as tappable links (publisher — title), falling back to the ID.
struct SourcesCard: View {
    @Environment(AppModel.self) private var model
    let sourceIDs: [String]

    var body: some View {
        if !sourceIDs.isEmpty {
            SectionCard(title: model.localizer("common.sources"), systemImage: "books.vertical") {
                ForEach(sourceIDs, id: \.self) { id in
                    if let s = model.content?.source(id), let url = URL(string: s.url) {
                        Link(destination: url) {
                            Label("\(s.publisher) — \(s.title)", systemImage: "arrow.up.right.square").font(.callout)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(id).font(.callout)
                    }
                }
            }
        }
    }
}
