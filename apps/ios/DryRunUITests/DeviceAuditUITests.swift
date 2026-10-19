import XCTest

/// Wired-iPhone audit journeys (fictional in-memory demos only). Every step keeps a screenshot so the rendering can
/// be reviewed; passing here proves the controls are reachable, not that the drawing or the exercise is correct.
@MainActor
final class DeviceAuditUITests: XCTestCase {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-demoLocale", "en"] + arguments
        app.launch()
        return app
    }
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func scroll(_ app: XCUIApplication, up: Bool) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.70))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.36))
        if up { low.press(forDuration: 0.05, thenDragTo: high) } else { high.press(forDuration: 0.05, thenDragTo: low) }
    }
    @discardableResult
    private func reveal(_ id: String, in app: XCUIApplication, steps: Int = 14) -> XCUIElement {
        let control = element(id, in: app)
        _ = control.waitForExistence(timeout: 3)
        for _ in 0..<steps where !(control.exists && control.isHittable) { scroll(app, up: true) }
        return control
    }

    func testAdaptiveApartmentFireCommitsActionsFromReceipts() {
        let app = launch(["-demoHousehold", "hh-oak", "-demoHome", "apartment-complex", "-demoScenario", "home-fire", "-demoAdaptive"])
        XCTAssertTrue(element("adaptive.header", in: app).waitForExistence(timeout: 30))
        shot("adaptive-fire-01-open", app)
        var moment = 2
        for _ in 0..<8 {
            if element("decision.option", in: app).exists || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch.exists { break }
            let next = element("adaptive.next", in: app)
            guard next.waitForExistence(timeout: 10), next.isEnabled else { break }
            next.tap()
            shot(String(format: "adaptive-fire-%02d-moment", moment), app); moment += 1
        }
        let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "a due authored choice is offered")
        if !option.isHittable { reveal(option.identifier, in: app) }
        shot("adaptive-fire-decision", app)
        option.tap()
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 10))
        shot("adaptive-fire-you-did", app)
        let more = reveal("adaptive.otherActions", in: app)
        if more.exists { more.tap(); shot("adaptive-fire-other-actions", app) }
        for index in 0..<10 {
            let next = element("adaptive.next", in: app)
            if !next.exists || !next.isEnabled {
                let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
                guard option.exists else { break }
                if !option.isHittable { reveal(option.identifier, in: app) }
                option.tap()
                continue
            }
            next.tap()
            shot(String(format: "adaptive-fire-later-%02d", index), app)
        }
        let finished = element("adaptive.finishedCard", in: app)
        if !finished.exists { element("adaptive.end", in: app).tap() }
        XCTAssertTrue(finished.waitForExistence(timeout: 15))
        reveal("adaptive.finishedCard", in: app)
        shot("adaptive-fire-finished", app)
    }

    func testAdaptiveWaterOutageWaterPolicyChangesTheCommittedSituation() {
        let app = launch(["-demoHousehold", "hh-oak", "-demoScenario", "water-outage", "-demoAdaptive"])
        XCTAssertTrue(element("adaptive.header", in: app).waitForExistence(timeout: 30))
        shot("adaptive-water-01-open", app)
        let more = reveal("adaptive.otherActions", in: app)
        XCTAssertTrue(more.exists)
        more.tap()
        let essential = app.buttons.matching(NSPredicate(format: "label CONTAINS 'only for essentials'")).firstMatch
        XCTAssertTrue(essential.waitForExistence(timeout: 10))
        shot("adaptive-water-02-actions", app)
        essential.tap()
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 10))
        shot("adaptive-water-03-you-did", app)
        for index in 0..<4 {
            let next = element("adaptive.next", in: app)
            guard next.exists, next.isEnabled else { break }
            next.tap()
            shot(String(format: "adaptive-water-%02d-later", index + 4), app)
        }
        let services = reveal("adaptive.services", in: app)
        if services.exists { services.tap(); shot("adaptive-water-services", app) }
    }

    /// Live synthetic loop: committed family action -> Core -> Gemini (gateway) -> Core tool previews -> validated
    /// director commit -> next decision. Runs only when TEST_RUNNER_AIGATEWAY/_AIGATEWAYTOKEN are supplied at run time.
    func testGeminiDirectsTheFictionalApartmentFireThroughValidatedCommits() throws {
        let env = ProcessInfo.processInfo.environment
        guard let gateway = env["AIGATEWAY"], let token = env["AIGATEWAYTOKEN"] else { throw XCTSkip("no development gateway supplied") }
        let scenario = env["AISCENARIO"] ?? "home-fire"
        let home = env["AIHOME"] ?? "apartment-complex"
        let app = launch(["-demoHousehold", "hh-oak", "-demoHome", home, "-demoScenario", scenario, "-demoAdaptive",
                          "-aiGateway", gateway, "-aiGatewayToken", token])
        XCTAssertTrue(element("adaptive.header", in: app).waitForExistence(timeout: 30))
        let toggle = app.switches["adaptive.cloudToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "cloud director offered for the fictional household")
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
        shot("gemini-\(scenario)-00-optin", app)
        var turn = 1, geminiTurns = 0
        for _ in 0..<7 {
            let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'"))
            if option.firstMatch.exists {
                // Vary the family's answers so different committed actions reach the director.
                let pick = option.count > 1 && turn % 2 == 0 ? option.element(boundBy: 1) : option.firstMatch
                if !pick.isHittable { reveal(pick.identifier, in: app) }
                pick.tap()
                shot(String(format: "gemini-\(scenario)-%02d-answered", turn), app)
            }
            let next = element("adaptive.next", in: app)
            guard next.waitForExistence(timeout: 10) else { break }
            if !next.isEnabled { if element("adaptive.finishedCard", in: app).exists { break } else { continue } }
            next.tap()
            // First contact with the development gateway asks for Local Network access for this test app.
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            // A Gemini turn waits on the gateway; the Next button comes back once the commit is published.
            let done = NSPredicate(format: "isEnabled == true OR exists == false")
            _ = XCTWaiter.wait(for: [expectation(for: done, evaluatedWith: next)], timeout: 150)
            shot(String(format: "gemini-\(scenario)-%02d-director", turn), app)
            if app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'suggested by Gemini'")).firstMatch.exists { geminiTurns += 1 }
            turn += 1
            if element("adaptive.finishedCard", in: app).exists { break }
        }
        // Fallback turns are legitimate, but this journey must show real Gemini-directed, host-validated commits.
        XCTAssertGreaterThan(geminiTurns, 0, "at least one committed turn was directed by Gemini")
        shot("gemini-\(scenario)-final", app)
    }

    func testTypedSupplyItemsAreReviewedOnceAndChangeGaps() {
        let app = launch(["-demoHousehold", "hh-oak"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let all = reveal("next.showAll", in: app, steps: 6)
        if all.exists { all.tap() }
        let water = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'next.step.' AND identifier CONTAINS[c] 'water'")).firstMatch
        for _ in 0..<12 where !(water.exists && water.isHittable) { scroll(app, up: true) }
        XCTAssertTrue(water.exists, "a water preparation is offered")
        water.tap()
        let open = reveal("supplies.inventory", in: app, steps: 4)
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        shot("inventory-01-empty", app)
        let quantity = app.textFields["inventory.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        /// Opens a List picker by its visible label and chooses an option.
        func pick(_ label: String, _ option: String) {
            let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<8 where !(picker.exists && picker.isHittable) { scroll(app, up: false) }
            XCTAssertTrue(picker.exists, label)
            picker.tap()
            let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
            if choice.waitForExistence(timeout: 5) { choice.tap() }
        }
        func segment(_ id: String, _ option: String) {
            let control = app.segmentedControls[id]
            for _ in 0..<8 where !(control.exists && control.isHittable) { scroll(app, up: false) }
            XCTAssertTrue(control.exists, id)
            control.buttons[option].tap()
        }
        func enter(_ amount: String) {
            quantity.tap(); quantity.typeText(amount)
            let done = app.buttons["inventory.keyboardDone"]
            if done.waitForExistence(timeout: 3) { done.tap() }
        }
        enter("4")
        segment("inventory.ready", "Yes")
        segment("inventory.reachable", "Yes")
        app.buttons["inventory.stage"].tap()
        shot("inventory-02-staged-water", app)
        pick("Item", "Flashlight")
        enter("2")
        segment("inventory.ready", "Yes")
        segment("inventory.reachable", "Yes")
        app.buttons["inventory.stage"].tap()
        let confirm = reveal("inventory.confirm", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("inventory-03-review", app)
        confirm.tap()
        // Confirmed, usable amounts now produce a concrete water result instead of "not enough recorded".
        let concrete = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Short by' OR label CONTAINS 'meets the'")).firstMatch
        for _ in 0..<8 where !concrete.exists { scroll(app, up: true) }
        XCTAssertTrue(concrete.exists, "confirmed usable water gives a computed gap")
        shot("inventory-04-gaps", app)
        let recorded = element("inventory.recorded", in: app)
        for _ in 0..<10 where !recorded.exists { scroll(app, up: false) }
        XCTAssertTrue(recorded.exists)
        shot("inventory-05-recorded", app)
    }

    /// Marker relocation from the Home marker list: invalid input keeps the editor open and the old marker intact;
    /// a valid visible position is applied by Save without tapping Apply, and moving it needs location review again.
    func testMarkerRelocationSaveWithoutApplyAndInvalidInputStaysOpen() {
        let app = launch(["-demoHousehold", "hh-oak", "-demoHome", "ranch"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let open = reveal("next.home", in: app)
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let key = reveal("home.markerKey", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        let keyToggle = app.buttons.matching(NSPredicate(format: "label == 'Safety markers'")).firstMatch
        if keyToggle.exists { keyToggle.tap() } else { key.tap() }
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.marker.' AND NOT (identifier IN %@)",
                                                      ["home.markerKey", "home.marker.x", "home.marker.y", "home.marker.apply", "home.marker.locationChecked"])).firstMatch
        for _ in 0..<6 where !(marker.exists && marker.isHittable) { scroll(app, up: true) }
        XCTAssertTrue(marker.exists, "a recorded marker is listed")
        let markerID = marker.identifier
        marker.tap()
        let x = app.textFields["home.marker.x"]
        XCTAssertTrue(x.waitForExistence(timeout: 10))
        shot("marker-01-editor", app)
        let original = Double((x.value as? String) ?? "") ?? 1
        func replace(_ field: XCUIElement, _ text: String) {
            field.tap()
            if let current = field.value as? String, !current.isEmpty {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
            }
            field.typeText(text)
        }
        replace(x, "abc")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(x.waitForExistence(timeout: 3), "invalid input keeps the editor open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'previous marker is unchanged'")).firstMatch.exists)
        shot("marker-02-invalid-kept-open", app)
        let moved = String(format: "%.2f", max(0.3, original - 0.25))
        replace(x, moved)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(element("home.scene", in: app).waitForExistence(timeout: 10), "a valid visible placement saves without Apply")
        let reopened = app.buttons[markerID]
        for _ in 0..<6 where !(reopened.exists && reopened.isHittable) { scroll(app, up: true) }
        XCTAssertTrue(reopened.label.contains("Location needs review"), "a moved marker needs its location reviewed again")
        shot("marker-03-saved-needs-review", app)
        reopened.tap()
        XCTAssertTrue(x.waitForExistence(timeout: 10))
        XCTAssertEqual(Double((x.value as? String) ?? ""), Double(moved), "the saved position is the one that was visible")
        shot("marker-04-reopened", app)
    }

    func testPracticeCheckRecordsFourFirstAnswersBeforeFeedback() {
        let app = launch(["-demoHousehold", "hh-oak", "-demoHome", "ranch", "-demoTab", "rehearse"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let open = reveal("practice.open", in: app)
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let start = reveal("practice.start", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        shot("practice-00-intro", app)
        start.tap()
        for number in 1...4 {
            XCTAssertTrue(element("practice.progress", in: app).waitForExistence(timeout: 20), "question \(number)")
            shot("practice-\(number)-question", app)
            let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'")).firstMatch
            if option.waitForExistence(timeout: 3) {
                if !option.isHittable { reveal(option.identifier, in: app) }
                option.tap()
            } else {
                let actions = element("practice.actions", in: app)
                for _ in 0..<6 where !(actions.exists && actions.isHittable) { scroll(app, up: true) }
                let first = actions.buttons.element(boundBy: 0)
                XCTAssertTrue(first.waitForExistence(timeout: 10), "an action is offered")
                first.tap()
            }
            XCTAssertTrue(element("practice.feedback", in: app).waitForExistence(timeout: 15), "feedback follows the saved answer")
            shot("practice-\(number)-feedback", app)
            reveal("practice.next", in: app).tap()
        }
        let result = reveal("practice.result", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(result.label.contains("4/4 assessed") || result.label.contains("/4 assessed"))
        shot("practice-5-finished", app)
    }

    func testScorecardOnPrepareForEachHousingDemo() {
        for home in ["ranch", "apartment-complex", "manufactured", "twostory"] {
            let app = launch(["-demoHousehold", "hh-oak", "-demoHome", home])
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
            let card = reveal("score.card", in: app, steps: 8)
            XCTAssertTrue(card.waitForExistence(timeout: 30), home)
            shot("score-\(home)", app)
            let how = reveal("score.how", in: app, steps: 6)
            if how.exists { how.tap(); scroll(app, up: true); shot("score-\(home)-how", app) }
            app.terminate()
        }
    }

    func testEveryFloorOfEveryHousingDemoInBothViews() {
        // Floors come from -demoHomeFloor so every floor is captured without driving the menu picker.
        let floors = ["apartment-complex": 3, "manufactured": 1, "twostory": 2, "ranch": 1]
        for (home, count) in floors.sorted(by: { $0.key < $1.key }) {
            for floor in 0..<count {
                for mode in ["2d", "3d"] {
                    let app = launch(["-demoHousehold", "hh-oak", "-demoHome", home, "-demoHomeMode", mode, "-demoHomeFloor", "\(floor)"])
                    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
                    let open = reveal("next.home", in: app)
                    XCTAssertTrue(open.waitForExistence(timeout: 10), home)
                    open.tap()
                    XCTAssertTrue(element("home.scene", in: app).waitForExistence(timeout: 20), home)
                    shot("home-\(home)-floor\(floor + 1)-\(mode)", app)
                    if mode == "2d" {
                        // The legend/marker key sits below the drawing.
                        scroll(app, up: true)
                        shot("home-\(home)-floor\(floor + 1)-\(mode)-below", app)
                    }
                    app.terminate()
                }
            }
        }
    }
}
