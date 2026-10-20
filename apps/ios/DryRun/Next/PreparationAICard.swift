import SwiftUI
import DryRunCore

/// Opt-in Gemini personalization of the Prepare list (fictional households through the development gateway only).
/// Gemini may reorder within a priority level and explain; the app checks each item against this household's own
/// list. Priority, the score and what counts as done never change. Ideas outside the list are shown as unscored.
struct PreparationAICard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let l = model.localizer
        SectionCard(title: l("prep.ai.title"), systemImage: "sparkles") {
            Text(l("prep.ai.detail")).font(.footnote).foregroundStyle(.secondary)
            switch model.preparationAIState {
            case .working:
                HStack(spacing: Theme.Space.s) { ProgressView(); Text(l("prep.ai.working")).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("next.ai.working")
            case .ready(let p):
                Label(l("prep.ai.applied", ["count": "\(p.ranked.count)"]), systemImage: "checkmark.shield")
                    .font(.callout).accessibilityIdentifier("next.ai.applied")
                if p.rejectedCount > 0 {
                    Text(l("prep.ai.rejected", ["count": "\(p.rejectedCount)"])).font(.footnote).foregroundStyle(Theme.caution)
                }
                if !p.ideas.isEmpty {
                    Text(l("prep.ai.ideas")).font(.subheadline.weight(.semibold)).padding(.top, Theme.Space.xs)
                    ForEach(Array(p.ideas.enumerated()), id: \.offset) { _, idea in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title).font(.callout.weight(.semibold))
                            Text(idea.action).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("next.ai.idea")
                    }
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
                // Development builds name the failing stage (never payloads) so the wired-device loop can be diagnosed.
                Text(reason).font(.caption2).foregroundStyle(.tertiary)
                #endif
                askButton
            case nil:
                askButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next.ai")
    }

    private var askButton: some View {
        Button(model.localizer("prep.ai.run"), systemImage: "sparkles") { Task { await model.personalizePreparation() } }
            .font(.callout.weight(.semibold))
            .frame(minHeight: Theme.minTap)
            .disabled(model.nextStepResults == nil)
            .accessibilityIdentifier("next.ai.run")
    }
}
