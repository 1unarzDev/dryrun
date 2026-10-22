import SwiftUI
import DryRunCore

/// The first tab: what this household should do next, merged across all six rehearsals. Concrete items lead —
/// to do, done, or still unknown. The provisional score follows them; it is compiled locally by Core under the
/// versioned draft rubric (DryRun_AI_Implementation_Reference.md §12), with coverage and cap reasons beside it.
struct NextStepsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    @State private var showAllQuestions = false
    @State private var showAllRecorded = false
    @State private var showAbout = false
    @State private var finishSheet: FinishSheet?
    @State private var briefing: FamilyBriefingService.Briefing?
    @State private var writingBriefing = false
    @State private var showBriefing = false
    @State private var briefingSource: BriefingSource?
    var openRehearse: () -> Void = {}

    /// The card essentials a new household fills in from Prepare, each in its focused editor.
    enum FinishSheet: Identifiable {
        case contact, meetup(SavedPlacePurpose)
        var id: String {
            switch self {
            case .contact: "contact"
            case .meetup(let purpose): "meetup-\(purpose.rawValue)"
            }
        }
    }

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                // Wait for the six scenario runs rather than showing a baseline list that reorders a second later.
                if let summary = model.nextSteps, model.nextStepResults != nil {
                    // Progress first, then the next three actions (Beacon demo goal milestone 6).
                    ProgressRingsCard()
                    toDo(summary)
                    if model.preparationAIAvailable { PreparationAICard() }
                } else {
                    SectionCard {
                        HStack(spacing: Theme.Space.m) {
                            ProgressView()
                            Text(l("ui.next.loading")).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                quickActions
                finishCard
                if let summary = model.nextSteps, model.nextStepResults != nil {
                    FamilySummaryCard()
                    familyBriefing
                    SectionCard(title: l("family.supplies"), systemImage: "shippingbox") {
                        NavigationLink { SupplyInventoryView() } label: {
                            Label(l("inventory.title"), systemImage: "shippingbox")
                                .frame(minHeight: Theme.minTap)
                        }.accessibilityIdentifier("next.inventory")
                    }
                    ShoppingEntryCard()
                    WhereToGoEntryCard()
                    ScorecardCard()
                    questions(summary)
                    recorded(summary)
                    done(summary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.tab.prepare"))
        .navigationDestination(for: NextStep.self) { PreparationTaskEditor(step: $0) }
        .sheet(item: $finishSheet) { which in
            switch which {
            case .contact: NavigationStack { FocusedHouseholdEditor(focus: .newContact(.other)) }
            case .meetup(let purpose): MeetingPlaceChooser(purpose: purpose)
            }
        }
        .task(id: model.currentKey) { await model.refreshNextSteps() }
        .task(id: model.scoreKey) { await model.refreshScorecard() }
        .task(id: BriefingRequest(source: briefingKey, expanded: showBriefing)) { await writeBriefing() }
    }

    // MARK: For your family (optional, on-device)

    private var topSteps: [NextStep] { Array((model.nextStepResults == nil ? [] : model.nextSteps?.toDo ?? []).prefix(PlanBriefing.maxSteps)) }
    private struct BriefingSource: Equatable {
        let scopeSessionID: String
        let learningState: Data?
        let revision: RevisionKey?
        let steps: [FamilyBriefingService.StepText]
        let locale: String
    }

    private struct BriefingRequest: Equatable {
        let source: BriefingSource
        let expanded: Bool
    }

    /// Bind prose to the exact source text as well as household, home, content and language revisions.
    private var briefingKey: BriefingSource {
        let l = model.localizer
        let steps = topSteps.map { step -> FamilyBriefingService.StepText in
            let r = step.recommendation
            let values = r.localizedTemplateValues(household: model.household, localizer: l)
            return .init(id: step.id, title: l(r.titleKey, values), why: l(r.whyKey, values))
        }
        return BriefingSource(scopeSessionID: model.scopeSessionID, learningState: model.integratedAIState,
                              revision: model.currentKey, steps: steps, locale: model.locale)
    }

    private func writeBriefing() async {
        guard !Task.isCancelled else { return }
        let source = briefingKey
        if briefingSource != source { briefing = nil; briefingSource = nil }
        writingBriefing = false
        guard showBriefing, let h = model.household, !source.steps.isEmpty,
              FamilyBriefingService.canWrite(locale: source.locale) else { return }
        if briefingSource == source, briefing != nil { return }
        guard !Task.isCancelled else { return }
        defer { if !Task.isCancelled, briefingKey == source { writingBriefing = false } }
        let regionName = model.content?.region(h.regionID)?.name
        writingBriefing = true
        let result = await FamilyBriefingService.write(steps: source.steps, household: h, regionName: regionName, locale: source.locale)
        guard !Task.isCancelled, showBriefing, briefingKey == source else { return }
        writingBriefing = false
        briefingSource = source
        briefing = result
    }

    @ViewBuilder private var familyBriefing: some View {
        let l = model.localizer
        if !model.preparationAIAvailable, !topSteps.isEmpty, FamilyBriefingService.canWrite(locale: model.locale) {
            SectionCard {
                DisclosureGroup(isExpanded: $showBriefing) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                    // The people/equipment roster that used to open this card now lives in FamilySummaryCard,
                    // with implications and a correction route; this card keeps only the written briefing.
                    if writingBriefing {
                        HStack(spacing: Theme.Space.s) { ProgressView(); Text(l("ui.brief.writing")).foregroundStyle(.secondary) }
                    }
                    if briefingSource == briefingKey, let briefing {
                        if let overview = briefing.overview { Text(overview).font(.body) }
                        ForEach(topSteps.filter { briefing.notes[$0.id] != nil }) { step in
                            let r = step.recommendation
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink(value: step) {
                                    Label(l(r.titleKey, r.localizedTemplateValues(household: model.household, localizer: l)),
                                          systemImage: PreparationPresentation.symbol(actionID: r.actionID))
                                        .font(.callout.weight(.semibold))
                                }
                                Text(briefing.notes[step.id] ?? "").font(.callout).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(l("ui.brief.note")).font(.caption).foregroundStyle(.secondary)
                    } else if !writingBriefing {
                        // Authored explanations remain useful when the optional model returns no accepted prose.
                        ForEach(topSteps) { step in
                            let r = step.recommendation
                            let values = r.localizedTemplateValues(household: model.household, localizer: l)
                            VStack(alignment: .leading, spacing: 2) {
                                Label(l(r.titleKey, values), systemImage: PreparationPresentation.symbol(actionID: r.actionID))
                                    .font(.callout.weight(.semibold))
                                Text(l(r.whyKey, values)).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.Space.s)
                } label: {
                    // person.2.fill belongs to the family panel; one symbol per meaning (visual rule 6).
                    Label(l("ui.brief.title"), systemImage: "text.quote").font(.headline)
                }
                .accessibilityIdentifier("next.briefing.expand")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("next.briefing")
        }
    }

    /// Three concrete steps to a card worth printing: a contact with a phone number and the two meeting places.
    /// Shown until all three exist, alongside the focused household/home/card shortcuts.
    @ViewBuilder private var finishCard: some View {
        let l = model.localizer
        if let h = model.household {
            let places = model.savedPlaces.filter { $0.homeID == h.stableHomeID }
            let items: [(sheet: FinishSheet, title: String, done: Bool)] = [
                (.contact, l("ui.card.finishContact"), h.contacts.contains(where: \.hasUsablePhone)),
                (.meetup(.outsideMeetingPoint), l("ui.card.finishNearMeetup"), places.contains { $0.purpose == .outsideMeetingPoint }),
                (.meetup(.backupMeetingPlace), l("ui.card.finishBackupMeetup"), places.contains { $0.purpose == .backupMeetingPlace }),
            ]
            let done = items.filter(\.done).count
            if done < items.count {
                SectionCard(title: l("ui.card.finishTitle"), systemImage: "person.text.rectangle.fill") {
                    Text(l("ui.card.finishProgress", ["done": "\(done)", "total": "\(items.count)"])).font(.footnote).foregroundStyle(.secondary)
                    ForEach(items, id: \.sheet.id) { item in
                        Button { finishSheet = item.sheet } label: {
                            HStack(spacing: Theme.Space.m) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.done ? Theme.success : Theme.accent)
                                    .accessibilityHidden(true)
                                Text(item.title).font(.body.weight(item.done ? .regular : .semibold))
                                    .foregroundStyle(item.done ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                            }
                            .frame(minHeight: Theme.minTap)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(item.done ? l("ui.next.done") : "")
                        .accessibilityIdentifier("next.finish.\(item.sheet.id)")
                    }
                    NavigationLink { OutageCardView() } label: {
                        Label(l("ui.card.openCard"), systemImage: "arrow.right").font(.callout.weight(.semibold))
                    }
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("next.finish.open")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("next.finishCard")
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(l("ui.next.headline")).font(.title2.weight(.bold))
                Spacer(minLength: 0)
                // How the list is built and what it cannot predict, behind ⓘ so the actions lead.
                InfoButton(label: l("ui.next.about"), isExpanded: $showAbout)
                    .accessibilityIdentifier("next.info")
            }
            if showAbout {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(l("ui.next.subhead"))
                    Text(l("ui.next.footer"))
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("next.about")
            }
        }
    }

    /// Three equal entry points, each one transition from the tab root.
    private var quickActions: some View {
        let l = model.localizer
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { tiles }
            VStack(spacing: Theme.Space.s) { tiles }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l("ui.next.shortcuts"))
    }
    @ViewBuilder private var tiles: some View {
        let l = model.localizer
        NavigationLink { FocusedHouseholdEditor(focus: .family) } label: { QuickTile(title: l("family.edit"), systemImage: "person.2.fill") }
            .buttonStyle(.plain).accessibilityIdentifier("next.family")
        NavigationLink { HomeTabView() } label: { QuickTile(title: l("family.home"), systemImage: "house.fill") }
            .buttonStyle(.plain).accessibilityIdentifier("next.home")
        NavigationLink { OutageCardView() } label: { QuickTile(title: l("family.title"), systemImage: "person.text.rectangle.fill") }
            .buttonStyle(.plain).accessibilityIdentifier("next.outageCard")
    }

    @ViewBuilder
    private func toDo(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        let personalization = model.preparationPersonalization
        let ordered = personalization.map { PreparationFeatureBridge.order(summary.toDo, by: $0) } ?? summary.toDo
        let shown = showAll ? ordered : Array(ordered.prefix(Theme.previewCount))
        SectionCard(title: l("ui.next.doNext") + " (\(summary.toDo.count))", systemImage: "list.bullet.clipboard") {
            if summary.toDo.isEmpty {
                Text(l("ui.next.nothingLeft")).foregroundStyle(.secondary)
            }
            ForEach(shown) { step in
                NavigationLink(value: step) { NextStepRow(step: step, isPrimary: step.id == shown.first?.id,
                        aiWhy: personalization?.ranked.first { $0.stepID == step.id }?.why) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next.step.\(step.id)")
                if step.id != shown.last?.id { Divider() }
            }
            ShowAllButton(total: summary.toDo.count, showAll: $showAll)
                .accessibilityIdentifier("next.showAll")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next.actions")
    }

    @ViewBuilder
    private func questions(_ summary: NextStepsSummary) -> some View {
        let l = model.localizer
        if !summary.unknownFacts.isEmpty {
            SectionCard(title: l("ui.next.questions"), systemImage: "questionmark.circle", tint: Theme.caution) {
                Text(l("ui.next.questionsWhy")).font(.footnote).foregroundStyle(.secondary)
                ForEach(showAllQuestions ? summary.unknownFacts : Array(summary.unknownFacts.prefix(Theme.previewCount)), id: \.self) { id in
                    IconRow(systemImage: "questionmark", tint: Theme.caution,
                            title: UnknownNames.describe(id, household: model.household, localizer: l))
                }
                ShowAllButton(total: summary.unknownFacts.count, showAll: $showAllQuestions)
                    .accessibilityIdentifier("next.questions.showAll")
                Text(l("ui.next.answerViaTasks")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func recorded(_ summary: NextStepsSummary) -> some View {
        if !summary.recorded.isEmpty {
            SectionCard(title: model.localizer("family.recordedPreparations"), systemImage: "checkmark.circle", tint: Theme.success) {
                Text(model.localizer("family.recordedExplanation")).font(.footnote).foregroundStyle(.secondary)
                ForEach(showAllRecorded ? summary.recorded : Array(summary.recorded.prefix(Theme.previewCount))) { step in
                    NavigationLink { PreparationTaskEditor(step: step, reviewingRecordedFacts: true) } label: {
                        Label(model.localizer(step.recommendation.titleKey, step.recommendation.localizedTemplateValues(household: model.household, localizer: model.localizer)), systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("next.recorded.\(step.id)")
                }
                ShowAllButton(total: summary.recorded.count, showAll: $showAllRecorded)
                    .accessibilityIdentifier("next.recorded.showAll")
            }
            // .contain keeps each row's own identifier and label; a bare container identifier would replace them.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("next.recordedSection")
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
                    Button(l("family.reopen")) { Task { await model.reopenPreparation(step.id) } }
                        .buttonStyle(.inline)
                        .accessibilityIdentifier("next.reopen.\(step.id)")
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
    var aiWhy: String?

    var body: some View {
        let l = model.localizer
        let r = step.recommendation
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: PreparationPresentation.symbol(actionID: r.actionID))
                .font(.title3)
                .foregroundStyle(r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(l(r.titleKey, r.localizedTemplateValues(household: model.household, localizer: l)))
                    .font(isPrimary ? .title3.weight(.bold) : .body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subjectID = r.subjectID {
                    let values = r.localizedTemplateValues(household: model.household, localizer: l)
                    if let name = values[subjectID.hasPrefix("person.") ? "person" : "device"] { Text(name).font(.subheadline.weight(.semibold)) }
                }
                Text(aiWhy ?? l(r.whyKey, r.localizedTemplateValues(household: model.household, localizer: l))).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                // Side by side when they fit; stacked at large text sizes instead of pushing the row off screen.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                        ScenarioIcons(ids: step.scenarioIDs, urgent: r.tier == .unmetEssentialRequirement)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                        ScenarioIcons(ids: step.scenarioIDs, urgent: r.tier == .unmetEssentialRequirement)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Space.s) {
                if r.tier == .unmetEssentialRequirement {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.critical)
                        .accessibilityLabel(l("common.critical"))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(width: Theme.Space.xl)
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
    var urgent = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ids, id: \.self) { id in
                Image(systemName: RehearseTabView.symbols[id] ?? "circle").font(.caption).foregroundStyle(urgent ? Theme.critical : .secondary)
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
                    HStack { StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                             ScenarioIcons(ids: step.scenarioIDs, urgent: r.tier == .unmetEssentialRequirement) }
                    VStack(alignment: .leading) { StatusPill(text: l("common.effort.\(r.effort.rawValue)"), systemImage: "dollarsign.circle", tint: r.tier == .unmetEssentialRequirement ? Theme.critical : Theme.accent)
                                                  ScenarioIcons(ids: step.scenarioIDs, urgent: r.tier == .unmetEssentialRequirement) }
                }
                SectionCard(title: l("common.why"), systemImage: "lightbulb") {
                    Text(l(r.whyKey, r.localizedTemplateValues(household: model.household, localizer: l)))
                    if !r.matchedFactIDs.isEmpty {
                        Text(l("ui.basedOn", ["facts": r.matchedFactIDs.map { UnknownNames.describe($0, household: model.household, localizer: l) }.joined(separator: "; ")]))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let effect = r.modeledEffectKey {
                    SectionCard(title: l("common.whatChanges"), systemImage: "arrow.triangle.2.circlepath") { Text(l(effect, r.localizedTemplateValues(household: model.household, localizer: l))) }
                }
                if !r.unconfirmed.isEmpty || !r.feasibilityNotes.isEmpty {
                    SectionCard(title: l("common.unconfirmed"), systemImage: "questionmark.circle", tint: Theme.caution) {
                        ForEach(r.unconfirmed, id: \.self) { Text(UnknownNames.describe($0, household: model.household, localizer: l)) }
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
    var reviewingRecordedFacts = false
    @ViewBuilder var body: some View {
        switch PreparationEditTarget.resolve(step.recommendation, home: model.home) {
        case .contact(let role): FocusedHouseholdEditor(focus: reviewingRecordedFacts ? .contacts : .newContact(role))
        case .family(let personID):
            FocusedHouseholdEditor(focus: personID.map { .person($0) } ?? .family)
        case .equipment(let id): MedicalSetupView(equipmentID: id)
        case .backups: FocusedHouseholdEditor(focus: .backups)
        case .meeting(let purpose):
            MeetingPlaceChooser(purpose: purpose, embedInNavigation: false)
        case .transport: FocusedHouseholdEditor(focus: .transport)
        case .home(let elementID):
            if let home = model.home {
                ManualHomeEditorView(home: home, selectedElementID: elementID, savedBaseRevision: model.home?.revision, scopeSessionID: model.scopeSessionID) { candidate, baseRevision, scope in
                    let saved = await model.updateHome(candidate, baseRevision: baseRevision, scopeSessionID: scope)
                    if saved { dismiss() }
                    return saved
                }
            } else { HomeTabView() }
        case .homeSetup: HomeTabView()
        case .review: FocusedHouseholdEditor(focus: .review)
        case .water: FocusedHouseholdEditor(focus: .water)
        case .communications: FocusedHouseholdEditor(focus: .communications)
        case .housing: FocusedHouseholdEditor(focus: .housing)
        case .checklist(let id, let titleKey): FocusedHouseholdEditor(focus: .checklist(id: id, titleKey: titleKey))
        case .supplies: FocusedHouseholdEditor(focus: .supplies)
        }
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

/// The shared map flow for choosing one meeting place. Saving closes it and returns to the initiating task.
struct MeetingPlaceChooser: View {
    @Environment(AppModel.self) private var model
    var purpose: SavedPlacePurpose? = nil
    var embedInNavigation = true
    var dismissAfterSave = true
    var body: some View {
        if let store = model.regionalResources {
            MapPlanningView(store: store, purpose: purpose, dismissAfterSave: dismissAfterSave && purpose != nil, embedInNavigation: embedInNavigation)
        } else if let content = model.content {
            MapPlanningView(content: content, client: model.publicClient, regionID: model.household?.regionID ?? "", purpose: purpose,
                            dismissAfterSave: dismissAfterSave && purpose != nil, embedInNavigation: embedInNavigation)
        }
    }
}
