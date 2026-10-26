import XCTest

/// Captures a fixed set of screens per locale as XCTest attachments (kept always), so tooling can export them from the
/// .xcresult. Runs on a simulator or a connected iPhone. Fictional demo data only.
///
/// Filters (pass through xcodebuild as TEST_RUNNER_<NAME>=value):
///   TOUR_LOCALES=en,es,vi     which locales (default all three)
///   TOUR_SCREENS=fire-end,plan  substring filter on screen names (default all)
///   TOUR_XXL=1                largest accessibility text size (Dynamic Type AX XXL); names get an "-xxl" suffix
@MainActor
final class ScreenshotTourUITests: XCTestCase {
    struct Screen {
        let name: String
        let args: [String]
        /// Accessibility identifier to tap after launch (e.g. open a sheet), if any.
        var tap: String? = nil
        /// A second identifier to tap once the first one's screen is up.
        var then: String? = nil
    }

    /// Household per locale matches each fictional household's preferred language.
    static let households = ["en": "hh-oak", "es": "hh-pine", "vi": "hh-lake"]

    static func screens(household h: String) -> [Screen] {
        [
            Screen(name: "onboarding", args: []),
            Screen(name: "next-steps", args: ["-demoHousehold", h, "-demoTab", "prepare"]),
            Screen(name: "outage-card", args: ["-demoHousehold", h, "-demoTab", "prepare"], tap: "next.outageCard"),
            Screen(name: "medical-setup", args: ["-demoHousehold", h, "-demoTab", "prepare"], tap: "next.outageCard", then: "card.addDevice"),
            Screen(name: "family-editor", args: ["-demoHousehold", h, "-demoTab", "prepare"], tap: "next.family"),
            Screen(name: "contacts", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.addContact"),
            Screen(name: "apartment-complex-2d", args: ["-demoHousehold", h, "-demoHome", "apartment-complex"], tap: "next.home"),
            Screen(name: "apartment-complex-3d", args: ["-demoHousehold", h, "-demoHome", "apartment-complex", "-demoHomeMode", "3d"], tap: "next.home"),
            Screen(name: "manufactured-2d", args: ["-demoHousehold", h, "-demoHome", "manufactured"], tap: "next.home"),
            Screen(name: "manufactured-3d", args: ["-demoHousehold", h, "-demoHome", "manufactured", "-demoHomeMode", "3d"], tap: "next.home"),
            Screen(name: "twostory-2d", args: ["-demoHousehold", h, "-demoHome", "twostory"], tap: "next.home"),
            Screen(name: "twostory-3d", args: ["-demoHousehold", h, "-demoHome", "twostory", "-demoHomeMode", "3d"], tap: "next.home"),
            Screen(name: "apartment-fire-decision", args: ["-demoHousehold", h, "-demoHome", "apartment-complex", "-demoScenario", "home-fire", "-demoStep", "decision"]),
            Screen(name: "rehearse-list", args: ["-demoHousehold", h, "-demoTab", "rehearse"]),
            Screen(name: "freeze-decision", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "decision"]),
            Screen(name: "freeze-end", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "end"]),
            Screen(name: "freeze-debrief", args: ["-demoHousehold", h, "-demoScenario", "freeze-power-loss", "-demoStep", "end"],
                   tap: "rehearsal.debrief"),
            Screen(name: "fire-start", args: ["-demoHousehold", h, "-demoScenario", "home-fire", "-demoStep", "start"]),
            Screen(name: "fire-decision", args: ["-demoHousehold", h, "-demoScenario", "home-fire", "-demoStep", "decision"]),
            Screen(name: "tornado-end", args: ["-demoHousehold", h, "-demoScenario", "tornado", "-demoStep", "end"]),
            Screen(name: "flood-start", args: ["-demoHousehold", h, "-demoScenario", "flash-flood", "-demoStep", "start"]),
            Screen(name: "flood-end", args: ["-demoHousehold", h, "-demoScenario", "flash-flood", "-demoStep", "end"]),
            Screen(name: "fire-end", args: ["-demoHousehold", h, "-demoScenario", "home-fire", "-demoStep", "end"]),
            Screen(name: "tornado-decision", args: ["-demoHousehold", h, "-demoScenario", "tornado", "-demoStep", "decision"]),
            Screen(name: "water-end", args: ["-demoHousehold", h, "-demoScenario", "water-outage", "-demoStep", "end"]),
            Screen(name: "home-2d", args: ["-demoHousehold", h, "-demoTab", "prepare", "-demoHomeMode", "2d"], tap: "next.home"),
            Screen(name: "home-3d", args: ["-demoHousehold", h, "-demoTab", "prepare", "-demoHomeMode", "3d"], tap: "next.home"),
            Screen(name: "home-rooms", args: ["-demoHousehold", h, "-demoTab", "prepare", "-demoHomeMode", "rooms"], tap: "next.home"),
            Screen(name: "plan-tab", args: ["-demoHousehold", h, "-demoTab", "plan", "-demoPlan", "all"]),
            Screen(name: "plan-document", args: ["-demoHousehold", h, "-demoTab", "plan", "-demoPlan", "all"], tap: "plan.viewSaved"),
            Screen(name: "neighborhood-map", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.map"),
            Screen(name: "address", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.address"),
            Screen(name: "meetup-near", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.meetup.outsideMeetingPoint"),
            Screen(name: "share", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.share"),
            Screen(name: "share-preview", args: ["-demoHousehold", h, "-demoTab", "plan"], tap: "plan.share", then: "share.preview"),
        ]
    }

    /// Polls on the main run loop. Used instead of predicate expectations so nothing main-actor isolated is captured
    /// by a @Sendable block (the test target builds in Swift 6 mode).
    private func wait(upTo seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    /// A comma-separated filter from the environment. Unset, empty, or only separators all mean "no filter": an
    /// empty value must not turn into an empty list that matches nothing.
    private func env(_ key: String) -> [String]? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    func testScreenshotTour() {
        let locales = env("TOUR_LOCALES") ?? ["en", "es", "vi"]
        let filters = env("TOUR_SCREENS")
        var captured = 0
        for locale in locales {
            let household = Self.households[locale] ?? "hh-oak"
            for screen in Self.screens(household: household) {
                if let filters, !filters.contains(where: { screen.name.contains($0) }) { continue }
                capture(screen, locale: locale)
                captured += 1
            }
        }
        XCTAssertGreaterThan(captured, 0, "no screen matched TOUR_LOCALES/TOUR_SCREENS; nothing was captured")
    }

    private func capture(_ screen: Screen, locale: String) {
        let app = XCUIApplication()
        let xxl = ProcessInfo.processInfo.environment["TOUR_XXL"] == "1"
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-demoLocale", locale] + screen.args
            + (xxl ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"] : [])
        app.launch()
        // Let async content load and the rehearsal/plan finish.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        for id in [screen.tap, screen.then].compactMap({ $0 }) {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            // Rows of a lazy list are not in the accessibility tree until scrolled near, so scroll before giving up.
            var found = element.waitForExistence(timeout: 15)
            for _ in 0..<4 where !found {
                app.swipeUp()
                found = element.waitForExistence(timeout: 2)
            }
            if found {
                // The debrief button exists from the first frame but is disabled until the demo has stepped the
                // rehearsal to its end; tapping it earlier does nothing and the screenshot would show the wrong screen.
                if !wait(upTo: 20, until: { element.isEnabled }) {
                    XCTFail("\(locale)-\(screen.name): element \(id) never became enabled")
                }
                for _ in 0..<4 where !element.isHittable { app.swipeUp() }
                element.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            } else {
                XCTFail("\(locale)-\(screen.name): element \(id) not found")
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        let suffix = ProcessInfo.processInfo.environment["TOUR_XXL"] == "1" ? "-xxl" : ""
        shot.name = "\(locale)-\(screen.name)\(suffix)"
        shot.lifetime = .keepAlways
        add(shot)
        // Accessibility tree dump helps diagnose layout and VoiceOver labels without the screenshot.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(locale)-\(screen.name)\(suffix).a11y.txt"
        tree.lifetime = .keepAlways
        add(tree)
        app.terminate()
    }
}
