import SwiftUI
import UIKit
import DryRunCore

@main
struct DryRunApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let demo = DemoLaunch.current
        #if DEBUG
        // Hosted unit tests must not start the owner's default vault while
        // XCTest constructs controlled models with their own stores.
        let unitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isolatedTestVault = ProcessInfo.processInfo.arguments.contains("-uiTestingVaultID")
        #else
        let unitTestHost = false
        let isolatedTestVault = false
        #endif
        // Demo launches use memory; explicit physical persistence tests use their own encrypted namespace.
        let store: PrivateDataStore
        if isolatedTestVault {
            store = VaultPrivateDataStore.makeDefault()
        } else if demo.usesInMemoryStore || unitTestHost {
            store = InMemoryPrivateDataStore()
        } else {
            store = VaultPrivateDataStore.makeDefault()
        }
        if demo.disableAnimations { UIView.setAnimationsEnabled(false) }
        let examples: PrivateDataStore? = isolatedTestVault || demo.usesInMemoryStore || unitTestHost
            ? nil : InMemoryPrivateDataStore()
        _model = State(initialValue: AppModel(store: store, exampleStore: examples))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    TemporaryExports.purgeAll() // leftovers from a previous run
                    await model.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    // App-switcher snapshots must not show household details, including inside sheets and covers,
                    // so the shield is a separate window above everything rather than a root-view overlay.
                    PrivacyShield.shared.set(visible: phase != .active)
                    if phase == .active { Task { await model.refreshScorecard(force: true) } }
                    // Do not purge while a share/print may still be reading the file; it is purged on dismissal.
                    if phase == .background && !TemporaryExports.hasActiveExport { TemporaryExports.purgeAll() }
                }
        }
    }
}

/// Window-level cover shown while the app is inactive/backgrounded.
@MainActor
final class PrivacyShield {
    static let shared = PrivacyShield()
    private var window: UIWindow?

    func set(visible: Bool) {
        if visible {
            guard window == nil, let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
            w.rootViewController = UIHostingController(rootView: PrivacyCover())
            w.isHidden = false
            window = w
        } else {
            window?.isHidden = true
            window = nil
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
