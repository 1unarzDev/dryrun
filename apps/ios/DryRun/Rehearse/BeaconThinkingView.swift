import SwiftUI
import DryRunCore

/// A calm "Beacon is working" indicator for any gateway request in flight, so a slow answer reads as progress rather
/// than a frozen screen. Every line it shows is host-authored copy (never model text); it rotates through short
/// status phrases for the kind of work underway and, after a while, reassures the family that the app stays usable.
/// With Reduce Motion the glyph stays still and only the status text changes.
struct BeaconThinkingView: View {
    enum Activity: String {
        case preparing, directing, debriefing, resources, practice

        /// Host-authored English status lines, in order. Optional `beacon.thinking.<activity>.<n>` locale keys override them.
        var phases: [String] {
            switch self {
            case .preparing: ["Reading your household…", "Checking your home…", "Ranking what to do first…"]
            case .directing: ["Reading what just happened…", "Checking your home…", "Planning the next moment…"]
            case .debriefing: ["Reviewing this rehearsal…", "Matching it to your preparations…", "Writing a short summary…"]
            case .resources: ["Reading your open tasks…", "Checking travel and budget…", "Planning local searches…"]
            case .practice: ["Preparing your next practice set…", "Choosing fresh situations…", "Almost ready…"]
            }
        }

        /// What the family can do while waiting; the app never blocks on Beacon.
        var stillWorking: String {
            switch self {
            case .directing: "Still working — you can keep going. If Beacon takes too long, this phone picks the next moment."
            case .practice: "Still working — you can keep going with the questions already here."
            default: "Still working — you can keep going. The app's own list stays in place."
            }
        }
    }

    let activity: Activity
    /// Optional already-localized headline (for example the card's existing "Asking Beacon…" line).
    var title: String?
    var compact = false

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    static let phaseSeconds: Double = 2.6
    static let reassureAfter: Double = 10

    var body: some View {
        TimelineView(.periodic(from: start, by: reduceMotion ? 1 : 1.0 / 30)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let phase = phaseText(elapsed)
            HStack(alignment: .center, spacing: Theme.Space.m) {
                glyph(elapsed)
                VStack(alignment: .leading, spacing: 2) {
                    if let title, !compact {
                        Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(phase)
                        .font(compact ? .footnote : .callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: phase)
                    if elapsed >= Self.reassureAfter {
                        Text(text("stillWorking", fallback: activity.stillWorking))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(phase: phase, elapsed: elapsed))
            .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("beacon.thinking.\(activity.rawValue)")
    }

    private func glyph(_ elapsed: Double) -> some View {
        let size: CGFloat = compact ? 22 : 30
        // Two soft rings radiate from the glyph, offset by half a cycle; the glyph breathes slightly.
        let cycle = 1.8
        let t = reduceMotion ? 0 : (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
        let t2 = reduceMotion ? 0 : ((elapsed + cycle / 2).truncatingRemainder(dividingBy: cycle)) / cycle
        let breathe = reduceMotion ? 1 : 1 + 0.06 * sin(elapsed * 2 * .pi / cycle)
        return ZStack {
            if !reduceMotion {
                ring(progress: t, size: size)
                ring(progress: t2, size: size)
            }
            Circle().fill(Theme.accent.opacity(0.14)).frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .scaleEffect(breathe)
        }
        .frame(width: size * 1.7, height: size * 1.7)
        .accessibilityHidden(true)
    }

    private func ring(progress: Double, size: CGFloat) -> some View {
        Circle()
            .stroke(Theme.accent, lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.7 * progress)
            .opacity(0.55 * (1 - progress))
    }

    private func phaseText(_ elapsed: Double) -> String {
        let phases = activity.phases
        // Walk the phrases once, then rest on the last one rather than looping (looping reads like a stuck spinner).
        let index = min(Int(elapsed / Self.phaseSeconds), phases.count - 1)
        return text("\(index + 1)", fallback: phases[index])
    }

    private func accessibilityText(phase: String, elapsed: Double) -> String {
        var parts = [text("label", fallback: "Beacon is working"), phase]
        if elapsed >= Self.reassureAfter { parts.append(text("stillWorking", fallback: activity.stillWorking)) }
        return parts.joined(separator: ". ")
    }

    /// Locale override when a reviewed key exists; otherwise the host-authored English line.
    private func text(_ suffix: String, fallback: String) -> String {
        let key = suffix == "label" ? "beacon.thinking.label" : "beacon.thinking.\(activity.rawValue).\(suffix)"
        let resolved = model.localizer.text(key)
        return resolved.isMissing ? fallback : resolved.text
    }
}

/// Opens the adaptive exercise for one hazard with Beacon directing (when a gateway is configured for a fictional
/// household). The adaptive view keeps the on-device director as the fallback and the bounded deadline per turn, so
/// every one of the six hazards can be rehearsed with Beacon's help without depending on it.
struct BeaconEntryLink: View {
    let scenarioID: String
    var compact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.cloudDirectorAvailable {
            NavigationLink(value: "adaptive:\(scenarioID)") {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text("beacon.entry.title", "Rehearse with Beacon")).font(.callout.weight(.semibold))
                        if !compact {
                            Text(text("beacon.entry.detail", "Beacon adapts what happens next to what you do. This phone takes over if Beacon is slow."))
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("beacon.entry.\(scenarioID)")
        }
    }

    private func text(_ key: String, _ fallback: String) -> String {
        let resolved = model.localizer.text(key)
        return resolved.isMissing ? fallback : resolved.text
    }
}
