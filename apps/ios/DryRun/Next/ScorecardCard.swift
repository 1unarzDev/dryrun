import SwiftUI
import DryRunCore

/// The provisional preparedness score, compiled locally by Core from accepted facts under the draft rubric. It is a
/// summary of documented preparation, not a safety rating, prediction or comparison, so it never shows a green
/// "safe" state. The number, its cap reason and its coverage stay together; the breakdown sits behind a disclosure.
struct ScorecardCard: View {
    @Environment(AppModel.self) private var model
    @State private var showHow = false

    var body: some View {
        let l = model.localizer
        if let result = model.scorecard, result.key == model.scoreKey {
            let card = result.card
            SectionCard(title: l("score.title"), systemImage: "gauge.with.dots.needle.33percent") {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    if let overall = card.overall {
                        Text(l("score.outOf", ["score": Self.whole(overall)]))
                            .font(.largeTitle.weight(.bold)).monospacedDigit()
                    } else {
                        Text(l("score.notAssessed")).font(.title2.weight(.bold))
                    }
                    if card.provisional { StatusPill(text: l("score.provisional"), systemImage: "hourglass", tint: Theme.caution) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("score.overall")
                Text(parts(card)).font(.callout)
                if let cap = capLine(card) {
                    Label(cap, systemImage: "exclamationmark.circle").font(.callout.weight(.semibold))
                        .foregroundStyle(card.cap <= (model.rubric?.knownGapCap ?? 0) ? Theme.critical : Theme.caution)
                        .accessibilityIdentifier("score.cap")
                }
                Text(l("score.coverage", ["coverage": Self.whole(card.evidenceCoverage), "assessed": "\(card.practiceAssessed)"]))
                    .font(.footnote).foregroundStyle(.secondary)
                if let shared = sharedEscapeLine(result) {
                    Label(shared, systemImage: "arrow.triangle.merge").font(.footnote)
                        .accessibilityIdentifier("score.sharedEscape")
                }
                DisclosureGroup(isExpanded: $showHow) { breakdown(card) } label: {
                    Text(l("score.how")).font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("score.how")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("score.card")
        }
    }

    /// Display rounding only; Core keeps the unrounded value and applies the cap before rounding.
    static func whole(_ value: Double) -> String { "\(Int(value.rounded()))" }

    private func parts(_ card: PreparednessScorecard) -> String {
        let l = model.localizer
        let prep = card.preparation.map(Self.whole) ?? l("score.notAssessed")
        let practice = card.practiceAssessed == 0 ? l("score.practiceNotAssessed") : l("score.practice", ["score": Self.whole(card.practice)])
        return l("score.parts", ["preparation": prep, "practice": practice])
    }

    /// "Limited by" only when the cap actually lowers the total (base above the cap); otherwise the same critical items
    /// are listed without claiming they changed the number. A known gap and an unverified requirement read differently.
    private func capLine(_ card: PreparednessScorecard) -> String? {
        guard let rubric = model.rubric, !card.capReasons.isEmpty, card.cap < 100 else { return nil }
        let names = card.capReasons.map { model.localizer("score.criterion.\($0)") }.joined(separator: ", ")
        let known = card.cap <= rubric.knownGapCap
        let base = rubric.preparationWeight * (card.preparation ?? 0) + rubric.practiceWeight * card.practice
        if base > card.cap { return model.localizer(known ? "score.capKnown" : "score.capUnverified", ["items": names]) }
        return model.localizer(known ? "score.criticalKnown" : "score.criticalUnverified", ["items": names])
    }

    /// The fire stress run is hypothetical; it can only say two escape paths meet at the same place.
    private func sharedEscapeLine(_ result: AppModel.Scorecard) -> String? {
        guard let home = model.home, let finding = result.fireStress,
              let shared = finding.baseline.routes.first(where: { !$0.sharedChokepoints.isEmpty })?.sharedChokepoints else { return nil }
        let names = shared.map { id -> String in
            if home.space(id) != nil { return HomeScenePresentation.roomLabel(id, in: home) }
            if let connector = home.connectors.first(where: { $0.id == id }) { return model.localizer("spatial.connector.\(connector.kind.rawValue)") }
            return model.localizer("score.sharedOpening")
        }
        return model.localizer("score.sharedEscape", ["places": Array(Set(names)).sorted().joined(separator: ", ")])
    }

    @ViewBuilder private func breakdown(_ card: PreparednessScorecard) -> some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(l("score.howBody")).font(.footnote)
            if let rubric = model.rubric {
                ForEach(["protection", "supplies", "communication", "continuity", "maintenance"], id: \.self) { domain in
                    let criteria = rubric.criteria.filter { $0.domain == domain }
                    if !criteria.isEmpty {
                        Text(l("score.domain.\(domain)")).font(.footnote.weight(.bold)).padding(.top, Theme.Space.xs)
                        ForEach(criteria, id: \.id) { criterion in
                            let status = card.statuses[criterion.id] ?? .unknown
                            HStack(spacing: Theme.Space.s) {
                                Image(systemName: Self.symbol(status)).foregroundStyle(Self.tint(status)).accessibilityHidden(true)
                                Text(l("score.criterion.\(criterion.id)")).font(.footnote)
                                Spacer(minLength: 0)
                                Text(l("score.status.\(status.rawValue)")).font(.footnote).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Text(l("score.version", ["version": rubric.version])).font(.caption).foregroundStyle(.secondary)
            }
            Text(l("score.notSafety")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, Theme.Space.xs)
    }

    static func symbol(_ status: CriterionStatus) -> String {
        switch status {
        case .met: "checkmark.circle"
        case .partlyMet: "circle.lefthalf.filled"
        case .unmet: "xmark.circle"
        case .unknown: "questionmark.circle"
        case .notApplicable: "minus.circle"
        case .outsideScope: "circle.dashed"
        }
    }

    /// Never green: met means documented, not safe.
    static func tint(_ status: CriterionStatus) -> Color {
        switch status {
        case .met, .partlyMet: Theme.accent
        case .unmet: Theme.critical
        case .unknown: Theme.caution
        case .notApplicable, .outsideScope: .secondary
        }
    }
}
