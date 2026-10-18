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
    private func tap(_ id: String, in app: XCUIApplication) {
        let control = element(id, in: app)
        for _ in 0..<8 {
            if control.exists && control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 15), "Missing control: \(id)")
        XCTAssertTrue(control.isHittable, "Hidden control: \(id)")
        control.tap()
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
        tap("next.contacts", in: app)
        let name = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.name.'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Example trusted contact")
        let phone = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.phone.'")).firstMatch
        phone.tap(); phone.typeText("+44 20 7946 0958")
        tap("focused.save", in: app)
        tap("next.outageCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Example trusted contact'")).firstMatch.exists)
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
        XCTAssertTrue(element("family.addPerson", in: app).waitForExistence(timeout: 10))
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
        tap("plan.map", in: app)
        let list = app.segmentedControls.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(list.waitForExistence(timeout: 10)); list.tap()
        tap("map.addText", in: app)
        tap("place.name", in: app)
        element("place.name", in: app).typeText("Example backup meeting place")
        tap("place.purpose", in: app)
        app.buttons["Backup meetup outside neighborhood"].tap()
        tap("place.address", in: app)
        element("place.address", in: app).typeText("456 Fictional Road")
        tap("place.instructions", in: app)
        element("place.instructions", in: app).typeText("Call our example contact before going")
        tap("place.save", in: app)
        XCTAssertTrue(app.staticTexts["Example backup meeting place"].waitForExistence(timeout: 10))
        tap("map.done", in: app)

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
        app.tabBars.buttons.element(boundBy: 2).tap()
        for _ in 0..<8 { app.swipeDown() }
        tap("plan.familyCard", in: app)
        XCTAssertTrue(element("card.page", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Example backup meeting place'")).firstMatch.exists)
        tap("card.share", in: app)
        XCTAssertTrue(element("pdf.preview", in: app).waitForExistence(timeout: 20))
    }

}
