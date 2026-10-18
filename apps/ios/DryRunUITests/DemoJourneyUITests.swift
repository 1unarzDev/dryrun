import XCTest

/// Current three-destination journeys. Authored on Linux; execution requires the native handoff.
/// In-memory UI runs isolate fictional data. Real vault relaunch is a separate manual/device gate.
@MainActor
final class DemoJourneyUITests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations"] + arguments
        app.launch()
        return app
    }
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    /// Scrolls in small steps until the control is on screen and not under the floating tab bar, then back up if
    /// a step overshot. Lazy list rows only exist once scrolled near.
    @discardableResult
    private func reveal(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let control = element(id, in: app)
        _ = control.waitForExistence(timeout: 3)
        for _ in 0..<12 {
            if control.exists && control.isHittable && !underTabBar(control, in: app) { return control }
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<6 {
            if control.exists && control.isHittable && !underTabBar(control, in: app) { return control }
            app.swipeDown(velocity: .slow)
        }
        return control
    }
    private func underTabBar(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists, bar.isHittable else { return false }
        return control.frame.maxY > bar.frame.minY - 4 && control.frame.minY < bar.frame.maxY
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let control = reveal(id, in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 15), "Missing control: \(id)")
        XCTAssertTrue(control.isHittable, "Hidden control: \(id)")
        control.tap()
    }
    private func hasText(_ text: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 5)
    }
    private func openPlan(_ app: XCUIApplication) {
        app.tabBars.buttons.element(boundBy: 2).tap()
        for _ in 0..<6 { app.swipeDown() }
    }
    private func sample(_ locale: String = "en") -> XCUIApplication {
        let app = launch(["-demoHousehold", "hh-oak", "-demoLocale", locale])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        return app
    }

    func testSkipAddressAndScanAddContactOpenAndPreviewUniversalCard() {
        let app = launch()
        XCTAssertTrue(app.buttons["onboarding.create"].waitForExistence(timeout: 20))
        app.buttons["onboarding.create"].tap()
        tap("setup.finishLater", in: app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        openPlan(app)
        tap("plan.addContact", in: app)
        let name = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.name.'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Example trusted contact")
        let phone = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.phone.'")).firstMatch
        phone.tap(); phone.typeText("+44 20 7946 0958")
        tap("focused.save", in: app)
        app.tabBars.buttons.element(boundBy: 0).tap()
        tap("next.outageCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(hasText("Example trusted contact", in: app))
        tap("card.share", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 15))
    }

    func testPersonalLayoutAbsentShowsManualHomePath() {
        let app = launch()
        XCTAssertTrue(app.buttons["onboarding.create"].waitForExistence(timeout: 20))
        app.buttons["onboarding.create"].tap()
        tap("setup.finishLater", in: app)
        tap("next.home", in: app)
        XCTAssertTrue(element("home.addManual", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("home.scene", in: app).exists, "Personal setup must not invent an example layout")
    }

    func testFamilyEditorAndLivePlanHaveDirectEntryPoints() {
        let app = sample()
        tap("next.family", in: app)
        XCTAssertTrue(reveal("family.addPerson", in: app).exists)
        tap("focused.save", in: app)
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(element("plan.familyCard", in: app).waitForExistence(timeout: 10))
        tap("plan.familyCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
    }

    func testEachSpatialHazardShowsSceneAtBeginning() {
        for scenario in ["home-fire", "flash-flood", "tornado"] {
            let app = launch(["-demoHousehold", "hh-oak", "-demoScenario", scenario, "-demoStep", "start"])
            XCTAssertTrue(element("rehearsal.scene", in: app).waitForExistence(timeout: 20), scenario)
            XCTAssertTrue(element("rehearsal.next", in: app).exists)
            app.terminate()
        }
    }

    func testThreeSupportedLocalesOpenFamilyCardWithoutGenerate() {
        for locale in ["en", "es", "vi"] {
            let app = sample(locale)
            app.tabBars.buttons.element(boundBy: 2).tap()
            tap("plan.familyCard", in: app)
            XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10), locale)
            app.terminate()
        }
    }

    #if targetEnvironment(simulator)
    /// Real encrypted repository and Keychain bridge, isolated from normal app data. Relaunch reads
    /// persisted contacts/layout absence; this still does not establish device Data Protection or Print.
    func testEncryptedVaultRetainsLayoutlessContactAndCardAcrossProcessRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingVaultID", UUID().uuidString, "-disableAnimations"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.create"].waitForExistence(timeout: 20))
        app.buttons["onboarding.create"].tap()
        tap("setup.finishLater", in: app)
        openPlan(app)
        tap("plan.addContact", in: app)
        let name = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.name.'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Persisted fictional contact")
        let phone = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.phone.'")).firstMatch
        phone.tap(); phone.typeText("+44 20 7946 0958")
        tap("focused.save", in: app)
        app.tabBars.buttons.element(boundBy: 0).tap()
        tap("next.outageCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        tap("card.share", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["onboarding.create"].exists)
        tap("next.home", in: app)
        XCTAssertTrue(element("home.addManual", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("home.scene", in: app).exists)
        app.tabBars.buttons.element(boundBy: 2).tap()
        tap("plan.familyCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(hasText("Persisted fictional contact", in: app))
        tap("card.share", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 20))
    }
    #endif
    /// Manual address/pin keeps this connected journey independent of live Apple search results.
    /// Nearby discovery may run; this test does not certify its results or any ordinary map route.
    func testAddressMeetupPreparationRehearsalAndUpdatedPlanStayConnected() {
        let app = sample()
        app.tabBars.buttons.element(boundBy: 2).tap()
        tap("plan.address", in: app)
        tap("address.line", in: app)
        element("address.line", in: app).typeText("123 Fictional Lane")
        tap("address.latitude", in: app)
        element("address.latitude", in: app).typeText("32.2")
        tap("address.longitude", in: app)
        element("address.longitude", in: app).typeText("-98.2")
        tap("address.save", in: app)
        XCTAssertTrue(element("address.save", in: app).waitForNonExistence(timeout: 10), "Address editor did not close after saving")
        // The backup slot opens the map already set to that purpose; saving returns to Plan.
        tap("plan.meetup.backupMeetingPlace", in: app)
        let list = app.segmentedControls.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(list.waitForExistence(timeout: 10)); list.tap()
        tap("map.addText", in: app)
        tap("place.name", in: app)
        element("place.name", in: app).typeText("Example backup meeting place")
        tap("place.address", in: app)
        element("place.address", in: app).typeText("456 Fictional Road")
        tap("place.instructions", in: app)
        element("place.instructions", in: app).typeText("Call our example contact before going")
        tap("place.save", in: app)
        XCTAssertTrue(element("plan.meetup.backupMeetingPlace", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(hasText("Example backup meeting place", in: app))

        // A saved destination closes its own real preparation before any rehearsal is completed.
        app.tabBars.buttons.element(boundBy: 0).tap()
        let recorded = element("next.recorded.prep.backupMeetup", in: app)
        for _ in 0..<10 where !recorded.exists { app.swipeUp() }
        XCTAssertTrue(recorded.exists)
        app.tabBars.buttons.element(boundBy: 1).tap()
        tap("scenario.home-fire", in: app)
        XCTAssertTrue(element("rehearsal.scene", in: app).waitForExistence(timeout: 15))
        let debrief = element("rehearsal.debrief", in: app)
        XCTAssertTrue(debrief.waitForExistence(timeout: 10))
        for _ in 0..<50 {
            if debrief.isEnabled { break }
            let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
            if option.exists {
                tap(option.identifier, in: app)
            } else {
                let next = element("rehearsal.next", in: app)
                XCTAssertTrue(next.isEnabled, "Exercise has no available next decision or advance")
                if !next.isEnabled { break }
                next.tap()
            }
        }
        XCTAssertTrue(debrief.isEnabled)
        openPlan(app)
        tap("plan.familyCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(hasText("Example backup meeting place", in: app))
        // One share flow: choose content, then the preview is pushed inside the same sheet.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("plan.share", in: app)
        tap("share.preview", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 30))
        XCTAssertTrue(element("pdf.share", in: app).exists)
    }

    func testRehearsalShowsStepNotClockAndPlanSharesOnce() {
        let app = launch(["-demoHousehold", "hh-oak", "-demoScenario", "home-fire", "-demoStep", "decision"])
        XCTAssertTrue(element("rehearsal.scene", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(element("rehearsal.step", in: app).exists)
        openPlan(app)
        tap("plan.share", in: app)
        tap("share.preview", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 30))
    }

}
