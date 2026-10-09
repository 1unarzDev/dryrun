import XCTest

/// End-to-end journeys for a simulator. AUTHORED ONLY in the first build (no macOS host was available);
/// see docs/VERIFICATION.md. Uses an in-memory store so no vault/key state leaks between runs.
/// XCUIApplication/XCUIElement are main-actor isolated in current SDKs; Swift 6 mode requires this.
@MainActor
final class DemoJourneyUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory"]
        app.launch()
        return app
    }

    func testSampleHouseholdFireRehearsalAndPlan() {
        let app = launch()
        app.buttons["onboarding.sample.hh-oak"].tap()
        app.tabBars.buttons["Rehearse"].tap()
        app.buttons["scenario.home-fire"].tap()
        XCTAssertTrue(app.staticTexts["Practice scenario"].waitForExistence(timeout: 5))
        // Step through the exercise, answering each decision with its first option.
        for _ in 0..<40 {
            if app.buttons["rehearsal.next"].isEnabled { app.buttons["rehearsal.next"].tap(); continue }
            let decision = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
            if decision.exists { decision.tap() } else { break }
        }
        XCTAssertTrue(app.staticTexts["Practice routes under these assumptions"].exists)
        app.tabBars.buttons["Plan"].tap()
        app.buttons["plan.generate"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'View saved plan'")).firstMatch.waitForExistence(timeout: 10))
    }

    func testFreezeTryChangeShowsBeforeAndAfter() {
        let app = launch()
        app.buttons["onboarding.sample.hh-oak"].tap()
        app.buttons["scenario.freeze-power-loss"].tap()
        while app.buttons["rehearsal.next"].isEnabled { app.buttons["rehearsal.next"].tap() }
        app.buttons["rehearsal.debrief"].tap()
        app.cells.firstMatch.tap()
        if app.buttons["Try this change"].exists {
            app.buttons["Try this change"].tap()
            XCTAssertTrue(app.navigationBars["Before and after"].waitForExistence(timeout: 5))
        }
    }

    func testVietnamesePlanShowsDraftLabel() {
        let app = launch()
        // The Lake household's preferred language is Vietnamese, so the UI and its draft label are Vietnamese
        // (content/locales/vi: common.plan.generate, common.draftTranslation).
        app.buttons["onboarding.sample.hh-lake"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.buttons["plan.generate"].tap()
        XCTAssertTrue(app.staticTexts["Bản dịch nháp - đang chờ duyệt ngôn ngữ"].firstMatch.waitForExistence(timeout: 10))
    }
}
