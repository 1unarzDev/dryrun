import SwiftUI
import DryRunCore

/// Share the plan and/or the outage card with relatives or caregivers. The household chooses what goes out, sees
/// what is still unknown, reads the sharing boundary, and previews before the share sheet. The plaintext PDF exists
/// only while the preview is open (same lifecycle as the Plan tab).
struct ShareWithFamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includePlan = true
    @State private var includeCard = true
    @State private var includePrivateNotes = false
    @State private var selection = FamilyCardSelection()
    @State private var exportURL: URL?
    @State private var showPreview = false
    @State private var preparing = false

    static let defaultPlanScenarios = ["home-fire", "freeze-power-loss", "heat-grid-strain"]

    var body: some View {
        let l = model.localizer
        let gaps = readinessGaps
        Form {
            Section {
                Toggle(isOn: $includePlan) { Label(l("ui.share.plan"), systemImage: "doc.text") }
                    .accessibilityIdentifier("share.includePlan")
                Group {
                    Toggle(isOn: $includeCard) { Label(l("ui.card.title"), systemImage: "bolt.heart") }
                        .accessibilityIdentifier("share.includeCard")
                }
                Toggle(l("family.critical"), isOn: $selection.includeCriticalInformation)
                Toggle(l("family.medication"), isOn: $selection.includeMedication)
                Toggle(l("family.instructions"), isOn: $selection.includeResponderInstructions)
                Toggle(l("family.contacts"), isOn: $selection.includeContacts)
                Toggle(l("common.plan.includePrivate"), isOn: $includePrivateNotes)
                Text(l("family.selectedWhy")).font(.footnote)
            } header: {
                Text(l("ui.share.what"))
            }
            .disabled(preparing)
            Section {
                if gaps.isEmpty {
                    Text(l("ui.share.readyFooter")).foregroundStyle(.secondary)
                }
                ForEach(gaps, id: \.self) { Label($0, systemImage: "questionmark.circle").foregroundStyle(.primary) }
            } header: {
                Text(l("ui.share.readyCheck"))
            } footer: {
                Text(l("ui.share.readyFooter"))
            }
            Section {
                Button {
                    Task { await prepare() }
                } label: {
                    if preparing { ProgressView() } else { Label(l("ui.share.preview"), systemImage: "eye") }
                }
                .buttonStyle(.primary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(preparing || (!includePlan && !includeCard))
                .accessibilityIdentifier("share.preview")
            } footer: {
                Text(l("common.privacy.shareBoundary"))
            }
        }
        .navigationTitle(l("ui.share.open"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } } }
        .sheet(isPresented: $showPreview, onDismiss: {
            TemporaryExports.hasActiveExport = false
            TemporaryExports.purgeAll()
            exportURL = nil
        }) {
            if let exportURL { PDFPreviewSheet(url: exportURL, note: nil) }
        }
    }

    /// Unknowns a relative would most need, phrased as things to record. From the outage card gaps and the plan.
    private var readinessGaps: [String] {
        guard let h = model.household else { return [] }
        let l = model.localizer
        var out: [String] = []
        if includeCard {
            for eq in OutageCardBuilder.devices(in: h) {
                for gap in OutageCardBuilder.gaps(for: eq, in: h) {
                    out.append("\(eq.localizedLabel(l)): \(l("card.gap.\(gap.rawValue)"))")
                }
            }
        }
        if includePlan {
            if !model.savedPlaces.contains(where: { $0.purpose == .outsideMeetingPoint && $0.homeID == h.stableHomeID }) { out.append(l("family.meetupMissing")) }
            if !h.contacts.contains(where: \.isComplete) { out.append(l("plan.contact.none")) }
        }
        return Array(NSOrderedSet(array: out)) as? [String] ?? out
    }

    private func prepare() async {
        guard !preparing else { return }
        let request = FamilyPlanExportRequest(includePlan: includePlan, includeCard: includeCard,
            includePrivateNotes: includePrivateNotes, selection: selection)
        let scenarioIDs = model.savedPlan?.scenarioIDs ?? []
        let startingKey = model.currentKey
        let startingLocale = model.locale
        let startingPlaces = model.savedPlaces
        preparing = true
        defer { preparing = false }
        var generatedPlan: PlanDocument?
        if request.includePlan {
            generatedPlan = await model.generatePlan(scenarioIDs: scenarioIDs, includePrivateNotes: request.includePrivateNotes, selection: request.selection)
            guard generatedPlan != nil, !model.planIsStale else { return }
        }
        let card = request.includeCard ? model.outageCard(includePrivateNotes: request.includePrivateNotes, selection: request.selection) : nil
        guard let doc = request.document(generatedPlan: generatedPlan, card: card) else { return }
        var panels: [PlanMapPanel] = []
        if request.includePlan, let snapshot = doc.visualSnapshot {
            panels = await PlanMapSnapshotRenderer().panels(for: snapshot, title: model.localizer("map.neighborhood"), localizer: model.localizer.with(locale: doc.locale))
        }
        guard model.currentKey == startingKey, model.locale == startingLocale, model.savedPlaces == startingPlaces else { return }
        let output = PlanPDFRenderer().render(doc, mapPanels: panels)
        do {
            exportURL = try TemporaryExports.write(output.data, name: "DryRun-family-\(doc.locale).pdf")
            TemporaryExports.hasActiveExport = true
            showPreview = true
        } catch {
            model.lastError = String(describing: error)
        }
    }
}
