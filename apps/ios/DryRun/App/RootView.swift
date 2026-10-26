import SwiftUI
import DryRunCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab(rawValue: DemoLaunch.current.tab ?? "") ?? (DemoLaunch.current.scenarioID != nil ? .rehearse : .prepare)
    @State private var showSettings = false
    @State private var rehearsePath: [String] = DemoLaunch.current.scenarioID.map { [$0] } ?? []

    enum Tab: String, Hashable { case prepare, rehearse, plan }

    private func t(_ key: String) -> String { model.localizer("native.\(key)") }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView(t("loading"))
            case .contentFailed(let message):
                ContentUnavailableView(t("loadFailed"), systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .vaultLocked:
                ContentUnavailableView {
                    Label(t("unlock"), systemImage: "lock")
                } description: {
                    Text(t("unlockDetail"))
                } actions: {
                    Button(t("retry")) { Task { await model.loadPrivateData() } }
                }
            case .vaultNeedsRecovery(let message):
                VaultRecoveryView(message: message)
            case .onboarding:
                OnboardingView()
            case .ready:
                tabs
            }
        }
        .environment(\.locale, Locale(identifier: model.locale))
        .tint(Theme.accent)
        .alert(t("error"), isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button(t("ok"), role: .cancel) { model.lastError = nil }
        } message: {
            // Generic on purpose: raw errors can contain file paths or key identifiers.
            Text(t("saveError"))
        }
    }

    private var tabs: some View {
        let l = model.localizer
        return TabView(selection: $tab) {
            NavigationStack { NextStepsView(openRehearse: { tab = .rehearse }).toolbar { settingsButton } }
                // A new household (replacing the example one) gets a fresh stack: top of the page, large title.
                .id(model.household?.id)
                .tabItem { Label(l("common.tab.prepare"), systemImage: "checklist") }
                .tag(Tab.prepare)
            NavigationStack(path: $rehearsePath) { RehearseTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.rehearse"), systemImage: "play.circle") }
                .tag(Tab.rehearse)
            NavigationStack { PlanTabView().toolbar { settingsButton } }
                .tabItem { Label(l("common.tab.plan"), systemImage: "doc.text") }
                .tag(Tab.plan)

        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: model.pendingScenarioID, initial: true) { _, id in
            guard let id else { return }
            tab = .rehearse
            rehearsePath = [id]
            model.pendingScenarioID = nil
        }
        .onChange(of: model.pendingTab, initial: true) { _, raw in
            guard let raw, let target = Tab(rawValue: raw) else { return }
            tab = target
            if target != .rehearse { rehearsePath = [] }
            model.pendingTab = nil
        }
        // After "Delete everything", the next household starts on Prepare, not on whatever tab was open before.
        .onChange(of: model.phase) { _, phase in
            if phase == .onboarding { tab = .prepare; rehearsePath = [] }
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Label(t("settingsPrivacy"), systemImage: "gearshape") }
                .accessibilityIdentifier("app.settings")
        }
    }
}

private struct VaultRecoveryView: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmDelete = false

    private func t(_ key: String) -> String { model.localizer("native.\(key)") }

    var body: some View {
        ContentUnavailableView {
            Label(t("recovery"), systemImage: "exclamationmark.lock")
        } description: {
            Text(t("recoveryDetail"))
        } actions: {
            Button(t("retry")) { Task { await model.loadPrivateData() } }
            Button(t("startOver"), role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog(t("recoveryDelete"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(t("deleteStartOver"), role: .destructive) { Task { await model.deleteAllPrivateData() } }
        }
    }
}
