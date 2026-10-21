import SwiftUI
import DryRunCore

/// Top of Prepare during an active NWS alert: what the alert is, Core's three steps for this household, and a way
/// straight into the matching rehearsal. A recorded sample is labelled as a sample.
struct AlertBannerCard: View {
    @Environment(AppModel.self) private var model
    let alert: WeatherAlert

    var body: some View {
        let l = model.localizer
        let scenario = WeatherAlerts.scenarioID(for: alert.event)
        let steps = model.alertSteps
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if alert.isSample {
                Text(l("alert.sample")).font(.caption.weight(.bold))
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
                    .background(.white.opacity(0.25), in: Capsule())
                    .accessibilityIdentifier("alert.sampleLabel")
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.event).font(.title3.weight(.bold))
                    Text(alert.areaDescription).font(.subheadline)
                    if let expires = alert.expires, !alert.isSample {
                        Text(l("alert.until", ["time": expires.formatted(date: .omitted, time: .shortened)])).font(.subheadline)
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            }
            if !steps.isEmpty {
                Text(l("alert.doNow")).font(.headline).padding(.top, Theme.Space.xs)
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text("\(index + 1)").font(.headline.monospacedDigit())
                            .frame(width: 28, height: 28).background(.white.opacity(0.25), in: Circle())
                        Text(model.alertStepText(step)).font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("alert.step")
                }
            }
            if let scenario {
                Button {
                    model.pendingScenarioID = scenario
                } label: {
                    Label(l("alert.rehearse"), systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.72, green: 0.11, blue: 0.11))
                .accessibilityIdentifier("alert.rehearse")
            } else {
                Text(l("alert.noRehearsal")).font(.footnote)
            }
            Text(l("alert.official")).font(.caption)
        }
        .foregroundStyle(.white)
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A fixed deep red: white text keeps its contrast in both appearances (Theme.critical lightens in dark mode).
        .background(Color(red: 0.72, green: 0.11, blue: 0.11), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alert.banner")
    }
}
