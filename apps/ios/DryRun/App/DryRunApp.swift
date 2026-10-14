import SwiftUI
import UIKit
import DryRunCore

@main
struct DryRunApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let demo = DemoLaunch.current
        // Demo/UI-test launches never touch the real vault.
        let store: PrivateDataStore = demo.usesInMemoryStore ? InMemoryPrivateDataStore() : VaultPrivateDataStore.makeDefault()
        if demo.disableAnimations { UIView.setAnimationsEnabled(false) }
        _model = State(initialValue: AppModel(store: store))
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
