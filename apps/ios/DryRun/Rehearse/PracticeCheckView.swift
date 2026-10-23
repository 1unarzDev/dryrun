import SwiftUI
import DryRunCore

/// The optional practice check: four short, separate practice situations in the household's own home. The first
/// answer to each is recorded by the host before any feedback appears; feedback never changes it. It contributes at
/// most 10 points to the provisional score and says nothing about real-world safety. No timing is measured.
struct PracticeCheckView: View {
    @Environment(AppModel.self) private var model
    @State private var receipt: SessionReceipt?
    @State private var actions: [ExerciseActions.Option] = []
    @State private var movePersonID = ""
    @State private var moveRoomID = ""
    @State private var feedback: Feedback?
    @State private var submitting = false
    @State private var loadedIdentity: AppModel.PracticeStepIdentity?

    /// What the family sees after their answer is safely recorded.
    struct Feedback: Equatable {
        let actionID: String
        let attemptID: String
        let scope: String
        let locale: String
        let competency: String
        let title: String
        let detail: String?
        let events: [SimulationEvent]
    }

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PracticeBanner(text: l("practice.banner"))
                if let feedback {
                    feedbackCard(feedback)
                } else if model.pendingPracticeFeedback != nil {
                    SectionCard(title: l("adaptive.youDid"), systemImage: "hand.raised") {
                        Text(l("practice.recorded"))
                        Button(l("native.retry")) { Task { await recoverFeedback() } }
                            .buttonStyle(.primary)
                            .disabled(submitting)
                    }
                } else if let step = model.practiceStep() {
                    question(step)
                } else if let attempt = model.latestPracticeCheck, (attempt.observations?.count ?? 0) >= 4 {
                    finished(attempt)
                } else {
                    intro
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("practice.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.practiceStepIdentity) { await loadStep() }
        .task { model.prefetchPracticePlan() }
        .task(id: model.scoreKey) { await model.refreshScorecard() }
        .onChange(of: model.scopeSessionID) { _, _ in feedback = nil }
        .onChange(of: model.locale) { _, _ in feedback = nil }
    }

    // MARK: Screens

    private var intro: some View {
        let l = model.localizer
        return SectionCard(title: l("practice.title"), systemImage: "checklist.checked") {
            Text(l("practice.intro")).font(.callout)
            Text(l("practice.rules")).font(.footnote).foregroundStyle(.secondary)
            if model.home == nil {
                Label(l("practice.needsHome"), systemImage: "house").font(.callout).foregroundStyle(Theme.caution)
            } else {
                Button(l("practice.start")) { Task { await model.beginPracticeCheck() } }
                    .buttonStyle(.primary)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("practice.start")
            }
        }
    }

    @ViewBuilder private func question(_ step: (attempt: PracticeAttempt, session: SimulationSession, competency: String)) -> some View {
        let l = model.localizer
        let number = (step.attempt.observations?.count ?? 0) + 1
        Label(l("practice.progress", ["number": "\(number)", "total": "4"]), systemImage: "list.number")
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityIdentifier("practice.progress")
        Text(l("practice.separate")).font(.footnote).foregroundStyle(.secondary)
        if let receipt {
            if let home = step.session.initial.home, step.session.initial.scenarioID == "home-fire" {
                SpatialRehearsalScene(home: home, household: step.session.initial.household, state: receipt.snapshot.spatialState,
                                      isFireExercise: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("practice.scene")
            }
            if let situation = receipt.events.last(where: { !$0.id.hasPrefix("user.") }) {
                EventCard(event: situation, isCurrent: true)
            }
            if let planned = model.practicePlanSituation(attempt: step.attempt, index: number - 1) {
                plannedList(planned, step: step, receipt: receipt)
            } else if let scenarios = model.scenarios,
               let choice = PracticeCheckSources.authoredChoice(step.session, competency: step.competency, library: scenarios) {
                let point = DecisionPoint(id: choice.id, simMinute: choice.minute, promptKey: choice.promptKey,
                                          options: choice.options.map { .init(id: $0.id, labelKey: $0.labelKey, feedbackKey: $0.feedbackKey, isRecommended: !$0.unsafe) })
                DecisionCard(decision: point) { option in
                    answer(SessionCommand(kind: "choose", target: choice.id, value: option), step: step)
                }
            } else {
                actionList(step)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    /// practice-phases/3: the options were planned (with every consequence) before the check began, so they show at once.
    @ViewBuilder private func plannedList(_ planned: PracticePlanSituation, step: (attempt: PracticeAttempt, session: SimulationSession, competency: String),
                                          receipt: SessionReceipt) -> some View {
        let l = model.localizer
        SectionCard(title: planned.prompt ?? l("adaptive.whatNow"), systemImage: "arrow.triangle.branch") {
            Text(l("practice.chooseOne")).font(.footnote).foregroundStyle(.secondary)
            ForEach(planned.options, id: \.id) { option in
                Button { answer(option.command, step: step) } label: {
                    Text(option.label ?? ExerciseActions.describe(option.command, session: step.session, receipt: receipt, localizer: l) ?? l("adaptive.action"))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.choice)
                .disabled(submitting)
                .accessibilityIdentifier("practice.option.\(option.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.actions")
    }

    @ViewBuilder private func actionList(_ step: (attempt: PracticeAttempt, session: SimulationSession, competency: String)) -> some View {
        let l = model.localizer
        SectionCard(title: l("adaptive.whatNow"), systemImage: "arrow.triangle.branch") {
            Text(l("practice.chooseOne")).font(.footnote).foregroundStyle(.secondary)
            let household = step.session.initial.household
            let byKey = Dictionary(actions.map { ($0.choiceItem(household, localizer: l).key, $0.commands[0]) }, uniquingKeysWith: { a, _ in a })
            ChoicePicker(items: actions.map { $0.choiceItem(household, localizer: l) }, disabled: submitting) { item in
                if let command = byKey[item.key] { answer(command, step: step) }
            }
            if let home = step.session.initial.home {
                Text(l("adaptive.move")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                PersonRoomPicker(people: household.people, home: home, personID: $movePersonID, roomID: $moveRoomID,
                                 confirmIdentifier: "practice.moveGo",
                                 canConfirm: !(movePersonID.isEmpty || moveRoomID.isEmpty || submitting)) {
                    answer(SessionCommand(kind: "moveTo", target: movePersonID, value: moveRoomID), step: step)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.actions")
    }

    private func feedbackCard(_ feedback: Feedback) -> some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionCard(title: l("adaptive.youDid"), systemImage: "hand.raised", tint: Theme.accent) {
                Text(feedback.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let detail = feedback.detail { Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true) }
                Text(l("practice.recorded")).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("practice.feedback")
            ForEach(feedback.events.reversed()) { TimelineRow(event: $0, result: nil) }
            Button(l("practice.next")) {
                guard !submitting else { return }
                submitting = true
                Task {
                    defer { submitting = false }
                    guard await model.acknowledgePracticeFeedback(attemptID: feedback.attemptID, actionID: feedback.actionID,
                        expectedScope: feedback.scope, expectedLocale: feedback.locale),
                        model.scopeSessionID == feedback.scope, model.locale == feedback.locale else { return }
                    self.feedback = nil
                    movePersonID = ""; moveRoomID = ""
                }
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("practice.next")
        }
    }

    private func finished(_ attempt: PracticeAttempt) -> some View {
        let l = model.localizer
        return SectionCard(title: l("practice.done"), systemImage: "flag.checkered") {
            if let card = model.scorecard?.card {
                Text(l("practice.result", ["score": ScorecardCard.whole(card.practice), "assessed": "\(card.practiceAssessed)"]))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("practice.result")
            }
            Text(l("practice.doneBody")).font(.callout)
            Button(l("practice.again")) { Task { await model.beginPracticeCheck() } }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("practice.again")
        }
    }

    // MARK: Actions

    private func loadStep() async {
        receipt = nil; actions = []; loadedIdentity = nil
        movePersonID = ""; moveRoomID = ""
        if model.pendingPracticeFeedback != nil { await recoverFeedback(); return }
        guard let identity = model.practiceStepIdentity,
              let step = model.practiceStep(), let scenarios = model.scenarios else { return }
        let session = step.session
        let localizer = model.localizer
        let query = Task.detached(priority: .userInitiated) { try session.query(library: scenarios) }
        guard let loaded = try? await query.value, !Task.isCancelled,
              model.practiceStepIdentity == identity else { return }
        // Show the situation and an authored question at once. Previewing every possible action (each a full
        // session replay) used to hold the whole step, including its decision options, until all previews finished.
        receipt = loaded
        loadedIdentity = identity
        guard PracticeCheckSources.authoredChoice(session, competency: step.competency, library: scenarios) == nil,
              step.attempt.plan == nil else { return }
        let accepted = await ExerciseActions.accepted(ExerciseActions.candidates(session: session, receipt: loaded, localizer: localizer),
                                                      session: session, library: scenarios)
        guard !Task.isCancelled, model.practiceStepIdentity == identity else { return }
        actions = accepted
    }

    /// Records the answer, then marks feedback revealed, and only then shows what happened.
    private func answer(_ command: SessionCommand, step: (attempt: PracticeAttempt, session: SimulationSession, competency: String)) {
        guard !submitting, let identity = loadedIdentity,
              model.practiceStepIdentity == identity,
              identity.attemptID == step.attempt.id, identity.sessionID == step.session.id,
              identity.revision == step.session.revision else { return }
        submitting = true
        Task {
            defer { submitting = false }
            guard await model.submitPracticeAnswer(command, expected: identity) != nil else { return }
            await recoverFeedback()
        }
    }

    /// Reconstructs the already committed answer. A failed reveal write stays retryable,
    /// including after relaunch, without submitting or grading the answer again.
    private func recoverFeedback() async {
        guard let pending = model.pendingPracticeFeedback, let scenarios = model.scenarios else { return }
        let scope = model.scopeSessionID, locale = model.locale
        if !pending.observation.feedbackRevealed {
            guard await model.revealPracticeFeedback(attemptID: pending.attempt.id, actionID: pending.observation.actionID) else { return }
        }
        guard model.scopeSessionID == scope, model.locale == locale,
              model.pendingPracticeFeedback?.observation.actionID == pending.observation.actionID else { return }
        let session = pending.session
        let query = Task.detached(priority: .userInitiated) { try session.query(library: scenarios) }
        guard let after = try? await query.value,
              model.scopeSessionID == scope, model.locale == locale,
              model.pendingPracticeFeedback?.observation.actionID == pending.observation.actionID,
              let command = session.commits.first(where: { $0.id == pending.observation.actionID })?.commands.first else { return }
        let l = model.localizer
        let before = session.commits.firstIndex(where: { $0.id == pending.observation.actionID }).flatMap { index -> SessionReceipt? in
            var prefix = SimulationSession(id: session.id, initial: session.initial, inventory: session.inventory, directorPolicy: session.directorPolicy,
                                           concernSeed: session.concernSeed, dependencyPolicy: session.dependencyPolicy, mechanicsVersion: session.mechanicsVersion)
            for commit in session.commits.prefix(index) { guard (try? prefix.commit(commit, library: scenarios)) != nil else { return nil } }
            return try? prefix.query(library: scenarios)
        }
        var title = ExerciseActions.describe(command, session: session, receipt: before ?? after, localizer: l) ?? l("adaptive.action")
        var detail: String?
        if command.kind == "choose", let option = scenarios.scenario(session.initial.scenarioID)?.choicePoints
            .first(where: { $0.id == command.target })?.options.first(where: { $0.id == command.value }) {
            title = l(option.labelKey); detail = l(option.feedbackKey)
        } else if command.kind == "moveTo", session.initial.scenarioID != "heat-grid-strain", let home = session.initial.home {
            let person = session.initial.household.people.first { $0.id == command.target }?.localizedLabel(l) ?? ""
            title = l("adaptive.moved", ["person": person, "room": command.value.map { HomeScenePresentation.roomLabel($0, in: home) } ?? ""])
        }
        if let index = pending.attempt.observations?.firstIndex(where: { $0.actionID == pending.observation.actionID }),
           let planned = model.practicePlanSituation(attempt: pending.attempt, index: index),
           let option = planned.options.first(where: { $0.command == command }) {
            if let label = option.label { title = label }
            if let text = option.feedback { detail = text }
        }
        let events = after.events.filter { !$0.id.hasPrefix("user.") && $0.id != "evt.\(command.target ?? "")" }
        if detail == nil, command.kind != "choose", command.kind != "moveTo" { detail = ExerciseActions.doneNote(command, localizer: l) }
        feedback = Feedback(actionID: pending.observation.actionID, attemptID: pending.attempt.id,
            scope: scope, locale: locale, competency: pending.observation.competencyID,
            title: title, detail: detail, events: events)
    }
}
