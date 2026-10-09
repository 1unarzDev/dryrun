import SwiftUI
import PDFKit
import DryRunCore

struct PlanTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = ["home-fire", "freeze-power-loss"]
    @State private var includePrivateNotes = false
    @State private var exportURL: URL?
    @State private var showPreview = false
    @State private var exportNote: String?

    var body: some View {
        @Bindable var model = model
        let l = model.localizer
        List {
            Section(l("common.plan.language")) {
                Picker("Plan language", selection: $model.locale) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                if model.locale != "en" {
                    Label(l("common.draftTranslation"), systemImage: "character.bubble").foregroundStyle(Theme.caution)
                }
            }
            Section(l("common.plan.scenarioPages")) {
                ForEach(RehearseTabView.scenarioIDs, id: \.self) { id in
                    Toggle(l("common.scenario.\(id)"), isOn: Binding(
                        get: { selected.contains(id) },
                        set: { if $0 { selected.insert(id) } else { selected.remove(id) } }))
                }
                Toggle(l("common.plan.includePrivate"), isOn: $includePrivateNotes)
                Button(l("common.plan.generate"), systemImage: "doc.badge.gearshape") {
                    Task { await model.generatePlan(scenarioIDs: Array(selected), includePrivateNotes: includePrivateNotes) }
                }
                .disabled(selected.isEmpty || model.isWorking)
            }
            if let plan = model.savedPlan {
                Section {
                    if model.planIsStale {
                        Label(l("common.plan.stale"),
                              systemImage: "exclamationmark.arrow.circlepath")
                            .foregroundStyle(Theme.caution)
                    }
                    NavigationLink(l("common.plan.viewSaved", ["count": "\(plan.pages.count)"])) { PlanDocumentView(doc: plan) }
                    Button(l("common.action.share") + " / " + l("common.action.print"), systemImage: "square.and.arrow.up") {
                        let output = PlanPDFRenderer().render(plan)
                        do {
                            exportURL = try TemporaryExports.write(output.data, name: "DryRun-plan-\(plan.locale).pdf")
                            TemporaryExports.hasActiveExport = true
                            exportNote = output.continuedPageIDs.isEmpty ? nil : l("common.plan.continued")
                            showPreview = true
                        } catch {
                            model.lastError = String(describing: error)
                        }
                    }
                } footer: {
                    Text(l("common.privacy.shareBoundary"))
                }
            }
            if let h = model.household {
                Section(l("common.plan.preparations")) {
                    if h.completedPreparations.isEmpty { Text(l("common.plan.noneCompleted")) }
                    ForEach(h.completedPreparations, id: \.actionID) { p in
                        Label(l("action.\(p.actionID).title"), systemImage: "checkmark.circle.fill")
                    }
                }
            }
        }
        .navigationTitle(l("common.tab.plan"))
        .sheet(isPresented: $showPreview, onDismiss: {
            TemporaryExports.hasActiveExport = false
            TemporaryExports.purgeAll()
            exportURL = nil
        }) {
            if let exportURL { PDFPreviewSheet(url: exportURL, note: exportNote) }
        }
    }

    private var languages: [(code: String, label: String)] {
        [("en", "English"), ("es", "Español"), ("vi", "Tiếng Việt")]
    }
}

/// Native, accessible rendering of the same PlanDocument used for the PDF.
struct PlanDocumentView: View {
    let doc: PlanDocument

    var body: some View {
        List {
            if let banner = doc.draftTranslationBanner {
                Label(banner, systemImage: "exclamationmark.bubble").foregroundStyle(Theme.caution).font(.callout.weight(.semibold))
            }
            if let note = doc.fallbackNote { Text(note).font(.footnote) }
            if let content = doc.contentReviewBanner { Text(content).font(.footnote).foregroundStyle(.secondary) }
            ForEach(doc.pages) { page in
                Section {
                    ForEach(page.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.heading).font(.headline)
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: icon(line.style)).accessibilityHidden(true)
                                    Text(line.text).font(line.style == .prohibition ? .body.weight(.semibold) : .body)
                                    if line.isFallback {
                                        Text("EN").font(.caption2.weight(.bold)).padding(2).border(.secondary)
                                            .accessibilityLabel("Shown in English")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(page.title).font(.title3.weight(.bold)).textCase(nil)
                }
            }
            Section { Text(doc.footer).font(.footnote) }
        }
        .navigationTitle("Plan")
    }

    private func icon(_ style: PlanLineStyle) -> String {
        switch style {
        case .prohibition: "exclamationmark.triangle"
        case .contact: "phone"
        case .caveat: "info.circle"
        case .normal: "circle.fill"
        }
    }
}

struct PDFPreviewSheet: View {
    let url: URL
    let note: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let note { Text(note).font(.footnote).padding(8) }
                PDFKitView(url: url)
            }
            .navigationTitle("Plan preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    // Explicit user actions only; sharing moves a copy outside the vault.
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button("Print", systemImage: "printer") { Printing.print(url: url) }
                }
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

enum Printing {
    @MainActor
    static func print(url: URL) {
        guard UIPrintInteractionController.canPrint(url) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Dry Run plan"
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}
