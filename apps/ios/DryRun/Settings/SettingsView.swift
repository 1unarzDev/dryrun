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
                        ForEach(model.localizer.selectableLocales, id: \.self) { code in
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
                SampleFamilySection(onLoaded: { dismiss() })
                if model.managesPersonalReminders { ReviewReminderSection() }
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
                    Task { if await model.deleteAllPrivateData() { dismiss() } }
                }
                Button(model.localizer("ui.cancel"), role: .cancel) {}
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


/// Examples live in a separate store; the personal household remains available to restore.
private struct SampleFamilySection: View {
    @Environment(AppModel.self) private var model
    let onLoaded: () -> Void
    @State private var familyID = SampleHouseholds.oak.id
    @State private var homeID = ""
    @State private var loading = false
    @State private var failed = false

    private func t(_ key: String) -> String { model.localizer("native.\(key)") }

    var body: some View {
        Section {
            if model.household == nil || model.household?.isFictional == true || model.hasPersonalHousehold {
                Picker(t("sampleFamilyPick"), selection: $familyID) {
                    ForEach(SampleHouseholds.all, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                .accessibilityIdentifier("settings.sampleFamily")
                Picker(t("sampleHomePick"), selection: $homeID) {
                    ForEach(SampleHomes.all) { Text($0.label).tag($0.id) }
                }
                .accessibilityIdentifier("settings.sampleHome")
                Button(t("sampleFamilyLoad"), systemImage: "person.3") {
                    load()
                }
                .disabled(loading)
                .accessibilityIdentifier("settings.sampleLoad")
                if model.household?.isFictional == true && model.hasPersonalHousehold {
                    Button(t("restoreHousehold")) {
                        loading = true
                        Task {
                            let restored = await model.restorePersonalHousehold()
                            loading = false; failed = !restored
                            if restored { onLoaded() }
                        }
                    }.disabled(loading).accessibilityIdentifier("settings.restoreHousehold")
                }
                if failed { Text(model.localizer("ui.tryFailed")).foregroundStyle(Theme.caution) }
            } else {
                Text(t("sampleFamilyBlocked")).font(.footnote)
            }
        } header: {
            Text(t("sampleFamily"))
        } footer: {
            Text(t("sampleFamilyDetail"))
        }
        .onAppear { if homeID.isEmpty { homeID = SampleHomes.ranch.id } }
    }

    private func load() {
        guard let family = SampleHouseholds.all.first(where: { $0.id == familyID }) else { return }
        loading = true; failed = false
        Task {
            let home = SampleHomes.all.first { $0.id == homeID }
            await model.useSampleHousehold(family, demoHome: home?.id == SampleHomes.ranch.id ? nil : home)
            loading = false
            if model.household?.id == familyID { onLoaded() } else { failed = true }
        }
    }
}
