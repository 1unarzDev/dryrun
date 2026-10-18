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
}
