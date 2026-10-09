import SwiftUI
import DryRunCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Language") {
                    Picker("Language", selection: $model.locale) {
                        Text("English").tag("en"); Text("Español").tag("es"); Text("Tiếng Việt").tag("vi")
                    }
                    Text("Spanish and Vietnamese text is a draft translation awaiting language review, and is labeled wherever it appears.")
                        .font(.footnote)
                }
                Section("Privacy") {
                    Text(model.localizer("common.privacy.promise"))
                    Text("Household details are encrypted on this iPhone with a key that stays on this device. They are not synced to iCloud and are excluded from device backups, so they cannot be restored on a new phone. Sharing or printing a plan creates a copy outside Dry Run.")
                        .font(.footnote)
                    Text("Public information (alerts and directories) is requested by county only. Those requests reveal your network address and selected county to the service providers.")
                        .font(.footnote)
                }
                Section("Device capabilities") {
                    LabeledContent("Room scanning (LiDAR)", value: model.capabilities.roomCaptureSupported ? "Supported" : "Not supported")
                    LabeledContent("On-device explanations", value: availabilityText(model.capabilities.explanationModel))
                    LabeledContent("Network", value: model.capabilities.isOnline ? "Online" : "Offline")
                }
                Section {
                    Button("Delete all household data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes the household, home layout, results, saved plans, temporary exports, and the encryption key from this iPhone. It cannot recall copies you already shared.")
                }
                if let issues = model.content?.issues, !issues.isEmpty {
                    Section("Content diagnostics") { ForEach(issues, id: \.self) { Text($0.description).font(.caption) } }
                }
                Section("About") {
                    Text("Content version \(model.content?.contentVersion ?? "?"). Prototype: safety content and translations are pending expert review.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete all household data from this iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    Task { await model.deleteAllPrivateData(); dismiss() }
                }
            }
        }
    }

    private func availabilityText(_ a: ExplanationAvailability) -> String {
        switch a {
        case .available: "Available (optional)"
        case .unavailable: "Not available — templates are used"
        }
    }
}
