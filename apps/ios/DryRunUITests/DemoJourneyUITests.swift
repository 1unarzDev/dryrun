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
                let option = preferredOptions.map { app.buttons["decision.option.\($0)"] }.first(where: { $0.exists }) ?? anyOption
                for _ in 0..<3 where !option.isHittable { app.swipeUp() }
                option.tap()
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
        app.tabBars.buttons["Rehearse"].tap()
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

        // The button is in the last section of a lazy List: it is not in the tree until scrolled into view.
        let tryChange = element("recommendation.tryChange", in: app)
        XCTAssertTrue(app.navigationBars["Preparation"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !(tryChange.exists && tryChange.isHittable) { app.swipeUp() }
        XCTAssertTrue(tryChange.waitForExistence(timeout: 5), "this preparation should offer Try this change")
        tryChange.tap()
        XCTAssertTrue(app.navigationBars["Before and after"].waitForExistence(timeout: 10))
    }

    func testVietnamesePlanShowsDraftLabel() {
        let app = launch()
        // The Lake household's preferred language is Vietnamese, so the UI and its draft label are Vietnamese
        // (content/locales/vi: common.plan.generate, common.draftTranslation).
        chooseSampleHousehold("hh-lake", in: app)
        app.tabBars.buttons.element(boundBy: 3).tap() // Next steps, Rehearse, Home, Plan
        XCTAssertTrue(app.staticTexts["Bản dịch nháp - đang chờ duyệt ngôn ngữ"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["plan.generate"].tap()
        // The saved-plan row sits below the scenario toggles and may need a scroll before it is in the tree.
        let saved = element("plan.viewSaved", in: app)
        if !saved.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "no plan was generated")
    }

    // MARK: - Next steps, outage card, sharing

    func testNextStepsMarkDoneMovesToDone() {
        let app = launch()
        chooseSampleHousehold("hh-oak", in: app)
        // Next steps is the first tab. It runs all six scenarios before listing anything.
        let step = element("next.step.act.backup.confirm-medical-backup", in: app)
        XCTAssertTrue(step.waitForExistence(timeout: 30), "the oxygen backup should be a next step for the Oak household")
        for _ in 0..<4 where !step.isHittable { app.swipeUp() }
        step.tap()
        let markDone = element("next.markDone", in: app)
        for _ in 0..<6 where !(markDone.exists && markDone.isHittable) { app.swipeUp() }
        XCTAssertTrue(markDone.waitForExistence(timeout: 5))
        markDone.tap()
        XCTAssertTrue(wait(upTo: 5) { !markDone.isEnabled }, "Mark completed should become Completed")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let done = element("next.completedSection", in: app)
        for _ in 0..<8 where !done.exists { app.swipeUp() }
        XCTAssertTrue(done.exists, "the completed preparation should be listed under Done")
    }

    func testOutageCardFillInClosesGapsAndShares() {
        let app = launch()
        chooseSampleHousehold("hh-oak", in: app)
        let open = app.buttons["next.outageCard"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the outage card is one tap from Next steps")
        open.tap()
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Runtime on backup: unknown — confirm with the manufacturer or care plan"].exists,
                      "an unknown runtime must be printed as unknown")

        // Fill in what's missing: the battery station works with the concentrator, tested, 6 hours documented.
        let fix = element("card.fix", in: app)
        for _ in 0..<6 where !(fix.exists && fix.isHittable) { app.swipeUp() }
        fix.tap()
        let worksWith = app.switches.matching(identifier: "medical.worksWith").firstMatch
        for _ in 0..<4 where !(worksWith.exists && worksWith.isHittable) { app.swipeUp() }
        XCTAssertTrue(worksWith.waitForExistence(timeout: 5))
        if (worksWith.value as? String) != "1" { worksWith.switches.firstMatch.tap() }
        let runtime = element("medical.runtime", in: app)
        for _ in 0..<4 where !(runtime.exists && runtime.isHittable) { app.swipeUp() }
        runtime.tap()
        runtime.typeText("6")
        app.buttons["medical.save"].tap()

        XCTAssertTrue(app.staticTexts["Runtime on backup: 6 hours (documented by the household)"].waitForExistence(timeout: 10),
                      "the recorded runtime should be on the card")
        let share = element("card.share", in: app)
        for _ in 0..<10 where !(share.exists && share.isHittable) { app.swipeUp() }
        share.tap()
        XCTAssertTrue(app.navigationBars["Plan preview"].waitForExistence(timeout: 10), "the card PDF preview should open")
    }

    func testShareWithFamilyPreview() {
        let app = launch()
        chooseSampleHousehold("hh-oak", in: app)
        let share = app.buttons["next.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        let preview = element("share.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        XCTAssertTrue(app.navigationBars["Plan preview"].waitForExistence(timeout: 30), "plan and card PDF preview should open")
    }
}
