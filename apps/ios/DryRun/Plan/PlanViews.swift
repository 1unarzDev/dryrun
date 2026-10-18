import SwiftUI
import UIKit
import PDFKit
import MapKit
import DryRunCore

struct PlanTabView: View {
    @Environment(AppModel.self) private var model
    @State private var includePrivateNotes = false
    @State private var selection = FamilyCardSelection()
    @State private var exportURL: URL?
    @State private var showingMap = false
    @State private var showingAddress = false
    @State private var showingContacts = false
    @State private var selectedScenarios: Set<String> = []
    @State private var showingExport = false
    @State private var exporting = false
    @State private var previewDocument: PlanDocument?
    @State private var showingDocument = false
    @State private var paper: PlanPDFRenderer.Paper = .letter
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }
    var body: some View {
        List {
            if let doc = model.currentPlan(selection: selection, includePrivateNotes: includePrivateNotes) {
                Section {
                    NavigationLink { OutageCardView() } label: { Label(model.localizer("family.title"), systemImage: "person.text.rectangle") }
                        .accessibilityIdentifier("plan.familyCard")
                    ForEach(doc.pages.first?.sections.prefix(2) ?? []) { section in
                        VStack(alignment: .leading, spacing: 5) { Text(section.heading).font(.headline); ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in Text(line.text).font(.callout) } }
                    }
                }
                Section { Button(model.localizer("family.contacts")) { showingContacts = true } }
                Section(t("home")) {
                    if let home = model.home {
                        if home.source == .sample { Label(model.localizer("family.example"), systemImage: "sparkles").font(.caption) }
                        FloorPlanView(home: home, routes: [], highlightedFloorID: nil).frame(minHeight: 240)
                        NavigationLink(t("editHome")) { HomeTabView() }
                    } else { Text(t("layoutMissing")).foregroundStyle(.secondary); NavigationLink(t("editHome")) { HomeTabView() } }
                    Button(t("homeAddress")) { showingAddress = true }.accessibilityIdentifier("plan.address")
                }
                Section(t("neighborhood")) {
                    if let snapshot = doc.visualSnapshot, snapshot.homeCoordinate != nil || snapshot.savedPlaces.contains(where: { $0.coordinate != nil }) { NeighborhoodPlanPreview(snapshot: snapshot).frame(height: 190) }
                    else { Text(t("noHome")).font(.callout).foregroundStyle(.secondary) }
                    ForEach(model.savedPlaces) { place in
                        VStack(alignment: .leading) { Text(place.label).font(.headline); if let address = place.addressText { Text(address) }; if let instructions = place.findingInstructions { Text(instructions).font(.caption) } }
                    }
                    Button(t("choosePlaces")) { showingMap = true }.accessibilityIdentifier("plan.map")
                }
                Section(t("selectedContent")) {
                    Text(t("diagramScope")).font(.caption).foregroundStyle(.secondary)
                    Toggle(model.localizer("family.critical"), isOn: $selection.includeCriticalInformation)
                    Toggle(model.localizer("family.medication"), isOn: $selection.includeMedication)
                    Toggle(model.localizer("family.instructions"), isOn: $selection.includeResponderInstructions)
                    Toggle(model.localizer("family.contacts"), isOn: $selection.includeContacts)
                    Toggle(model.localizer("common.plan.includePrivate"), isOn: $includePrivateNotes)
                    Picker(t("paper"), selection: $paper) { Text("Letter").tag(PlanPDFRenderer.Paper.letter); Text("A4").tag(PlanPDFRenderer.Paper.a4) }
                    DisclosureGroup(model.localizer("common.plan.scenarioPages")) {
                        ForEach(RehearseTabView.scenarioIDs, id: \.self) { id in Toggle(model.localizer("common.scenario.\(id)"), isOn: Binding(get: { selectedScenarios.contains(id) }, set: { if $0 { selectedScenarios.insert(id) } else { selectedScenarios.remove(id) } })) }
                    }
                    Button(t("selectedPreview")) { prepareDocument(export: false) }.accessibilityIdentifier("plan.viewSaved")
                    Button(model.localizer("common.action.share") + " / " + model.localizer("common.action.print"), systemImage: "square.and.arrow.up") { prepareDocument(export: true) }
                    if exporting { ProgressView() }
                }
                Section { NavigationLink(t("official")) { HelpTabView() } }
                if let saved = model.savedPlan, !saved.scenarioIDs.isEmpty {
                    Section {
                        if model.planIsStale { Label(model.localizer("common.plan.stale"), systemImage: "exclamationmark.arrow.circlepath").foregroundStyle(Theme.caution) }
                        NavigationLink(model.localizer("common.plan.viewSaved", ["count": "\(saved.pages.count)"])) { PlanDocumentView(doc: saved) }
                    }
                }
            } else { Text(t("noHousehold")) }
        }
        .disabled(exporting)
        .navigationTitle(model.localizer("common.tab.plan"))
        .navigationDestination(isPresented: $showingDocument) { if let previewDocument { PlanDocumentView(doc: previewDocument, paper: paper) } }
        .sheet(isPresented: $showingMap) {
            if let store = model.regionalResources { MapPlanningView(store: store) }
            else if let content = model.content { MapPlanningView(content: content, client: model.publicClient, regionID: model.household?.regionID ?? "") }
        }
        .sheet(isPresented: $showingContacts) { NavigationStack { FocusedHouseholdEditor(focus: .contacts) } }
        .sheet(isPresented: $showingAddress) { HomeAddressEditorView() }
        .sheet(isPresented: $showingExport, onDismiss: { TemporaryExports.hasActiveExport = false; TemporaryExports.purgeAll(); exportURL = nil }) { if let exportURL { PDFPreviewSheet(url: exportURL, note: nil) } }
    }
    /// Both actions commit the same current selected document. Choices stay locked through map preparation.
    private func prepareDocument(export: Bool) {
        let chosenSelection = selection
        let chosenNotes = includePrivateNotes
        let chosenScenarios = selectedScenarios.sorted()
        let chosenPaper = paper
        exporting = true
        Task { @MainActor in
            defer { exporting = false }
            guard let doc = await model.generatePlan(scenarioIDs: chosenScenarios, includePrivateNotes: chosenNotes, selection: chosenSelection) else { return }
            guard selection == chosenSelection, includePrivateNotes == chosenNotes, selectedScenarios.sorted() == chosenScenarios else { return }
            if !export { previewDocument = doc; showingDocument = true; return }
            var panels: [PlanMapPanel] = []
            if let snapshot = doc.visualSnapshot { panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: t("neighborhood")) }
            guard selection == chosenSelection, includePrivateNotes == chosenNotes, selectedScenarios.sorted() == chosenScenarios, paper == chosenPaper,
                  model.documentIsCurrent(doc) else { return }
            let result = PlanPDFRenderer().render(doc, paper: chosenPaper, mapPanels: panels)
            do { exportURL = try TemporaryExports.write(result.data, name: "DryRun-family-plan-\(doc.locale).pdf"); TemporaryExports.hasActiveExport = true; showingExport = true }
            catch { model.lastError = String(describing: error) }
        }
    }

}

