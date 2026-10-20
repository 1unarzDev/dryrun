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

    /// What the family sees after their answer is safely recorded.
    struct Feedback: Equatable {
        let actionID: String
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
        .task(id: model.practiceStep()?.session.revision ?? -1) { await loadStep() }
        .task(id: model.scoreKey) { await model.refreshScorecard() }
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
            if let scenarios = model.scenarios,
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

    @ViewBuilder private func actionList(_ step: (attempt: PracticeAttempt, session: SimulationSession, competency: String)) -> some View {
        let l = model.localizer
        SectionCard(title: l("adaptive.whatNow"), systemImage: "arrow.triangle.branch") {
            Text(l("practice.chooseOne")).font(.footnote).foregroundStyle(.secondary)
            ForEach(actions, id: \.self) { action in
                Button { answer(action.commands[0], step: step) } label: {
                    Label(action.title, systemImage: action.symbol).multilineTextAlignment(.leading)
                }
                .buttonStyle(.choice)
                .disabled(submitting)
            }
            if let home = step.session.initial.home {
                Text(l("adaptive.move")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                Picker(l("adaptive.movePerson"), selection: $movePersonID) {
                    Text(l("adaptive.choose")).tag("")
                    ForEach(step.session.initial.household.people) { Text($0.localizedLabel(l)).tag($0.id) }
                }
                Picker(l("adaptive.moveRoom"), selection: $moveRoomID) {
                    Text(l("adaptive.choose")).tag("")
                    ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                }
                Button(l("adaptive.moveGo")) {
                    answer(SessionCommand(kind: "moveTo", target: movePersonID, value: moveRoomID), step: step)
                }
                .buttonStyle(.secondary)
                .disabled(movePersonID.isEmpty || moveRoomID.isEmpty || submitting)
                .accessibilityIdentifier("practice.moveGo")
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
                self.feedback = nil
                movePersonID = ""; moveRoomID = ""
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
        guard let step = model.practiceStep(), let scenarios = model.scenarios else { receipt = nil; return }
        let session = step.session
        let query = Task.detached(priority: .userInitiated) { try session.query(library: scenarios) }
        guard let loaded = try? await query.value else { return }
        receipt = loaded
        actions = await ExerciseActions.accepted(ExerciseActions.candidates(session: session, receipt: loaded, localizer: model.localizer),
                                                 session: session, library: scenarios)
    }

    /// Records the answer, then marks feedback revealed, and only then shows what happened.
    private func answer(_ command: SessionCommand, step: (attempt: PracticeAttempt, session: SimulationSession, competency: String)) {
        guard !submitting else { return }
        submitting = true
        Task {
            defer { submitting = false }
            let before = receipt?.events.count ?? 0
            guard let observation = await model.submitPracticeAnswer(command),
                  await model.revealPracticeFeedback(attemptID: step.attempt.id, actionID: observation.actionID),
                  let scenarios = model.scenarios,
                  let session = model.aiState.sessions.first(where: { $0.id == step.session.id }) else { return }
            let after = try? session.query(library: scenarios)
            let l = model.localizer
            var title = (receipt ?? after).flatMap { shown in
                ExerciseActions.candidates(session: step.session, receipt: shown, localizer: l).first { $0.commands == [command] }?.title
            } ?? l("adaptive.action")
            var detail: String?
            if command.kind == "choose", let option = scenarios.scenario(step.session.initial.scenarioID)?.choicePoints
                .first(where: { $0.id == command.target })?.options.first(where: { $0.id == command.value }) {
                title = l(option.labelKey); detail = l(option.feedbackKey)
            } else if command.kind == "moveTo", let home = step.session.initial.home {
                let person = step.session.initial.household.people.first { $0.id == command.target }?.localizedLabel(l) ?? ""
                title = l("adaptive.moved", ["person": person, "room": command.value.map { HomeScenePresentation.roomLabel($0, in: home) } ?? ""])
            }
            let events = (after?.events.dropFirst(before) ?? []).filter { !$0.id.hasPrefix("user.") && $0.id != "evt.\(command.target ?? "")" }
            feedback = Feedback(actionID: observation.actionID, competency: step.competency, title: title, detail: detail, events: Array(events))
        }
    }
}
