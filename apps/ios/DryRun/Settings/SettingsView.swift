import SwiftUI
import DryRunCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private func t(_ key: String) -> String { model.localizer("native.\(key)") }

    var body: some View {
        NavigationStack {
            List {
                Section(t("language")) {
                    // Through selectLocale so the choice is saved with the household and survives a relaunch.
                    Picker(t("language"), selection: Binding(get: { model.locale },
                                                          set: { new in Task { await model.selectLocale(new) } })) {
                        ForEach(model.localizer.availableLocales, id: \.self) { code in
                            Text(model.content?.localeManifest?.entry(code)?.nativeName ?? code).tag(code)
                        }
                    }
                    Text(t("translationNotice"))
                        .font(.footnote)
                }
                Section(t("privacy")) {
                    Text(model.localizer("common.privacy.promise"))
                    Text(t("privateStorage"))
                        .font(.footnote)
                    Text(t("publicBoundary"))
                        .font(.footnote)
                }
                Section(t("capabilities")) {
                    LabeledContent(t("roomScan"), value: model.capabilities.roomCaptureSupported ? t("supported") : t("notSupported"))
                    LabeledContent(t("explanations"), value: availabilityText(model.capabilities.explanationModel))
                    LabeledContent(t("network"), value: model.capabilities.isOnline ? t("online") : t("offline"))
                }
                Section {
                    Button(t("delete"), role: .destructive) { confirmDelete = true }
                } footer: {
                    Text(t("deleteFooter"))
                }
                Section(t("about")) {
                    Text(t("prototype"))
                        .font(.footnote)
                }
            }
            .navigationTitle(t("settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
            .confirmationDialog(t("deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(t("deleteEverything"), role: .destructive) {
                    Task { await model.deleteAllPrivateData(); dismiss() }
                }
            }
        }
    }

    private func availabilityText(_ a: ExplanationAvailability) -> String {
        switch a {
        case .available: t("optionalAvailable")
        case .unavailable: t("notAvailable")
        }
    }
}