/// Native, accessible rendering of the same PlanDocument used for the PDF.
struct PlanDocumentView: View {
    @Environment(AppModel.self) private var model
    let doc: PlanDocument
    var paper: PlanPDFRenderer.Paper = .letter

    var body: some View {
        List {
            if let banner = doc.draftTranslationBanner {
                Label(banner, systemImage: "exclamationmark.bubble").foregroundStyle(Theme.caution).font(.callout.weight(.semibold))
            }
            if let note = doc.fallbackNote { Text(note).font(.footnote) }
            if let content = doc.contentReviewBanner { Text(content).font(.footnote).foregroundStyle(.secondary) }
            ForEach(doc.pages.filter { $0.id == "family-card" }) { page in pageSection(page) }
            if let snapshot = doc.visualSnapshot {
                if let home = snapshot.home {
                    ForEach(snapshot.homePanels) { panel in
                        Section(panel.title(in: snapshot)) {
                            FloorPlanView(home: home, routes: panel.paths, highlightedFloorID: panel.floorID,
                                          spatialState: panel.spatialState, selectedRoute: panel.route).frame(minHeight: 260)
                            ForEach(Array((snapshot.panelDetails?[panel.id] ?? panel.details(in: snapshot, localizer: model.localizer.with(locale: doc.locale))).enumerated()), id: \.offset) { _, detail in Text(detail).font(.callout) }
                        }
                    }
                }
                if snapshot.savedPlaces.contains(where: { $0.coordinate != nil }) || snapshot.homeCoordinate != nil {
                    Section(model.localizer("map.neighborhood")) { NeighborhoodPlanPreview(snapshot: snapshot).frame(height: 220); Text(model.localizer("map.offline")).font(.caption) }
                }
            }
            ForEach(doc.pages.filter { $0.id != "family-card" }) { page in pageSection(page) }
            Section { Text(doc.footer).font(.footnote) }
        }
        .navigationTitle(model.localizer("common.tab.plan"))
        .toolbar { PlanShareButton(doc: doc, paper: paper) }
    }

