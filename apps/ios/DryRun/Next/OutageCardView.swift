import SwiftUI
import DryRunCore

/// Universal household emergency card, with intentionally selected clinical information.
/// The legacy type name remains for existing entry points; device continuity is supporting content.
struct OutageCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// One sheet slot: two `.sheet` modifiers on one view fail to present the second right after the first closes.
    @State private var sheet: ActiveSheet?
    @State private var selection = FamilyCardSelection()
    /// Shown only when presented modally; when pushed, the back button is the way out.
    var showsDone = false

    enum ActiveSheet: Identifiable {
        case edit(String)
        case preview(URL)
        var id: String {
            switch self {
            case .edit(let id): "edit-\(id)"
            case .preview(let url): "preview-\(url.lastPathComponent)"
            }
        }
    }

    var body: some View {
        let l = model.localizer
        let doc = model.outageCard(selection: selection)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let banner = doc?.draftTranslationBanner {
                    Label(banner, systemImage: "character.bubble").font(.footnote.weight(.semibold)).foregroundStyle(Theme.caution)
                }
                if let doc, !doc.pages.isEmpty {
                    ForEach(doc.pages) { page in
                        CardPageView(page: page) { if case .outageCard(let id) = page.kind { sheet = .edit(id) } }
                    }
                    SectionCard(title: l("family.selected"), systemImage: "checklist") {
                        Toggle(l("family.critical"), isOn: $selection.includeCriticalInformation)
                        Toggle(l("family.medication"), isOn: $selection.includeMedication)
                        Toggle(l("family.instructions"), isOn: $selection.includeResponderInstructions)
                        Toggle(l("family.contacts"), isOn: $selection.includeContacts)
                        Text(l("family.selectedWhy")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { share(doc) } label: { Label(l("ui.card.printShare"), systemImage: "printer") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("card.share")
                    Text(l("common.privacy.shareBoundary")).font(.footnote).foregroundStyle(.secondary)
                    Text(doc.footer).font(.footnote).foregroundStyle(.secondary)
                } else {
                    EmptyStateView(title: l("ui.card.emptyTitle"), message: l("ui.card.emptyMessage"),
                                   systemImage: "bolt.heart", actionTitle: l("ui.card.addDevice")) {
                        sheet = .edit(MedicalSetupView.newDeviceID)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("ui.card.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } }
            }
            if doc?.pages.isEmpty == false {
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .edit(MedicalSetupView.newDeviceID) } label: {
                        Label(l("ui.card.addDevice"), systemImage: "plus")
                    }.accessibilityIdentifier("card.addDevice")
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            // Only a preview leaves a plaintext export behind; purging when the editor closes is harmless.
            TemporaryExports.hasActiveExport = false
            TemporaryExports.purgeAll()
        }) { active in
            switch active {
            case .edit(let id): NavigationStack { MedicalSetupView(equipmentID: id) }
            case .preview(let url): PDFPreviewSheet(url: url, note: nil)
            }
        }
    }

    private func share(_ doc: PlanDocument) {
        let output = PlanPDFRenderer().render(doc)
        do {
            let url = try TemporaryExports.write(output.data, name: "DryRun-family-card-\(doc.locale).pdf")
            TemporaryExports.hasActiveExport = true
            sheet = .preview(url)
        } catch {
            model.lastError = String(describing: error)
        }
    }
}

/// The phone view of one card page. Same section order and vocabulary as the PDF: a heading band per section,
/// critical information inverted, people and contacts as rows, missing information in italics, never blank.
struct CardPageView: View {
    @Environment(AppModel.self) private var model
    let page: PlanPage
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(page.title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let review = page.sections.first(where: { $0.id == "review" })?.lines.first {
                Label(model.localizer("pdf.lastReviewed") + ": " + (review.parts?.fields.first?.value ?? review.text), systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(review.parts?.isMissing == true ? Theme.caution : .secondary)
            }
            ForEach(page.sections.filter { $0.id != "review" }) { section in
                if section.id == "identity" {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            if line.style == .caveat {
                                StatusPill(text: line.text, systemImage: "sparkles", tint: Theme.caution)
                            } else {
                                Text(line.text)
                                    .font(line.parts?.subject != nil ? .headline : (line.parts?.isMissing == true ? .callout.italic() : .callout))
                                    .foregroundStyle(line.parts?.isMissing == true ? .secondary : .primary)
                            }
                        }
                    }
                } else {
                    CardSectionView(section: section, onFix: onFix)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.ink.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.page")
    }

    static func icon(_ sectionID: String) -> String { PlanPDFRenderer.symbol(for: sectionID) }
}

struct CardSectionView: View {
    @Environment(AppModel.self) private var model
    let section: PlanSection
    var onFix: () -> Void = {}

    private var critical: Bool { section.isSafetyCritical && section.id != "contacts" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(section.heading.uppercased(), systemImage: CardPageView.icon(section.id))
                .font(.caption.weight(.bold))
                .kerning(0.4)
                .foregroundStyle(critical ? Color(uiColor: .systemBackground) : Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(critical ? Theme.ink : Theme.ink.opacity(0.08))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { Divider() }
                    CardLine(line: line, sectionID: section.id)
                }
                if section.id == "gaps" {
                    Button(action: onFix) { Label(model.localizer("ui.card.fix"), systemImage: "square.and.pencil") }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.caution))
                        .accessibilityIdentifier("card.fix")
                }
            }
            .padding(10)
        }
        .overlay(Rectangle().strokeBorder(critical ? Theme.ink : Theme.ink.opacity(0.3), lineWidth: critical ? 2 : 1))
    }
}

struct CardLine: View {
    @Environment(AppModel.self) private var model
    let line: PlanLine
    var sectionID = ""

    var body: some View {
        Group {
            if let parts = line.parts {
                structured(parts)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(line.text)
                        .font(line.style == .caveat ? .callout : .body)
                        .foregroundStyle(line.style == .caveat ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if line.isFallback {
                        Text("EN").font(.caption2.weight(.bold)).padding(2).border(.secondary).accessibilityLabel(model.localizer("common.fallbackShown"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func structured(_ parts: PlanLineParts) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let subject = parts.subject {
                HStack(alignment: .firstTextBaseline) {
                    Text(subject).font(.headline)
                    Spacer(minLength: 8)
                    if let phone = parts.phone {
                        if let url = PhoneLink.url(phone) {
                            Link(destination: url) { Label(phone, systemImage: "phone.fill").font(.body.monospacedDigit().weight(.semibold)) }
                                .accessibilityHint(model.localizer("common.help.call"))
                        } else {
                            Text(phone).font(.body.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
            if let detail = parts.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            ForEach(Array(parts.fields.enumerated()), id: \.offset) { _, field in
                Group {
                    if let label = field.label {
                        Text(label + ": ").fontWeight(.semibold) + Text(field.value)
                    } else {
                        Text(field.value)
                    }
                }
                .font(parts.isMissing ? .callout.italic() : .callout)
                .foregroundStyle(parts.isMissing ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
