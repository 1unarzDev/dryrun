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
                SectionCard(title: l("family.selected"), systemImage: "checklist") {
                    Toggle(l("family.critical"), isOn: $selection.includeCriticalInformation)
                    Toggle(l("family.medication"), isOn: $selection.includeMedication)
                    Toggle(l("family.instructions"), isOn: $selection.includeResponderInstructions)
                    Toggle(l("family.contacts"), isOn: $selection.includeContacts)
                    Text(l("family.selectedWhy")).font(.footnote).foregroundStyle(.secondary)
                }
                if let banner = doc?.draftTranslationBanner {
                    Label(banner, systemImage: "character.bubble").font(.footnote.weight(.semibold)).foregroundStyle(Theme.caution)
                }
                if let doc, !doc.pages.isEmpty {
                    ForEach(doc.pages) { page in
                        CardPageView(page: page) { if case .outageCard(let id) = page.kind { sheet = .edit(id) } }
                    }
                    if selection.includeContacts {
                        ForEach(model.household?.contacts ?? []) { contact in
                            if let url = contact.telephoneURL {
                                Link(destination: url) { Label(contact.alias + " · " + (contact.phone ?? ""), systemImage: "phone") }
                            }
                        }
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
            ToolbarItem(placement: .confirmationAction) { Button(l("common.done")) { dismiss() } }
            if doc?.pages.isEmpty == false {
                ToolbarItem(placement: .topBarLeading) {
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

/// One device's card. Large type, sections in reading order, phone numbers as text with an explicit call button.
struct CardPageView: View {
    @Environment(AppModel.self) private var model
    let page: PlanPage
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label(page.title, systemImage: "bolt.heart.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.critical)
                .accessibilityAddTraits(.isHeader)
            ForEach(page.sections) { section in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label(section.heading, systemImage: Self.icon(section.id))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(section.id == "gaps" ? Theme.caution : Theme.accent)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        CardLine(line: line)
                    }
                    if section.id == "gaps" {
                        Button(action: onFix) { Label(model.localizer("ui.card.fix"), systemImage: "square.and.pencil") }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.caution))
                            .accessibilityIdentifier("card.fix")
                    }
                }
                if section.id != page.sections.last?.id { Divider() }
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.critical.opacity(0.35), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.page")
    }

    static func icon(_ sectionID: String) -> String {
        switch sectionID {
        case "device": "person.fill"
        case "backup": "battery.100.bolt"
        case "steps": "list.number"
        case "contacts": "phone.fill"
        case "goTo": "house.fill"
        case "help": "cross.case.fill"
        case "gaps": "questionmark.circle.fill"
        default: "circle"
        }
    }
}

struct CardLine: View {
    @Environment(AppModel.self) private var model
    let line: PlanLine

    var body: some View {
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
