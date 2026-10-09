import XCTest

/// Captures a fixed set of screens per locale as XCTest attachments (kept always), so tooling can export them from the
/// .xcresult. Runs on a simulator or a connected iPhone. Fictional demo data only.
///
/// Filters (pass through xcodebuild as TEST_RUNNER_<NAME>=value):
///   TOUR_LOCALES=en,es,vi     which locales (default all three)
///   TOUR_SCREENS=fire-end,plan  substring filter on screen names (default all)
@MainActor
final class ScreenshotTourUITests: XCTestCase {
    struct Screen {
        let name: String
        let args: [String]
        /// Accessibility identifier to tap after launch (e.g. open a sheet), if any.
        var tap: String? = nil
    }

    /// Household per locale matches each fictional household's preferred language.
    static let households = ["en": "hh-oak", "es": "hh-pine", "vi": "hh-lake"]

    static func screens(household h: String) -> [Screen] {
        [
            Screen(name: "onboarding", args: []),
            Screen(name: "rehearse-list", args: ["-demoHousehold", h, "-demoTab", "rehearse"]),
            Screen(name: "freeze-decision", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "decision"]),
            Screen(name: "freeze-end", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "end"]),
            Screen(name: "freeze-debrief", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "end"],
                   tap: "rehearsal.debrief"),
            Screen(name: "fire-end", args: ["-demoHousehold", h, "-demoScenario", "home-fire", "-demoStep", "end"]),
            Screen(name: "tornado-decision", args: ["-demoHousehold", h, "-demoScenario", "tornado", "-demoStep", "decision"]),
            Screen(name: "water-end", args: ["-demoHousehold", h, "-demoScenario", "water-outage", "-demoStep", "end"]),
            Screen(name: "home-2d", args: ["-demoHousehold", h, "-demoTab", "home", "-demoHomeMode", "2d"]),
            Screen(name: "home-3d", args: ["-demoHousehold", h, "-demoTab", "home", "-demoHomeMode", "3d"]),
            Screen(name: "home-rooms", args: ["-demoHousehold", h, "-demoTab", "home", "-demoHomeMode", "rooms"]),
            Screen(name: "plan-tab", args: ["-demoHousehold", h, "-demoTab", "plan", "-demoPlan", "all"]),
            Screen(name: "plan-document", args: ["-demoHousehold", h, "-demoTab", "plan", "-demoPlan", "all"], tap: "plan.viewSaved"),
            Screen(name: "help", args: ["-demoHousehold", h, "-demoTab", "help"]),
        ]
    }

    private func env(_ key: String) -> [String]? {
        ProcessInfo.processInfo.environment[key].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    func testScreenshotTour() {
        let locales = env("TOUR_LOCALES") ?? ["en", "es", "vi"]
        let filters = env("TOUR_SCREENS")
        for locale in locales {
            let household = Self.households[locale] ?? "hh-oak"
            for screen in Self.screens(household: household) {
                if let filters, !filters.contains(where: { screen.name.contains($0) }) { continue }
                capture(screen, locale: locale)
            }
        }
    }

    private func capture(_ screen: Screen, locale: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-demoLocale", locale] + screen.args
        app.launch()
        // Let async content load and the rehearsal/plan finish.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        if let id = screen.tap {
            let element = app.descendants(matching: .any)[id]
            if element.waitForExistence(timeout: 15) {
                if !element.isHittable { app.swipeUp() }
                element.tap()
            } else {
                XCTFail("\(locale)-\(screen.name): element \(id) not found")
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(locale)-\(screen.name)"
        shot.lifetime = .keepAlways
        add(shot)
        // Accessibility tree dump helps diagnose layout and VoiceOver labels without the screenshot.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(locale)-\(screen.name).a11y.txt"
        tree.lifetime = .keepAlways
        add(tree)
        app.terminate()
    }
}
