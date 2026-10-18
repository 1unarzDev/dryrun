import SwiftUI
import UIKit
import PDFKit
import MapKit
import DryRunCore

/// Plan: the family's living plan, shown as it is entered. No scenario choice or Generate step is needed for the
/// basic card; scenario pages and paper size are offered only when sharing.
struct PlanTabView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: PlanSheet?

    enum PlanSheet: Identifiable {
        case address, contacts, newContact, meetup(SavedPlacePurpose), map, share
        var id: String {
            switch self {
            case .address: "address"; case .contacts: "contacts"; case .newContact: "newContact"
            case .meetup(let p): "meetup-\(p.rawValue)"; case .map: "map"; case .share: "share"
            }
        }
    }

    private func t(_ key: String) -> String { model.localizer("map.\(key)") }

    var body: some View {
        let l = model.localizer
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let household = model.household, let doc = model.currentPlan(selection: FamilyCardSelection(includeCriticalInformation: true, includeMedication: true, includeContacts: true)) {
                    header(household)
                    cardSummary(doc)
                    meetups(household)
                    contacts(household)
                    neighborhood(doc)
                    homeSection
                    Button { sheet = .share } label: { Label(l("common.action.share") + " / " + l("common.action.print"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("plan.share")
                    NavigationLink { HelpTabView() } label: { Label(t("official"), systemImage: "building.columns") }
                        .frame(minHeight: Theme.minTap)
                    if let saved = model.savedPlan, !saved.scenarioIDs.isEmpty {
                        NavigationLink { PlanDocumentView(doc: saved) } label: {
                            Label(l("common.plan.viewSaved", ["count": "\(saved.pages.count)"]), systemImage: "doc.richtext")
                        }
                        .frame(minHeight: Theme.minTap)
                        .accessibilityIdentifier("plan.viewSaved")
                        if model.planIsStale { Label(l("common.plan.stale"), systemImage: "exclamationmark.arrow.circlepath").font(.footnote).foregroundStyle(Theme.caution) }
                    }
                } else {
                    Text(t("noHousehold"))
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(l("common.tab.plan"))
        .sheet(item: $sheet) { which in
            switch which {
            case .address: HomeAddressEditorView()
            case .contacts: NavigationStack { FocusedHouseholdEditor(focus: .contacts) }
            case .newContact: NavigationStack { FocusedHouseholdEditor(focus: .newContact(.other)) }
            case .meetup(let purpose): MeetingPlaceChooser(purpose: purpose)
            case .map: MeetingPlaceChooser(purpose: nil)
            case .share: NavigationStack { FamilyPlanShareView() }
            }
        }
    }

    private func header(_ household: HouseholdProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(household.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if household.isFictional { StatusPill(text: model.localizer("family.example"), systemImage: "house", tint: Theme.caution) }
            Text(model.localizer("ui.plan.headline")).font(.title2.weight(.bold))
            Text(model.localizer("ui.plan.subhead")).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// The living card: what a responder would read first, plus what is still missing. Opens the full card.
    private func cardSummary(_ doc: PlanDocument) -> some View {
        let l = model.localizer
        let page = doc.pages.first { $0.id == "family-card" }
        let missing = (page?.sections ?? []).filter { ["identity", "critical", "contacts", "outsideMeetingPoint", "backupMeetingPlace", "review"].contains($0.id) }
            .flatMap { section in section.lines.filter { $0.parts?.isMissing == true }.map { _ in section.id == "identity" ? t("homeAddress") : section.heading } }
        return NavigationLink { OutageCardView() } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Label(l("family.title"), systemImage: "person.text.rectangle.fill").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if let critical = page?.sections.first(where: { $0.id == "critical" }) {
                    ForEach(Array(critical.lines.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line.text).font(.callout).lineLimit(2).foregroundStyle(line.parts?.isMissing == true ? .secondary : .primary)
                    }
                }
                if missing.isEmpty {
                    StatusPill(text: l("ui.plan.cardComplete"), systemImage: "checkmark.circle", tint: Theme.success)
                } else {
                    Text(l("ui.plan.missing", ["items": Array(NSOrderedSet(array: missing)).compactMap { $0 as? String }.joined(separator: ", ")]))
                        .font(.footnote).foregroundStyle(Theme.caution)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.ink.opacity(0.25)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.familyCard")
    }

    /// Two fixed slots, matching the Red Cross's two meetup purposes. Each opens the map already set to that purpose.
    private func meetups(_ household: HouseholdProfile) -> some View {
        let l = model.localizer
        let places = model.savedPlaces.filter { $0.homeID == household.stableHomeID }
        return SectionCard(title: l("pdf.meetingPlaces"), systemImage: "figure.2") {
            ForEach([SavedPlacePurpose.outsideMeetingPoint, .backupMeetingPlace], id: \.self) { purpose in
                let place = places.first { $0.purpose == purpose }
                Button { sheet = .meetup(purpose) } label: {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Text(purpose == .outsideMeetingPoint ? "1" : "2")
                            .font(.headline.monospacedDigit()).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 28, height: 28).background(Theme.ink, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l(purpose == .outsideMeetingPoint ? "family.nearMeetup" : "family.backupMeetup")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if let place {
                                Text(place.label).font(.body.weight(.semibold))
                                if let address = place.addressText, !address.isEmpty { Text(address).font(.footnote) }
                                if let instructions = place.findingInstructions, !instructions.isEmpty { Text(instructions).font(.footnote).foregroundStyle(.secondary) }
                            } else {
                                Text(l("ui.plan.chooseMeetup")).font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: place == nil ? "plus.circle.fill" : "pencil").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: Theme.minTap)
                .accessibilityIdentifier("plan.meetup.\(purpose.rawValue)")
                if purpose == .outsideMeetingPoint { Divider() }
            }
        }
    }

    private func contacts(_ household: HouseholdProfile) -> some View {
        let l = model.localizer
        return SectionCard(title: l("family.contacts"), systemImage: "phone.fill") {
            if household.contacts.isEmpty {
                Text(l("family.contactMissing")).font(.callout.italic()).foregroundStyle(.secondary)
            }
            ForEach(household.contacts) { contact in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.alias).font(.body.weight(.semibold))
                        let detail = [contact.relationship, contact.role == .other ? nil : l("ui.contact.role.\(contact.role.rawValue)")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                    if let phone = contact.phone, contact.hasUsablePhone, let url = PhoneLink.url(phone) {
                        Link(destination: url) { Label(phone, systemImage: "phone.fill").font(.callout.monospacedDigit().weight(.semibold)) }
                    } else {
                        Text(l("family.phoneMissing")).font(.footnote.italic()).foregroundStyle(Theme.caution)
                    }
                }
            }
            AdaptiveStack(spacing: Theme.Space.s) {
                Button { sheet = .newContact } label: { Label(l("prep.contact.title"), systemImage: "person.crop.circle.badge.plus") }
                    .buttonStyle(.secondary).accessibilityIdentifier("plan.addContact")
                if !household.contacts.isEmpty {
                    Button { sheet = .contacts } label: { Label(l("ui.plan.editContacts"), systemImage: "pencil") }
                        .buttonStyle(.secondary).accessibilityIdentifier("plan.editContacts")
                }
            }
        }
    }

    private func neighborhood(_ doc: PlanDocument) -> some View {
        let l = model.localizer
        return SectionCard(title: t("neighborhood"), systemImage: "map") {
            if let snapshot = doc.visualSnapshot, snapshot.homeCoordinate != nil || snapshot.savedPlaces.contains(where: { $0.coordinate != nil }) {
                NeighborhoodPlanPreview(snapshot: snapshot)
            } else {
                Text(t("noHome")).font(.callout).foregroundStyle(.secondary)
            }
            if let address = model.household?.privateLocation?.addressLine {
                Label(address, systemImage: "house.fill").font(.footnote)
            }
            AdaptiveStack(spacing: Theme.Space.s) {
                Button { sheet = .address } label: { Label(t("homeAddress"), systemImage: "house") }
                    .buttonStyle(.secondary).accessibilityIdentifier("plan.address")
                Button { sheet = .map } label: { Label(l("ui.plan.openMap"), systemImage: "map") }
                    .buttonStyle(.secondary).accessibilityIdentifier("plan.map")
            }
        }
    }

    private var homeSection: some View {
        SectionCard(title: t("home"), systemImage: "house.fill") {
            if let home = model.home {
                if home.source == .sample { StatusPill(text: model.localizer("family.example"), systemImage: "sparkles", tint: Theme.caution) }
                FloorPlanView(home: home, routes: [], highlightedFloorID: nil).frame(minHeight: 240)
                    .accessibilityLabel(model.localizer("ui.plan.homeDiagram", ["rooms": "\(home.spaces.count)"]))
            } else {
                Text(t("layoutMissing")).font(.callout).foregroundStyle(.secondary)
            }
            NavigationLink { HomeTabView() } label: { Label(t("editHome"), systemImage: "square.and.pencil") }
                .frame(minHeight: Theme.minTap)
                .accessibilityIdentifier("plan.editHome")
        }
    }
}

/// One share/print flow for the card and full plan. The family chooses what goes out and the paper size, sees what
/// is still unknown and the sharing boundary, then previews the exact PDF that Share and Print use. The preview is
/// pushed inside this sheet, so there is never a sheet on a sheet.
struct FamilyPlanShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includePlan = true
    @State private var includePrivateNotes = false
    @State private var selection = FamilyCardSelection(includeCriticalInformation: true, includeContacts: true)
    @State private var selectedScenarios: Set<String> = []
    @State private var paper: PlanPDFRenderer.Paper = Locale.current.region?.identifier == "US" ? .letter : .a4
    @State private var preparing = false
    @State private var exportURL: URL?
    @State private var showingPreview = false
    @State private var failed = false

    var body: some View {
        let l = model.localizer
        Form {
            Section {
                Toggle(l("family.critical"), isOn: $selection.includeCriticalInformation)
                Toggle(l("family.medication"), isOn: $selection.includeMedication)
                Toggle(l("family.instructions"), isOn: $selection.includeResponderInstructions)
                Toggle(l("family.contacts"), isOn: $selection.includeContacts)
                Text(l("family.selectedWhy")).font(.footnote).foregroundStyle(.secondary)
            } header: { Text(l("family.selected")) }
            Section {
                Toggle(isOn: $includePlan) { Label(l("ui.share.plan"), systemImage: "doc.text") }
                    .accessibilityIdentifier("share.includePlan")
                if includePlan {
                    DisclosureGroup(l("common.plan.scenarioPages")) {
                        ForEach(RehearseTabView.scenarioIDs, id: \.self) { id in
                            Toggle(l("common.scenario.\(id)"), isOn: Binding(get: { selectedScenarios.contains(id) },
                                set: { if $0 { selectedScenarios.insert(id) } else { selectedScenarios.remove(id) } }))
                        }
                    }
                    Toggle(l("common.plan.includePrivate"), isOn: $includePrivateNotes)
                }
                Picker(model.localizer("map.paper"), selection: $paper) {
                    Text("Letter").tag(PlanPDFRenderer.Paper.letter); Text("A4").tag(PlanPDFRenderer.Paper.a4)
                }
            } header: { Text(l("ui.share.what")) }
            let gaps = readinessGaps
            if !gaps.isEmpty {
                Section {
                    ForEach(gaps, id: \.self) { Label($0, systemImage: "questionmark.circle") }
                } header: { Text(l("ui.share.readyCheck")) } footer: { Text(l("ui.share.readyFooter")) }
            }
            Section {
                Button { Task { await prepare() } } label: {
                    if preparing { ProgressView().frame(maxWidth: .infinity) } else { Label(l("ui.share.preview"), systemImage: "eye") }
                }
                .buttonStyle(.primary)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                .disabled(preparing)
                .accessibilityIdentifier("share.preview")
                if failed { Text(l("ui.tryFailed")).font(.footnote).foregroundStyle(Theme.caution) }
            } footer: { Text(l("common.privacy.shareBoundary")) }
        }
        .disabled(preparing)
        .navigationTitle(l("ui.share.open"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } } }
        .navigationDestination(isPresented: $showingPreview) {
            if let exportURL { PDFPreviewContent(url: exportURL) }
        }
        .onChange(of: showingPreview) { _, showing in
            // Leaving the preview purges the plaintext file; an open share activity keeps its own lease.
            if !showing { TemporaryExports.hasActiveExport = false; TemporaryExports.purgeAll(); exportURL = nil }
        }
        .onDisappear { TemporaryExports.hasActiveExport = false; TemporaryExports.purgeAll() }
    }

    /// Things a relative would most need, phrased as what to record.
    private var readinessGaps: [String] {
        guard let h = model.household else { return [] }
        let l = model.localizer
        var out: [String] = []
        let places = model.savedPlaces.filter { $0.homeID == h.stableHomeID }
        if !places.contains(where: { $0.purpose == .outsideMeetingPoint }) { out.append(l("family.nearMeetup") + ": " + l("ui.plan.notChosen")) }
        if !places.contains(where: { $0.purpose == .backupMeetingPlace }) { out.append(l("family.backupMeetup") + ": " + l("ui.plan.notChosen")) }
        if !h.contacts.contains(where: \.hasUsablePhone) { out.append(l("family.contactMissing")) }
        if h.preparedness?.reviewedAt == nil { out.append(l("family.reviewMissing")) }
        return out
    }

    private func prepare() async {
        guard !preparing else { return }
        let request = FamilyPlanExportRequest(includePlan: includePlan, includeCard: true, includePrivateNotes: includePrivateNotes, selection: selection)
        let chosenScenarios = selectedScenarios.sorted()
        let chosenPaper = paper
        let startingPlaces = model.savedPlaces
        preparing = true; failed = false
        defer { preparing = false }
        var generated: PlanDocument?
        if request.includePlan {
            generated = await model.generatePlan(scenarioIDs: chosenScenarios, includePrivateNotes: request.includePrivateNotes, selection: request.selection)
            guard generated != nil else { failed = true; return }
        }
        let card = model.outageCard(includePrivateNotes: request.includePrivateNotes, selection: request.selection)
        guard let doc = request.includePlan ? generated : card else { failed = true; return }
        let startingKey = model.currentKey
        var panels: [PlanMapPanel] = []
        if request.includePlan, let snapshot = doc.visualSnapshot {
            panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: model.localizer("map.neighborhood"), localizer: model.localizer.with(locale: doc.locale))
        }
        // A late result never shows content older than the household's latest edits.
        guard model.currentKey == startingKey, model.savedPlaces == startingPlaces, paper == chosenPaper, (!request.includePlan || model.documentIsCurrent(doc)) else { failed = true; return }
        let output = PlanPDFRenderer().render(doc, paper: chosenPaper, mapPanels: panels)
        do {
            exportURL = try TemporaryExports.write(output.data, name: "DryRun-family-\(doc.locale).pdf")
            TemporaryExports.hasActiveExport = true
            showingPreview = true
        } catch {
            failed = true
            model.lastError = String(describing: error)
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
                    Section(model.localizer("map.neighborhood")) { NeighborhoodPlanPreview(snapshot: snapshot); Text(model.localizer("map.offline")).font(.caption) }
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
    let url: URL
    let note: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFPreviewContent(url: url, note: note)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(model.localizer("map.done")) { dismiss() }.accessibilityIdentifier("pdf.done") }
                }
        }
    }
}

