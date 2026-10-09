import SwiftUI
import DryRunCore

@main
struct DryRunApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains("-uiTestingInMemory")
        let store: PrivateDataStore = isUITest ? InMemoryPrivateDataStore() : VaultPrivateDataStore.makeDefault()
        _model = State(initialValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                // App-switcher snapshots should not show household details.
                .overlay { if scenePhase != .active { PrivacyCover() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { TemporaryExports.purgeAll() }
                }
        }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Label("Dry Run", systemImage: "house.lodge")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityHidden(true)
    }
}

/// Restrained, readable defaults. A later design pass will refine these tokens.
enum Theme {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let accent = Color(red: 0.05, green: 0.45, blue: 0.50)
    static let caution = Color(red: 0.78, green: 0.50, blue: 0.02)
    static let critical = Color(red: 0.72, green: 0.15, blue: 0.12)

    static func color(for state: ServiceState) -> Color {
        switch state {
        case .operational: accent
        case .degraded: caution
        case .unavailable: critical
        case .unknown: .secondary
        }
    }

    static func symbol(for state: ServiceState) -> String {
        switch state {
        case .operational: "checkmark.circle"
        case .degraded: "exclamationmark.triangle"
        case .unavailable: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }

    static func color(for severity: EventSeverity) -> Color {
        switch severity {
        case .info: .secondary
        case .caution: caution
        case .critical: critical
        }
    }
}
