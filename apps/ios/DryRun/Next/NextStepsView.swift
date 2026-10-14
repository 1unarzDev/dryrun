import SwiftUI
import DryRunCore

/// The first tab: what this household should do next, merged across all six rehearsals. Concrete items only —
/// to do, done, or still unknown. No score, no percentage (docs/FRONTEND_HANDOFF.md §3).
struct NextStepsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    /// One sheet slot (several `.sheet` modifiers on one view can fail to present right after another closes).
    @State private var sheet: Sheet?
    enum Sheet: String, Identifiable { case card, share, household; var id: String { rawValue } }
    var openRehearse: () -> Void = {}

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                quickActions
                if let summary = model.nextSteps {
                    toDo(summary)
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
        .navigationTitle(l("common.tab.next"))
        .navigationDestination(for: NextStep.self) { NextStepDetailView(step: $0) }
        .task(id: model.currentKey) { await model.refreshNextSteps() }
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .card: OutageCardView()
                case .share: ShareWithFamilyView()
                case .household: HouseholdSetupView(mode: .edit)
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
            Text(l("ui.next.headline")).font(.title2.weight(.bold))
            Text(l("ui.next.subhead")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var quickActions: some View {
        let l = model.localizer
        let hasDevices = !(model.household.map(OutageCardBuilder.devices(in:)) ?? []).isEmpty
        return VStack(spacing: Theme.Space.s) {
            if hasDevices {
                Button { sheet = .card } label: {
                    Label(l("ui.card.open"), systemImage: "bolt.heart.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.critical))
                .accessibilityIdentifier("next.outageCard")
            }
            HStack(spacing: Theme.Space.s) {
                Button { openRehearse() } label: { QuickTile(title: l("ui.next.rehearse"), systemImage: "play.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next.rehearse")
                Button { sheet = .share } label: { QuickTile(title: l("ui.share.open"), systemImage: "person.2.wave.2.fill") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next.share")
            }
        }
    }

    @ViewBuilder
    private func toDo(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        let shown = showAll ? summary.toDo : Array(summary.toDo.prefix(4))
        SectionCard(title: l("ui.next.doNext"), systemImage: "list.bullet.clipboard") {
            if summary.toDo.isEmpty {
                Text(l("ui.next.nothingLeft")).foregroundStyle(.secondary)
            }
            ForEach(shown) { step in
                NavigationLink(value: step) { NextStepRow(step: step) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next.step.\(step.id)")
                if step.id != shown.last?.id { Divider() }
            }
            if summary.toDo.count > 4 {
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
                            title: l(step.recommendation.titleKey, step.recommendation.templateValues),
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

    var body: some View {
        let l = model.localizer
        let r = step.recommendation
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: r.tier == .unmetEssentialRequirement ? "exclamationmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(l(r.titleKey, r.templateValues)).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                Text(l(r.whyKey, r.templateValues)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: Theme.Space.s) {
                    StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                    ScenarioIcons(ids: step.scenarioIDs)
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

    var body: some View {
        let l = model.localizer
        let r = step.recommendation
        let completed = model.household?.completedPreparations.contains { $0.actionID == r.actionID } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(l(r.titleKey, r.templateValues)).font(.title2.weight(.bold))
                HStack { StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: Theme.accent)
                         ScenarioIcons(ids: step.scenarioIDs) }
                SectionCard(title: l("common.why"), systemImage: "lightbulb") {
                    Text(l(r.whyKey, r.templateValues))
                    if !r.matchedFactIDs.isEmpty {
                        Text(l("ui.basedOn", ["facts": r.matchedFactIDs.map { UnknownNames.describe($0, household: model.household) }.joined(separator: "; ")]))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let effect = r.modeledEffectKey {
                    SectionCard(title: l("common.whatChanges"), systemImage: "arrow.triangle.2.circlepath") { Text(l(effect, r.templateValues)) }
                }
                if !r.unconfirmed.isEmpty || !r.feasibilityNotes.isEmpty {
                    SectionCard(title: l("common.unconfirmed"), systemImage: "questionmark.circle", tint: Theme.caution) {
                        ForEach(r.unconfirmed, id: \.self) { Text(UnknownNames.describe($0, household: model.household)) }
                        ForEach(r.feasibilityNotes, id: \.self) { Text(l($0)) }
                    }
                }
                SourcesCard(sourceIDs: r.sourceIDs)
                VStack(spacing: Theme.Space.s) {
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
                        .buttonStyle(.primary)
                        .disabled(trying)
                        .accessibilityIdentifier("next.tryChange")
                        if tryFailed {
                            Text(l("ui.tryFailed")).font(.footnote).foregroundStyle(Theme.caution)
                        }
                    }
                    Button {
                        Task { await model.markPreparationCompleted(r.actionID) }
                    } label: {
                        Label(completed ? l("common.completed") : l("common.action.markDone"),
                              systemImage: completed ? "checkmark.seal.fill" : "checkmark.seal")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.success))
                    .disabled(completed)
                    .accessibilityIdentifier("next.markDone")
                    Text(l("common.tryVsDone")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.preparation"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showComparison) { NavigationStack { ComparisonView() } }
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
