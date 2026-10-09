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

    /// Looks an element up by accessibility identifier whatever its type. In a List the identifier can be reported on
    /// both the cell and the button inside it, so take the first match instead of failing on "multiple matches".
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Onboarding appears only after the bundled content has loaded, so wait for the button instead of tapping at once.
    private func chooseSampleHousehold(_ id: String, in app: XCUIApplication) {
        let button = app.buttons["onboarding.sample.\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "onboarding did not appear")
        button.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "tabs did not appear after choosing \(id)")
    }

    /// Steps through the open rehearsal to its end, answering each decision with one of `preferredOptions` when it is
    /// offered and otherwise with the first option. "Next" is disabled while a decision is pending, so a loop that
    /// only taps "Next" stops at the first decision.
    private func stepToEnd(_ app: XCUIApplication, preferredOptions: [String] = []) {
        let next = app.buttons["rehearsal.next"]
        let debrief = app.buttons["rehearsal.debrief"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "the rehearsal did not start")
        for _ in 0..<120 {
            if debrief.isEnabled { return }
            if next.isEnabled { next.tap(); continue }
            let anyOption = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
            if anyOption.waitForExistence(timeout: 3) {
                let preferred = preferredOptions.map { app.buttons["decision.option.\($0)"] }.first(where: { $0.exists })
                (preferred ?? anyOption).tap()
                // The choice re-runs the engine; wait until stepping (or the debrief) is available again.
                _ = wait(upTo: 10) { next.isEnabled || debrief.isEnabled }
            } else if !next.isEnabled && !debrief.isEnabled {
                break
            }
        }
        XCTAssertTrue(debrief.isEnabled, "the rehearsal never reached its end")
    }

    func testSampleHouseholdFireRehearsalAndPlan() {
        let app = launch()
        chooseSampleHousehold("hh-oak", in: app)
        app.tabBars.buttons["Rehearse"].tap()
        app.buttons["scenario.home-fire"].tap()
        XCTAssertTrue(app.staticTexts["Practice scenario"].waitForExistence(timeout: 5))
        stepToEnd(app)
        XCTAssertTrue(app.staticTexts["Practice routes under these assumptions"].exists)
        app.tabBars.buttons["Plan"].tap()
        app.buttons["plan.generate"].tap()
        XCTAssertTrue(element("plan.viewSaved", in: app).waitForExistence(timeout: 10))
    }

    func testFreezeTryChangeShowsBeforeAndAfter() {
        let app = launch()
        chooseSampleHousehold("hh-oak", in: app)
        app.buttons["scenario.freeze-power-loss"].tap()
        // Stay home at both decisions, so the outage at home (and the equipment that depends on power) stays in play.
        stepToEnd(app, preferredOptions: ["layer-up", "stay"])
        app.buttons["rehearsal.debrief"].tap()

        // The Oak household's oxygen concentrator has no confirmed backup, so this preparation is always offered
        // and can be tried (README demo step 3). It may be below the top three.
        let recommendation = element("recommendation.act.backup.confirm-medical-backup", in: app)
        if !recommendation.waitForExistence(timeout: 5) {
            let showAll = element("debrief.showAll", in: app)
            if showAll.exists { showAll.tap() }
            for _ in 0..<4 where !recommendation.exists { app.swipeUp() }
        }
        XCTAssertTrue(recommendation.exists, "the medical-backup preparation is missing from the debrief")
        recommendation.tap()

        let tryChange = element("recommendation.tryChange", in: app)
        XCTAssertTrue(tryChange.waitForExistence(timeout: 5), "this preparation should offer Try this change")
        tryChange.tap()
        XCTAssertTrue(app.navigationBars["Before and after"].waitForExistence(timeout: 10))
    }

    func testVietnamesePlanShowsDraftLabel() {
        let app = launch()
        // The Lake household's preferred language is Vietnamese, so the UI and its draft label are Vietnamese
        // (content/locales/vi: common.plan.generate, common.draftTranslation).
        chooseSampleHousehold("hh-lake", in: app)
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["Bản dịch nháp - đang chờ duyệt ngôn ngữ"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["plan.generate"].tap()
        // The saved-plan row sits below the scenario toggles and may need a scroll before it is in the tree.
        let saved = element("plan.viewSaved", in: app)
        if !saved.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "no plan was generated")
    }
}