/// The exact PDF that Share and Print send. Usable pushed (share flow) or inside `PDFPreviewSheet`.
struct PDFPreviewContent: View {
    @Environment(AppModel.self) private var model
    @State private var showingActivity = false
    let url: URL
    var note: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let note { Text(note).font(.footnote).padding(8) }
            PDFKitView(url: url).accessibilityIdentifier("pdf.preview")
        }
        .navigationTitle(model.localizer("map.selectedPreview"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                // Explicit user actions only; sharing moves a copy outside the vault.
                Button { showingActivity = true } label: { Label(model.localizer("common.action.share"), systemImage: "square.and.arrow.up") }.accessibilityIdentifier("pdf.share")
                Spacer()
                Button(model.localizer("common.action.print"), systemImage: "printer") { Printing.print(url: url) }.accessibilityIdentifier("pdf.print")
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PlanMapSelection.extents(homeCoordinate: snapshot.homeCoordinate, places: snapshot.savedPlaces)) { extent in
                VStack(alignment: .leading, spacing: 5) {
                    Text(extent.title(neighborhood: model.localizer("map.neighborhood"))).font(.caption.weight(.semibold))
                    Map {
                        if let coordinate = extent.homeCoordinate { Marker(model.localizer("map.home"), systemImage: "house.fill", coordinate: coordinate.cl) }
                        ForEach(extent.places, id: \.place.id) { entry in
                            if let coordinate = entry.place.coordinate {
                                Marker("\(entry.number). \(entry.place.label)", coordinate: coordinate.cl).tint(entry.place.purpose == .outsideMeetingPoint ? .green : .orange)
                            }
                        }
                    }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 190)
                        .accessibilityLabel(([extent.homeCoordinate == nil ? nil : model.localizer("map.home")] + extent.places.map { Optional($0.place.label) }).compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
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
            if let snapshot = doc.visualSnapshot { panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: model.localizer("map.neighborhood"), localizer: model.localizer.with(locale: doc.locale)) }
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
