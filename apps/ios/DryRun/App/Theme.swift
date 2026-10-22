import SwiftUI
import UIKit
import DryRunCore

/// Design tokens and shared components. Calm, high-contrast, light and dark. Status always pairs an icon and text
/// with color (never color alone). The provisional score appears only as Core computes it; nothing here invents one.
///
/// Visual rules (docs/integration/native-ui-specialist.md "Visual rules" holds the list with its rationale):
/// 1. Type: screen headline `.title2.bold`; card title `.headline`; row title `.body.semibold` (the first row of a
///    ranked list may use `.title3.bold`); supporting text `.footnote` secondary; caveats `.caption`/`.footnote`.
/// 2. Spacing: only `Theme.Space` values. Screen gutter `l` (16); card padding `l`; between cards `l`; inside a card
///    `m`; label/value pairs `xs`/`s`. No one-off offsets to fix a single screenshot.
/// 3. Cards: `SectionCard` for every grouped block outside a `List`; radius `Radius.card`; controls `Radius.control`.
/// 4. Buttons: one `.primary` per screen; `.secondary` beside it; `.inline` text actions (`ShowAllButton`) inside a
///    card. Every tappable thing is at least `Theme.minTap` tall; primary/secondary use `Theme.comfortableTap`.
/// 5. Color: `accent` for identity and navigation, `critical` only for an unmet essential requirement, `caution` for
///    unknown/unconfirmed, `success` only for "recorded/done" (never "safe"). Ring colors are not status colors.
/// 6. Icons: one leading symbol per card title or row, never decorative repeats; urgency/status icons sit in a fixed
///    trailing column; icon-only controls carry an accessibility label. Family = `person.2.fill`, home =
///    `house.fill`, card = `person.text.rectangle.fill`.
/// 7. Lists: at most `Theme.previewCount` items before "Show all"; caveats and method notes sit behind `InfoButton`.
/// 8. Forms: a field whose meaning could be confused once filled keeps a visible label (`LabeledTextField`).
enum Theme {
    // MARK: Color

    /// Warm off-white in light mode, near-black in dark mode.
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)
        : .white })
    static let surfaceMuted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1)
        : UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1) })
    static let ink = Color.primary
    static let inkSecondary = Color.secondary
    /// Deep teal; AA contrast on both backgrounds.
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.35, green: 0.78, blue: 0.80, alpha: 1)
        : UIColor(red: 0.04, green: 0.40, blue: 0.45, alpha: 1) })
    static let onAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static let caution = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.98, green: 0.72, blue: 0.28, alpha: 1)
        : UIColor(red: 0.62, green: 0.38, blue: 0.0, alpha: 1) })
    static let critical = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.45, blue: 0.40, alpha: 1)
        : UIColor(red: 0.70, green: 0.13, blue: 0.11, alpha: 1) })
    static let success = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1)
        : UIColor(red: 0.10, green: 0.45, blue: 0.20, alpha: 1) })

    // MARK: Layout

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }
    enum Radius {
        static let card: CGFloat = 16, control: CGFloat = 12, badge: CGFloat = 8, pill: CGFloat = 999
    }
    /// Minimum tap target (Apple HIG).
    static let minTap: CGFloat = 44
    /// Full-width buttons and choices: larger than the minimum so an unsteady hand still lands on them.
    static let comfortableTap: CGFloat = 52
    /// Ranked lists show this many items before "Show all".
    static let previewCount = 3

    // MARK: Progress rings (identity colors, not status: a full ring never means "safe")

    static let ringPractice = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.62, green: 0.66, blue: 1.0, alpha: 1)
        : UIColor(red: 0.27, green: 0.30, blue: 0.75, alpha: 1) })
    static let ringOverall = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.80, green: 0.62, blue: 0.95, alpha: 1)
        : UIColor(red: 0.45, green: 0.22, blue: 0.62, alpha: 1) })

    // MARK: Status

    static func color(for state: ServiceState) -> Color {
        switch state {
        case .operational: success
        case .degraded: caution
        case .unavailable: critical
        case .unknown: .secondary
        }
    }

    static func symbol(for state: ServiceState) -> String {
        switch state {
        case .operational: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func color(for severity: EventSeverity) -> Color {
        switch severity {
        case .info: accent
        case .caution: caution
        case .critical: critical
        }
    }

    static func symbol(for severity: EventSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

// MARK: - Components

/// A rounded content card. Use for every grouped block outside a List.
struct SectionCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    var tint: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(tint) }
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// The one obvious action on a screen. Full width, 52 pt tall.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.comfortableTap)
            .padding(.horizontal, Theme.Space.l)
            .foregroundStyle(Theme.onAccent)
            .background(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Secondary actions: outlined, same height as the primary so rows of actions line up.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.comfortableTap)
            .padding(.horizontal, Theme.Space.m)
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.4))
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(tint.opacity(isEnabled ? 0.45 : 0.2)))
            .contentShape(Rectangle())
    }
}

