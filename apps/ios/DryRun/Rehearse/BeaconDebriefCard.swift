import SwiftUI
import DryRunCore

/// Beacon's short summary at the end of a rehearsal (fictional households, development gateway). The app's own
/// debrief below stays complete without it; Beacon may only point at recommendations this rehearsal already made.
struct BeaconDebriefCard: View {
    @Environment(AppModel.self) private var model
    let result: RehearsalResult

    var body: some View {
        let l = model.localizer
        SectionCard(title: l("debrief.ai.title"), systemImage: "sparkles") {
            switch model.beaconDebriefState(for: result.input) {
            case .working, nil:
                BeaconThinkingView(activity: .debriefing, title: l("debrief.ai.working"))
            case .ready(let accepted, let replay):
                Text(accepted.summary).font(.callout)
                    .accessibilityIdentifier("debrief.ai.summary")
                if !accepted.focusActionIDs.isEmpty {
                    Text(l("debrief.ai.first")).font(.subheadline.weight(.semibold))
                    ForEach(accepted.focusActionIDs, id: \.self) { action in
                        Label(model.actionTitle(action), systemImage: "arrow.right.circle").font(.callout)
                    }
                }
                Text(l("debrief.ai.note")).font(.caption).foregroundStyle(.secondary)
                #if DEBUG
                if replay {
                    Label("Replay of a recorded Beacon answer (gateway unavailable)", systemImage: "play.rectangle")
                        .font(.caption).foregroundStyle(Theme.caution)
                }
                #endif
            case .unavailable(let reason):
                Text(l("debrief.ai.unavailable")).font(.footnote).foregroundStyle(Theme.caution)
                #if DEBUG
                Text(reason).font(.caption2).foregroundStyle(.tertiary)
                #endif
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrief.ai")
        .task(id: result.input) { await model.requestBeaconDebrief(for: result) }
    }
}
