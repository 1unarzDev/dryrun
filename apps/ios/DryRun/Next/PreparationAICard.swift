import SwiftUI
import DryRunCore

/// Gateway personalization of the Prepare list (fictional households through the development gateway only).
/// The selected provider may reorder within a priority level and explain; the app checks each item against this household's own
/// list. Priority, the score and what counts as done never change. Ideas outside the list are shown as unscored.
struct PreparationAICard: View {
    @Environment(AppModel.self) private var model
    @State private var showIdeas = false

    var body: some View {
        let l = model.localizer
        SectionCard(title: l("prep.ai.title"), systemImage: "sparkles") {
            switch model.preparationAIState {
            case .working:
                HStack(spacing: Theme.Space.s) { ProgressView(); Text(l("prep.ai.working")).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("next.ai.working")
            case .ready(let p):
                Label(l("prep.ai.applied", ["count": "\(p.ranked.count)"]), systemImage: "checkmark.shield")
                    .font(.callout).accessibilityIdentifier("next.ai.applied")
                #if DEBUG
                if model.preparationAIIsSaved {
                    Label("Saved Beacon answer for these same inputs", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("next.ai.saved")
                }
                if model.preparationAIIsReplay {
                    // Development label only: the filmed demo must not pass a recording off as a live answer.
                    Label("Replay of a recorded Beacon answer (gateway unavailable)", systemImage: "play.rectangle")
                        .font(.caption).foregroundStyle(Theme.caution)
                        .accessibilityIdentifier("next.ai.replay")
                }
                #endif
                if p.rejectedCount > 0 {
                    Text(l("prep.ai.rejected", ["count": "\(p.rejectedCount)"])).font(.footnote).foregroundStyle(Theme.caution)
                }
                if !p.ideas.isEmpty {
                    DisclosureGroup(isExpanded: $showIdeas) {
                        ForEach(Array(p.ideas.enumerated()), id: \.offset) { _, idea in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(idea.title).font(.callout.weight(.semibold))
                                Text(idea.action).font(.footnote).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.Space.s)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("next.ai.idea")
                        }
                    } label: {
                        Text(l("prep.ai.ideas") + " (\(p.ideas.count))").font(.subheadline.weight(.semibold))
                            .frame(minHeight: Theme.minTap)
                    }
                    .accessibilityIdentifier("next.ai.ideas.expand")
                }
                if let question = p.question, !question.isEmpty {
                    Label(l("prep.ai.question", ["question": question]), systemImage: "questionmark.bubble").font(.footnote)
                }
                Button(l("prep.ai.reset")) { model.clearPreparationPersonalization() }
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("next.ai.reset")
            case .unavailable(let reason):
                Text(l("prep.ai.unavailable")).font(.footnote).foregroundStyle(Theme.caution)
                #if DEBUG
                Text("Gateway: \(reason)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("next.ai.reason")
                #endif
                askButton
            case nil:
                askButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next.ai")
        .onChange(of: model.scopeSessionID) { _, _ in showIdeas = false }
        // Beacon tailors the list on open, without a tap, once per input state.
        .task(id: model.preparationAITrigger) { await model.autoPersonalizePreparation() }
    }

    private var askButton: some View {
        Button(model.localizer("prep.ai.run"), systemImage: "sparkles") { Task { await model.personalizePreparation() } }
            .font(.callout.weight(.semibold))
            .frame(minHeight: Theme.minTap)
            .disabled(model.nextStepResults == nil)
            .accessibilityIdentifier("next.ai.run")
    }
}