/// A large, full-width choice (decision options, setup answers). Never styled as "correct" or "wrong".
struct ChoiceButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: Theme.comfortableTap, alignment: .leading)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .foregroundStyle(Theme.ink)
            .background(selected ? Theme.accent.opacity(0.14) : Theme.surfaceMuted.opacity(configuration.isPressed ? 1 : 0.7),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
extension ButtonStyle where Self == ChoiceButtonStyle {
    static var choice: ChoiceButtonStyle { ChoiceButtonStyle() }
}

/// Icon + text status, e.g. "Not working". Color is never the only cue.
struct StatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, Theme.Space.xs + 1)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

/// Explains why a section is empty and offers the next step.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage).font(.system(size: 36)).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.primary).padding(.top, Theme.Space.s)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }
}

/// A row with a leading tinted icon, used in cards for facts and contacts.
struct IconRow<Trailing: View>: View {
    let systemImage: String
    var tint: Color = Theme.accent
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

extension IconRow where Trailing == EmptyView {
    init(systemImage: String, tint: Color = Theme.accent, title: String, subtitle: String? = nil) {
        self.init(systemImage: systemImage, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Phone number shown as text with an explicit call button. Never auto-dials.
struct PhoneRow: View {
    @Environment(AppModel.self) private var model
    let label: String
    let number: String
    var systemImage = "phone.fill"

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Text(number).font(.title3.weight(.semibold).monospacedDigit()).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if let url = PhoneLink.url(number) {
                Link(destination: url) {
                    Label(model.localizer("common.action.call"), systemImage: systemImage).labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(model.localizer("common.accessibility.call", ["name": label, "number": number]))
                .accessibilityHint(model.localizer("common.accessibility.callHint"))
            }
        }
    }
}

enum PhoneLink {
    /// tel: URL from the digits of a displayed number ("2-1-1" → tel:211). Nil when there are no digits.
    static func url(_ number: String) -> URL? {
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard (3...15).contains(digits.count) else { return nil }
        return URL(string: "tel:\(number.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : "")\(digits)")
    }
}

/// A row of equal controls that becomes a column at accessibility text sizes, so labels never wrap letter by letter.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    var spacing: CGFloat = Theme.Space.s
    @ViewBuilder var content: Content

    var body: some View {
        if size.isAccessibilitySize {
            VStack(spacing: spacing) { content }
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}

/// An in-card text action ("Show all", "Undo / reopen", "Correct"): semibold callout in the accent color, at least
/// `Theme.minTap` tall and leading-aligned so it lines up with the card's text edge.
struct InlineActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint.opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4))
            .multilineTextAlignment(.leading)
            .frame(minHeight: Theme.minTap, alignment: .leading)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == InlineActionButtonStyle {
    static var inline: InlineActionButtonStyle { InlineActionButtonStyle() }
}

/// "Show all 7" / "Show fewer" under a list that previews `Theme.previewCount` items. Absent when nothing is hidden.
struct ShowAllButton: View {
    @Environment(AppModel.self) private var model
    let total: Int
    @Binding var showAll: Bool
    var limit = Theme.previewCount

    var body: some View {
        if total > limit {
            Button(showAll ? model.localizer("ui.showFewer") : model.localizer("common.showAll", ["count": "\(total)"])) {
                showAll.toggle()
            }
            .buttonStyle(.inline)
        }
    }
}

/// An ⓘ button that reveals a caveat or method note in place, so the list itself leads. VoiceOver reads its label
/// and a selected trait while the note is open.
struct InfoButton: View {
    let label: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: Theme.minTap, minHeight: Theme.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }
}

/// A form text field whose purpose stays visible after something is typed: label leading, value trailing. Use it
/// wherever two fields could be confused once filled (a person's name vs their relationship).
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    /// Accessibility identifier for the text field itself (UI tests type into it), not the row.
    var fieldID: String?

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text, prompt: prompt.map { Text($0) })
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(fieldID ?? "")
        }
    }
}

/// The square symbol tile that leads a navigation card (scenario, practice check): one size and corner everywhere.
struct SymbolTile: View {
    let systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(tint)
            .frame(width: Theme.comfortableTap, height: Theme.comfortableTap)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Surface, corner and hairline shared by `SectionCard` and tappable navigation cards, so both read as one family.
    func cardSurface(padding: CGFloat = Theme.Space.l) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
    }
}
