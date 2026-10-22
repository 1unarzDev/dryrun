import SwiftUI
import DryRunCore

/// Top of Prepare: the provisional score as three rings (preparation, practice, overall) and what the family has
/// already done. Ring colors are identity colors, never status: progress is never shown as a green "safe". The
/// provisional caveat sits behind ⓘ; the full breakdown stays in ScorecardCard further down.
struct ProgressRingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var showCaveat = false

    var body: some View {
        let l = model.localizer
        if let result = model.scorecard, result.key == model.scoreKey {
            let card = result.card
            let done = model.household?.completedPreparations.count ?? 0
            SectionCard {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Space.l) { rings(card, l) }
                        VStack(alignment: .leading, spacing: Theme.Space.m) { rings(card, l) }
                    }
                    .frame(maxWidth: .infinity)
                    InfoButton(label: l("rings.about"), isExpanded: $showCaveat)
                        .accessibilityIdentifier("rings.info")
                }
                if done > 0 {
                    Label(l("rings.done", ["count": "\(done)"]), systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("rings.done")
                } else {
                    Text(l("rings.start")).font(.callout)
                }
                if showCaveat {
                    Text(l("rings.provisional")).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rings.caveat")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rings.card")
        }
    }

    @ViewBuilder private func rings(_ card: PreparednessScorecard, _ l: Localizer) -> some View {
        ring(card.preparation, label: l("rings.preparation"), tint: Theme.accent)
        ring(card.practiceAssessed > 0 ? card.practice : nil, label: l("rings.practice"), tint: Theme.ringPractice)
        ring(card.overall, label: l("rings.overall"), tint: Theme.ringOverall)
    }

    private func ring(_ value: Double?, label: String, tint: Color) -> some View {
        let fraction = (value ?? 0) / 100
        return VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 9)
                Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.map { "\(Int($0.rounded()))" } ?? "–").font(.title3.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 72, height: 72)
            Text(label).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(label): \(Int($0.rounded())) / 100" } ?? "\(label): –")
    }
}
