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
    @State private var exportURL: URL?
    @State private var showPreview = false
    @State private var preparing = false

    static let defaultPlanScenarios = ["home-fire", "freeze-power-loss", "heat-grid-strain"]

    var body: some View {
        let l = model.localizer
        let hasDevices = !(model.household.map(OutageCardBuilder.devices(in:)) ?? []).isEmpty
        let gaps = readinessGaps
        Form {
            Section {
                Toggle(isOn: $includePlan) { Label(l("ui.share.plan"), systemImage: "doc.text") }
                    .accessibilityIdentifier("share.includePlan")
                if hasDevices {
                    Toggle(isOn: $includeCard) { Label(l("ui.card.title"), systemImage: "bolt.heart") }
                        .accessibilityIdentifier("share.includeCard")
                }
                Toggle(l("common.plan.includePrivate"), isOn: $includePrivateNotes)
            } header: {
                Text(l("ui.share.what"))
            }
            Section {
                if gaps.isEmpty {
                    Label(l("ui.share.nothingMissing"), systemImage: "checkmark.circle").foregroundStyle(Theme.success)
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
                .disabled(preparing || (!includePlan && !(includeCard && hasDevices)))
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
                    out.append("\(eq.label): \(l("card.gap.\(gap.rawValue)"))")
                }
            }
        }
        if includePlan {
            if model.home?.meetingPoint == nil { out.append(l("plan.meeting.missing")) }
            if h.contacts.isEmpty { out.append(l("plan.contact.none")) }
        }
        return Array(NSOrderedSet(array: out)) as? [String] ?? out
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        var pages: [PlanPage] = []
        var base: PlanDocument?
        if includePlan {
            if model.savedPlan == nil || model.planIsStale || model.savedPlan?.includesPrivateNotes != includePrivateNotes {
                let scenarios = model.savedPlan?.scenarioIDs.isEmpty == false ? model.savedPlan!.scenarioIDs : Self.defaultPlanScenarios
                await model.generatePlan(scenarioIDs: scenarios, includePrivateNotes: includePrivateNotes)
            }
            if let plan = model.savedPlan, plan.locale == model.locale {
                base = plan
                pages += plan.pages
            }
        }
        if includeCard, let card = model.outageCard(includePrivateNotes: includePrivateNotes), !card.pages.isEmpty {
            // The card goes first: it is the page someone needs in a hurry.
            pages = card.pages + pages
            if var merged = base {
                merged.draftTranslationBanner = merged.draftTranslationBanner ?? card.draftTranslationBanner
                merged.fallbackNote = merged.fallbackNote ?? card.fallbackNote
                merged.sourceIDs = Array(Set(merged.sourceIDs + card.sourceIDs)).sorted()
                base = merged
            } else {
                base = card
            }
        }
        guard var doc = base, !pages.isEmpty else { return }
        doc.pages = pages
        let output = PlanPDFRenderer().render(doc)
        do {
            exportURL = try TemporaryExports.write(output.data, name: "DryRun-family-\(doc.locale).pdf")
            TemporaryExports.hasActiveExport = true
            showPreview = true
        } catch {
            model.lastError = String(describing: error)
        }
    }
}
