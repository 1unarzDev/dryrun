import SwiftUI
import DryRunCore

/// Top of Prepare: the provisional score as three rings (preparation, practice, overall) and what the family has
/// already done. Rings use the accent palette only: progress is never shown as a green "safe".
struct ProgressRingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let l = model.localizer
        if let result = model.scorecard, result.key == model.scoreKey {
            let card = result.card
            let done = model.household?.completedPreparations.count ?? 0
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.l) {
                    ring(card.preparation, label: l("rings.preparation"), tint: Theme.accent)
                    ring(card.practiceAssessed > 0 ? card.practice : nil, label: l("rings.practice"), tint: .orange)
                    ring(card.overall, label: l("rings.overall"), tint: .purple)
                }
                .frame(maxWidth: .infinity)
                if done > 0 {
                    Label(l("rings.done", ["count": "\(done)"]), systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("rings.done")
                } else {
                    Text(l("rings.start")).font(.callout)
                }
                if card.provisional {
                    Text(l("rings.provisional")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rings.card")
        }
    }

    private func ring(_ value: Double?, label: String, tint: Color) -> some View {
        let fraction = (value ?? 0) / 100
        return VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 9)
                Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.map { "\(Int($0.rounded()))" } ?? "–").font(.title3.weight(.bold).monospacedDigit())
            }
            .frame(width: 72, height: 72)
            Text(label).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(label): \(Int($0.rounded())) / 100" } ?? "\(label): –")
    }
}