    private func pageSection(_ page: PlanPage) -> some View {
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
                                    .accessibilityLabel(model.localizer("plan.fallbackNote"))
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
    @Environment(AppModel.self) private var model
    @State private var showingActivity = false
    let url: URL
    let note: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let note { Text(note).font(.footnote).padding(8) }
                PDFKitView(url: url).accessibilityIdentifier("pdf.preview")
            }
            .navigationTitle(model.localizer("map.selectedPreview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.localizer("map.done")) { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    // Explicit user actions only; sharing moves a copy outside the vault.
                    Button { showingActivity = true } label: { Label(model.localizer("common.action.share"), systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button(model.localizer("common.action.print"), systemImage: "printer") { Printing.print(url: url) }
                }
            }
        }
        .sheet(isPresented: $showingActivity) { ExportActivityView(url: url) { showingActivity = false } }
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
        let lease = ExportActivityView.Coordinator()
        lease.retain()
        let presented = controller.present(animated: true) { _, _, _ in Task { @MainActor in lease.release() } }
        if !presented { lease.release() }
    }
}

/// Live map only; saved text remains the offline alternative. Indoor coordinates are never overlaid here.
struct NeighborhoodPlanPreview: View {
    @Environment(AppModel.self) private var model
    let snapshot: PlanVisualSnapshot
    var body: some View {
        Map {
            if let coordinate = snapshot.homeCoordinate { Marker(model.localizer("map.home"), systemImage: "house.fill", coordinate: coordinate.cl) }
            ForEach(Array(snapshot.savedPlaces.enumerated()), id: \.element.id) { index, place in
                if let coordinate = place.coordinate { Marker("\(index + 1). \(place.label)", coordinate: coordinate.cl).tint(place.purpose == .outsideMeetingPoint ? .green : .orange) }
            }
        }.mapStyle(.standard(pointsOfInterest: .excludingAll))
            .accessibilityLabel(snapshot.savedPlaces.map(\.label).joined(separator: ", "))
    }
}


/// Holds a protected file lease until the system activity actually finishes/cancels.
struct ExportActivityView: UIViewControllerRepresentable {
    let url: URL
    let onComplete: @MainActor @Sendable () -> Void
    @MainActor final class Coordinator {
        var retained = false
        func retain() { guard !retained else { return }; retained = true; TemporaryExports.retainActivity() }
        func release() { guard retained else { return }; retained = false; TemporaryExports.releaseActivity() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        context.coordinator.retain()
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let coordinator = context.coordinator
        let completed = onComplete
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in coordinator.release(); completed() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) { coordinator.release() }
}


struct PlanShareButton: View {
    @Environment(AppModel.self) private var model
    let doc: PlanDocument
    var paper: PlanPDFRenderer.Paper = .letter
    @State private var url: URL?
    @State private var preview = false
    @State private var working = false
    var body: some View {
        Button {
            let startingKey = model.currentKey; let startingPlaces = model.savedPlaces; let startingLocale = model.locale
            working = true; Task { @MainActor in
            defer { working = false }
            var panels: [PlanMapPanel] = []
            if let snapshot = doc.visualSnapshot { panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: model.localizer("map.neighborhood")) }
            guard model.currentKey == startingKey, model.savedPlaces == startingPlaces, model.locale == startingLocale else { return }
            do {
                url = try TemporaryExports.write(PlanPDFRenderer().render(doc, paper: paper, mapPanels: panels).data, name: "DryRun-preview-\(UUID().uuidString).pdf")
                TemporaryExports.hasActiveExport = true; preview = true
            } catch { model.lastError = String(describing: error) }
        } } label: { Label(model.localizer("common.action.share"), systemImage: working ? "hourglass" : "square.and.arrow.up") }
            .disabled(working)
            .sheet(isPresented: $preview, onDismiss: { TemporaryExports.hasActiveExport = false; TemporaryExports.purgeAll(); url = nil }) { if let url { PDFPreviewSheet(url: url, note: nil) } }
    }
}
