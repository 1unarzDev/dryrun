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
        app.buttons["Oak household (fictional)"].firstMatch.tap()
        app.tabBars.buttons["Rehearse"].tap()
        app.buttons["Home fire"].tap()
        XCTAssertTrue(app.staticTexts["Practice scenario"].waitForExistence(timeout: 5))
        // Step through the exercise, answering each decision with its first option.
        for _ in 0..<40 {
            if app.buttons["Next step"].isEnabled { app.buttons["Next step"].tap(); continue }
            let decision = app.otherElements.containing(.staticText, identifier: "Decision").buttons.firstMatch
            if decision.exists { decision.tap() } else { break }
        }
        XCTAssertTrue(app.staticTexts["Practice routes under these assumptions"].exists)
        app.tabBars.buttons["Plan"].tap()
        app.buttons["Generate plan"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'View saved plan'")).firstMatch.waitForExistence(timeout: 10))
    }

    func testFreezeTryChangeShowsBeforeAndAfter() {
        let app = launch()
        app.buttons["Oak household (fictional)"].firstMatch.tap()
        app.buttons["Freeze with power loss"].tap()
        while app.buttons["Next step"].isEnabled { app.buttons["Next step"].tap() }
        app.buttons["Debrief"].tap()
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
        app.buttons["Lake household (fictional)"].firstMatch.tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.buttons["Tạo kế hoạch"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bản dịch nháp - đang chờ duyệt ngôn ngữ"].firstMatch.waitForExistence(timeout: 10))
    }
}
