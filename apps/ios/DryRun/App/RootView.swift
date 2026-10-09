import SwiftUI
import DryRunCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.rehearse
    @State private var showSettings = false

    enum Tab: Hashable { case rehearse, home, plan, help }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Loading")
            case .contentFailed(let message):
                ContentUnavailableView("Content could not load", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .vaultLocked:
                ContentUnavailableView {
                    Label("Unlock your iPhone", systemImage: "lock")
                } description: {
                    Text("Your household data is encrypted and can be opened after the device is unlocked. Nothing was deleted.")
                } actions: {
                    Button("Try again") { Task { await model.loadPrivateData() } }
                }
            case .vaultNeedsRecovery(let message):
                VaultRecoveryView(message: message)
            case .onboarding:
                OnboardingView()
            case .ready:
                tabs
            }
        }
        .tint(Theme.accent)
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            // Generic on purpose: raw errors can contain file paths or key identifiers.
            Text("Dry Run could not finish that step. Your saved household data was not changed.")
        }
    }

    private var tabs: some View {
        let l = model.localizer
        return TabView(selection: $tab) {
            NavigationStack { RehearseTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.rehearse"), systemImage: "play.circle") }
                .tag(Tab.rehearse)
            NavigationStack { HomeTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.home"), systemImage: "house") }
                .tag(Tab.home)
            NavigationStack { PlanTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.plan"), systemImage: "doc.text") }
                .tag(Tab.plan)
            NavigationStack { HelpTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.help"), systemImage: "phone.bubble") }
                .tag(Tab.help)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Label("Settings and privacy", systemImage: "gearshape") }
        }
    }
}

private struct VaultRecoveryView: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmDelete = false

    var body: some View {
        ContentUnavailableView {
            Label("Your saved household could not be opened", systemImage: "exclamationmark.lock")
        } description: {
            Text("The encrypted file was kept, not erased. This can happen after restoring to a new phone, because the key stays on the original device. Details: \(message)")
        } actions: {
            Button("Try again") { Task { await model.loadPrivateData() } }
            Button("Start over and delete stored data", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete the unreadable household data and start over?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete and start over", role: .destructive) { Task { await model.deleteAllPrivateData() } }
        }
    }
}
