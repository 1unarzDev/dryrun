import SwiftUI
import DryRunCore

/// An adaptive exercise over an incremental Core session. Everything on screen (scene, routes, resources, events)
/// comes from the committed receipt; the family's actions are validated by the host before anything changes, and the
/// director (on-device, or Gemini when enabled) only chooses what happens next within reviewed limits.
struct AdaptiveRehearsalView: View {
    let scenarioID: String
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showServices = false
    @State private var movePersonID = ""
    @State private var moveRoomID = ""
    /// Actions the host accepts at `acceptedRevision`, previewed once per committed revision rather than per render.
    @State private var accepted: [ActionOption] = []
    @State private var acceptedRevision: Int?

    private static let spatial: Set<String> = ["home-fire", "flash-flood", "tornado"]

    var body: some View {
        let l = model.localizer
        let exercise = model.adaptive.flatMap { $0.session.initial.scenarioID == scenarioID ? $0 : nil }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    PracticeBanner(text: l("common.practiceLabel")).id("top")
                    if let exercise {
                        header(exercise)
                        if exercise.sourceKey != model.currentKey { staleNotice }
                        if let home = exercise.session.initial.home, Self.spatial.contains(scenarioID) {
                            SpatialRehearsalScene(home: home, household: exercise.session.initial.household,
                                                  state: exercise.receipt.snapshot.spatialState,
                                                  previous: exercise.previous?.snapshot.spatialState,
                                                  isFireExercise: scenarioID == "home-fire")
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("adaptive.scene")
                        } else if !Self.spatial.contains(scenarioID),
                                  let design = RehearsalExperienceDesign.design(scenarioID: scenarioID, household: exercise.session.initial.household),
                                  let presentation = try? RehearsalScenePresentation(hazard: design.hazard, snapshot: exercise.receipt.snapshot,
                                      baseline: nil, experience: exercise.receipt.experience, visibleEvents: exercise.receipt.events) {
                            // Non-spatial hazards (freeze, heat, water) get the same committed status scene as the
                            // scripted rehearsal, so a Beacon-directed exercise has a visual anchor for every hazard.
                            HazardStatusScene(presentation: presentation, household: exercise.session.initial.household,
                                              home: exercise.session.initial.home)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("adaptive.hazardScene")
                        }
                        youDid(exercise)
                        recordedChanges(exercise)
                        happened(exercise)
                        if exercise.receipt.finished {
                            finished(exercise)
                        } else if exercise.receipt.directorState?.awaitingUserAction == true {
                            decision(exercise).id("decision")
                        }
                        if !exercise.receipt.finished {
                            hazardChoices(exercise)
                            otherActions(exercise)
                        }
                        DisclosureGroup(isExpanded: $showServices) {
                            ServiceStateGrid(snapshot: exercise.receipt.snapshot).padding(.top, Theme.Space.s)
                        } label: {
                            Label(l("ui.rehearse.allServices"), systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                        }
                        .padding(Theme.Space.l)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .accessibilityIdentifier("adaptive.services")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xxl)
                    }
                }
                .padding()
            }
            .onChange(of: exercise?.receipt.revision, initial: true) { _, _ in
                guard let exercise, exercise.sourceKey == model.currentKey else { return }
                let target = exercise.receipt.directorState?.awaitingUserAction == true ? "decision" : "top"
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { if let exercise { controls(exercise) } }
        .navigationTitle(l("common.scenario.\(scenarioID)"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.openAdaptive(scenarioID: scenarioID) }
        .task(id: exercise?.session.revision) { await refreshAccepted() }
    }

    // MARK: Header and notices

    private func header(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let minute = exercise.receipt.snapshot.simMinute
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Label(l("adaptive.title"), systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
            // One row when it fits; stacked at large text so neither label is squeezed into a narrow column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { clockLabel(minute); directorLabel(exercise) }
                VStack(alignment: .leading, spacing: Theme.Space.xs) { clockLabel(minute); directorLabel(exercise) }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if let narration = exercise.narration, exercise.lastDirector?.isRemote == true {
                // Model prose is a suggestion; the scene above and the events below are the committed facts.
                Text(narration).font(.callout).foregroundStyle(.secondary)
                Text(l("adaptive.narrationNote")).font(.caption).foregroundStyle(.secondary)
            }
            if model.directorTurnInFlight {
                // Brief progress while a gateway turn runs; End stays available, and past the deadline this phone takes the step.
                BeaconThinkingView(activity: .directing, title: l("adaptive.director.inFlight"))
                    .accessibilityIdentifier("adaptive.director.inFlight")
            }
            if let note = model.directorFallbackNote {
                Label(note, systemImage: "iphone").font(.footnote).foregroundStyle(Theme.caution)
                    .accessibilityIdentifier("adaptive.fallbackNote")
            }
            if model.cloudDirectorAvailable {
                let bindable = Bindable(model)
                Toggle(isOn: bindable.cloudDirectorEnabled) {
                    Text(l("adaptive.cloud.toggle")).font(.callout.weight(.semibold))
                }
                .padding(.top, Theme.Space.xs)
                .accessibilityIdentifier("adaptive.cloudToggle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.header")
    }

    private func clockLabel(_ minute: Int) -> some View {
        let l = model.localizer
        return Label(l("common.simClock", ["time": RehearsalPresentation.compactTime(minutes: minute, localizer: l)]), systemImage: "clock")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(RehearsalPresentation.spokenTime(minutes: minute, localizer: l))
    }

    @ViewBuilder private func directorLabel(_ exercise: AppModel.AdaptiveExercise) -> some View {
        if let director = exercise.lastDirector {
            Label(model.localizer("adaptive.director.\(director.rawValue)"), systemImage: director.isRemote ? "sparkles" : "iphone")
                .fixedSize(horizontal: false, vertical: true)
            // Debug builds only: the allowlisted provider that served the turn (nothing for an unreported one).
            BeaconServedByLabel(servedBy: director == .beacon ? nil : director.rawValue)
        }
    }

    private var staleNotice: some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label(l("adaptive.stale"), systemImage: "clock.arrow.circlepath").font(.callout)
            Button(l("adaptive.restart")) { Task { await model.openAdaptive(scenarioID: scenarioID, restart: true) } }
                .font(.callout.weight(.semibold)).frame(minHeight: Theme.minTap)
        }
        .padding(Theme.Space.m)
        .background(Theme.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityIdentifier("adaptive.stale")
    }

    // MARK: Committed results

    /// The family's newest committed action and the host's reading of it, separate from what the director added.
    @ViewBuilder private func youDid(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        if let last = exercise.session.commits.last, last.actor == "user" {
            SectionCard(title: l("adaptive.youDid"), systemImage: "hand.raised", tint: Theme.accent) {
                ForEach(Array(last.commands.enumerated()), id: \.offset) { _, command in
                    if command.kind == "choose", let option = chosenOption(command, in: exercise) {
                        Text(l(option.labelKey)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(l(option.feedbackKey)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(actionTitle(command, in: exercise)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(ExerciseActions.doneNote(command, localizer: l)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("adaptive.youDid")
        }
    }

    /// Events the newest commit produced, newest first. Engine events only; the user's own echo is shown above.
    @ViewBuilder private func happened(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let start = min(exercise.previous?.events.count ?? 0, exercise.receipt.events.count)
        // The engine echoes an answered choice as an event; "What you did" already shows that option and feedback.
        let answered = Set((exercise.session.commits.last?.actor == "user" ? exercise.session.commits.last?.commands ?? [] : [])
            .filter { $0.kind == "choose" }.compactMap { $0.target.map { "evt.\($0)" } })
        let situation = exercise.receipt.events.filter { !$0.id.hasPrefix("user.") && !answered.contains($0.id) }
        let fresh = exercise.receipt.events[start...].filter { !$0.id.hasPrefix("user.") && !answered.contains($0.id) }
        if let latest = fresh.last {
            EventCard(event: latest, isCurrent: true)
            ForEach(fresh.dropLast().reversed()) { TimelineRow(event: $0, result: nil) }
        } else if let current = situation.last, exercise.session.commits.last?.actor != "user" {
            // Nothing new this turn: keep the current situation beside the decision instead of an empty screen.
            EventCard(event: current, isCurrent: false)
        } else if situation.isEmpty {
            Text(model.localizer("ui.scenario.\(scenarioID).blurb")).font(.title3.weight(.semibold))
        }
    }

    @ViewBuilder private func decision(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        if let scenarios = model.scenarios,
           let choice = LocalDirector.dueChoice(session: exercise.session, receipt: exercise.receipt, library: scenarios) {
            let point = DecisionPoint(id: choice.id, simMinute: choice.minute, promptKey: choice.promptKey,
                                      options: choice.options.map { .init(id: $0.id, labelKey: $0.labelKey, feedbackKey: $0.feedbackKey, isRecommended: !$0.unsafe) })
            DecisionCard(decision: point) { option in
                Task { await model.submitAdaptive([SessionCommand(kind: "choose", target: choice.id, value: option)]) }
            }
        } else {
            // A director asked for a decision without an authored question: any action below continues the exercise,
            // or the family can explicitly keep watching (a recorded decision, not a default).
            SectionCard(title: l("adaptive.whatNow"), systemImage: "arrow.triangle.branch") {
                Text(l("adaptive.whatNowDetail")).font(.callout)
                if let scenarios = model.scenarios,
                   HazardChoices.waitAvailable(session: exercise.session, receipt: exercise.receipt, library: scenarios) {
                    Button { Task { await model.submitAdaptive([SessionCommand(kind: "wait")]) } } label: {
                        Label(l("rehearsal.cmd.wait"), systemImage: "hourglass").multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.choice)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("rehearsal.cmd.wait")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("adaptive.whatNow")
        }
    }

    @ViewBuilder private func finished(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let household = exercise.session.initial.household
        SectionCard(title: l("adaptive.finished"), systemImage: "flag.checkered") {
            Text(l("adaptive.finishedBody")).font(.callout)
            // The family's own committed actions, in order, described from the commands themselves.
            let trace = exercise.session.commits.filter { $0.actor == "user" }.flatMap(\.commands).filter { $0.kind != "finish" }
            if !trace.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(l("rehearsal.cmd.trace")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                    ForEach(Array(trace.enumerated()), id: \.offset) { index, command in
                        IconRow(systemImage: "\(min(index + 1, 50)).circle", tint: Theme.accent, title: actionTitle(command, in: exercise))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("rehearsal.cmd.trace")
            }
            let facts = ExerciseActions.facts(exercise.receipt, session: exercise.session, localizer: l)
            if !facts.isEmpty {
                Text(l("rehearsal.cmd.recorded")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                ForEach(facts, id: \.id) { fact in
                    IconRow(systemImage: "checkmark.circle", tint: Theme.accent, title: fact.text)
                }
            }
            let unmet = exercise.receipt.snapshot.unmetRequirements
            if !unmet.isEmpty {
                Text(l("adaptive.unmet")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                ForEach(unmet, id: \.self) { id in
                    IconRow(systemImage: "exclamationmark.circle", tint: Theme.critical, title: requirementName(id, household: household))
                }
            }
            Button(l("adaptive.prepareNext")) {
                model.closeAdaptive()
                model.pendingTab = "prepare"
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("adaptive.prepareNext")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.finishedCard")
    }

    // MARK: Actions

    /// Facts this turn added to the exercise record (arrivals, accounting, what was in place at an outage),
    /// read from the committed receipt, not from narration.
    @ViewBuilder private func recordedChanges(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let before = exercise.previous.map { Set(ExerciseActions.facts($0, session: exercise.session, localizer: l).map(\.text)) } ?? []
        let fresh = exercise.previous == nil ? [] : ExerciseActions.facts(exercise.receipt, session: exercise.session, localizer: l).filter { !before.contains($0.text) }
        if !fresh.isEmpty, !exercise.receipt.finished {
            SectionCard(title: l("rehearsal.cmd.changed"), systemImage: "list.bullet.clipboard") {
                ForEach(fresh, id: \.id) { fact in
                    Text(fact.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rehearsal.cmd.changed")
        }
    }

    /// The hazard's own choices now: who does what, where. Each was validated by the host for this receipt and is
    /// previewed again at this revision; choosing one commits it through the engine.
    @ViewBuilder private func hazardChoices(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let actions = (acceptedRevision == exercise.session.revision ? accepted : []).filter(Self.isHazard)
        if !actions.isEmpty {
            SectionCard(title: l("rehearsal.cmd.title"), systemImage: "person.line.dotted.person") {
                Text(l("rehearsal.cmd.detail")).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(actions, id: \.identifier) { action in
                    Button { Task { await model.submitAdaptive(action.commands) } } label: {
                        Label(action.title, systemImage: action.symbol).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.choice)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier(action.identifier)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rehearsal.cmd.list")
        }
    }

    /// Hazard choices described from the receipt (not recognition notes, water-use policies or door closing).
    private static func isHazard(_ option: ActionOption) -> Bool {
        // Disconnecting a device is a counterfactual the family may explore, never offered beside the hazard choices.
        option.isHazardChoice && option.commands.count == 1
            && !(option.commands[0].kind == "allocatePower" && option.commands[0].value == "none")
    }

    /// Typed actions the host can model, shown only when the host would accept them at this moment.
    @ViewBuilder private func otherActions(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let all = acceptedRevision == exercise.session.revision ? accepted : []
        let actions = all.filter { !Self.isHazard($0) && !$0.isNote }
        let notes = all.filter(\.isNote)
        let household = exercise.session.initial.household
        // A free person+room move only where the hazard has no person/destination choices of its own (flood keeps it
        // for supply logistics); fire, tornado and heat offer specific exits, shelters and shaded rooms instead.
        let home = Self.spatial.contains(scenarioID) && (!ExerciseActions.hasHazardChoices(exercise.receipt) || scenarioID == "flash-flood")
            ? exercise.session.initial.home : nil
        let move = moveCommand(exercise)
        if !actions.isEmpty || !notes.isEmpty || home != nil {
            SectionCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(actions, id: \.title) { action in
                            Button { Task { await model.submitAdaptive(action.commands) } } label: {
                                Label(action.title, systemImage: action.symbol).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.choice)
                            .accessibilityIdentifier(action.identifier)
                        }
                        if !notes.isEmpty {
                            Text(l("rehearsal.cmd.notes")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                            ForEach(notes, id: \.identifier) { note in
                                Button { Task { await model.submitAdaptive(note.commands) } } label: {
                                    Label(note.title, systemImage: note.symbol).multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.choice)
                                .accessibilityIdentifier(note.identifier)
                            }
                        }
                        if let home {
                            Text(l("adaptive.move")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                            Picker(l("adaptive.movePerson"), selection: $movePersonID) {
                                Text(l("adaptive.choose")).tag("")
                                ForEach(household.people) { Text($0.localizedLabel(l)).tag($0.id) }
                            }
                            Picker(l("adaptive.moveRoom"), selection: $moveRoomID) {
                                Text(l("adaptive.choose")).tag("")
                                ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                            }
                            Button(l("adaptive.moveGo")) { if let move { Task { await model.submitAdaptive([move]) } } }
                                .buttonStyle(.secondary)
                                .disabled(move.map { !model.adaptiveAccepts([$0]) } ?? true)
                                .accessibilityIdentifier("adaptive.moveGo")
                        }
                        Text(l("adaptive.onlyModeled")).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, Theme.Space.s)
                } label: {
                    Label(l("adaptive.otherActions"), systemImage: "plus.bubble").font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("adaptive.otherActions")
        }
    }

    private typealias ActionOption = ExerciseActions.Option

    private func refreshAccepted() async {
        guard let exercise = model.adaptive, exercise.session.initial.scenarioID == scenarioID, let library = model.scenarios else { return }
        let options = await ExerciseActions.accepted(availableActions(exercise), session: exercise.session, library: library)
        guard model.adaptive?.session.revision == exercise.session.revision else { return }
        accepted = options
        acceptedRevision = exercise.session.revision
    }

    private func availableActions(_ exercise: AppModel.AdaptiveExercise) -> [ActionOption] {
        ExerciseActions.candidates(session: exercise.session, receipt: exercise.receipt, localizer: model.localizer)
    }

    private func moveCommand(_ exercise: AppModel.AdaptiveExercise) -> SessionCommand? {
        guard !movePersonID.isEmpty, !moveRoomID.isEmpty else { return nil }
        return SessionCommand(kind: "moveTo", target: movePersonID, value: moveRoomID)
    }

    private func chosenOption(_ command: SessionCommand, in exercise: AppModel.AdaptiveExercise) -> AuthoredOption? {
        model.scenarios?.scenario(scenarioID)?.choicePoints.first { $0.id == command.target }?.options.first { $0.id == command.value }
    }

    private func actionTitle(_ command: SessionCommand, in exercise: AppModel.AdaptiveExercise) -> String {
        // Described from the command itself: an escape that is no longer offered still says who left by which exit.
        let receipt = exercise.previous ?? exercise.receipt
        return ExerciseActions.describe(command, session: exercise.session, receipt: receipt, localizer: model.localizer)
            ?? (command.kind == "moveTo" ? movedTitle(command, in: exercise) : model.localizer("adaptive.action"))
    }

    private func movedTitle(_ command: SessionCommand, in exercise: AppModel.AdaptiveExercise) -> String {
        let h = exercise.session.initial.household
        let person = h.people.first { $0.id == command.target }?.localizedLabel(model.localizer) ?? ""
        let room = exercise.session.initial.home.flatMap { home in command.value.map { HomeScenePresentation.roomLabel($0, in: home) } } ?? ""
        return model.localizer("adaptive.moved", ["person": person, "room": room])
    }

    private func requirementName(_ id: String, household: HouseholdProfile) -> String {
        let l = model.localizer
        for kind in ["power", "refrigeration"] where id.hasPrefix("req.\(kind).") {
            let device = HouseholdLabels.equipment(String(id.dropFirst("req.\(kind).".count)), in: household, localizer: l)
            return l("adaptive.req.\(kind)", ["device": device])
        }
        let key = "adaptive.\(id)"
        // A requirement without a name is described, never shown as a raw key.
        return l.has(key, in: "en") ? l(key) : UnknownNames.describe(id, household: household, localizer: l)
    }

    // MARK: Controls

    private func controls(_ exercise: AppModel.AdaptiveExercise) -> some View {
        let l = model.localizer
        let awaiting = exercise.receipt.directorState?.awaitingUserAction == true
        let finished = exercise.receipt.finished
        return AdaptiveStack(spacing: Theme.Space.s) {
            Button {
                Task { await model.openAdaptive(scenarioID: scenarioID, restart: true) }
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.body.weight(.semibold)).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .accessibilityLabel(l("adaptive.restart"))
            .accessibilityIdentifier("adaptive.restart")
            Button { Task { await model.advanceAdaptive() } } label: {
                Label(awaiting ? l("ui.rehearse.chooseAbove") : l("adaptive.next"), systemImage: awaiting ? "hand.point.up" : "forward.frame")
            }
            .buttonStyle(PrimaryButtonStyle(tint: finished ? Color.secondary : Theme.accent))
            .disabled(awaiting || finished || model.isWorking || model.directorTurnInFlight)
            .accessibilityIdentifier("adaptive.next")
            Button { Task { await model.submitAdaptive([SessionCommand(kind: "finish")]) } } label: {
                Label(l("adaptive.end"), systemImage: "stop.circle")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Color.secondary))
            .disabled(finished || model.isWorking)
            .accessibilityIdentifier("adaptive.end")
        }
        .padding(.horizontal).padding(.vertical, Theme.Space.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }
}
