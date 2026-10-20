import XCTest

/// The six hazard rehearsals through ordinary navigation: setup questions, a non-default setup answer, the run to
/// the end, and the debrief's hazard-specific outcomes. Fictional in-memory demos only; every step keeps a screenshot
/// so the rendering can be reviewed. Passing proves the flow is reachable and finishes, not that the content is right.
@MainActor
final class SixHazardUITests: XCTestCase {
    /// Scenario → one non-default setup option for the Oak household (private well, oxygen concentrator).
    static let setupChoices: [(scenario: String, option: String)] = [
        ("home-fire", "hallway-smoke"), ("tornado", "night"), ("flash-flood", "home-flooded"),
        ("freeze-power-loss", "extended-outage"), ("heat-grid-strain", "no-rotating-outage"), ("water-outage", "with-power-loss"),
    ]

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
    private func reveal(_ control: XCUIElement, in app: XCUIApplication, steps: Int = 14) -> XCUIElement {
        _ = control.waitForExistence(timeout: 3)
        for _ in 0..<steps where !(control.exists && control.isHittable) { scroll(app, up: true) }
        return control
    }

    func testFireSetupToDebrief() { run(0) }
    func testTornadoSetupToDebrief() { run(1) }
    func testFlashFloodSetupToDebrief() { run(2) }
    func testFreezeSetupToDebrief() { run(3) }
    func testHeatSetupToDebrief() { run(4) }
    func testWaterOutageSetupToDebrief() { run(5) }

    private func run(_ index: Int) {
        let (scenario, option) = Self.setupChoices[index]
        let app = launch(["-demoHousehold", "hh-oak", "-demoHome", "ranch", "-demoTab", "rehearse"])
        let card = reveal(element("scenario.\(scenario)", in: app), in: app)
        XCTAssertTrue(card.exists, "\(scenario) card is listed")
        card.tap()

        // Normal entry opens setup first; nothing starts until Start.
        XCTAssertTrue(element("rehearsal.setup", in: app).waitForExistence(timeout: 10), "\(scenario) opens its setup")
        shot("\(scenario)-01-setup", app)
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                                                      "rehearsal.setup.", ".\(option)")).firstMatch
        reveal(choice, in: app)
        XCTAssertTrue(choice.exists, "\(scenario) offers \(option)")
        choice.tap()
        shot("\(scenario)-02-setup-chosen", app)
        let start = reveal(element("rehearsal.setup.start", in: app), in: app)
        XCTAssertTrue(start.isEnabled, "\(scenario) can start")
        start.tap()

        // Advance to the end, answering each decision with its first option.
        let next = element("rehearsal.next", in: app), debrief = element("rehearsal.debrief", in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        var decisions = 0, steps = 0
        while !(debrief.exists && debrief.isEnabled), steps < 60 {
            steps += 1
            let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'decision.option.'"))
            if options.count > 0 {
                let first = reveal(options.firstMatch, in: app, steps: 8)
                if decisions == 0 { shot("\(scenario)-03-decision", app) }
                first.tap(); decisions += 1
                continue
            }
            if next.isEnabled { next.tap() }
            if steps == 2 { shot("\(scenario)-04-scene", app) }
        }
        XCTAssertTrue(debrief.isEnabled, "\(scenario) reaches its end within 60 steps")
        shot("\(scenario)-05-end", app)
        debrief.tap()
        XCTAssertTrue(element("debrief.hazard.\(scenario)", in: app).waitForExistence(timeout: 10), "\(scenario) debrief names its hazard")
        shot("\(scenario)-06-debrief", app)
        let outcomes = reveal(element("debrief.outcomes.\(scenario)", in: app), in: app, steps: 20)
        XCTAssertTrue(outcomes.exists, "\(scenario) debrief shows final outcome evidence")
        shot("\(scenario)-07-outcomes", app)
        XCTAssertGreaterThan(decisions, 0, "\(scenario) asks at least one decision")
    }
}
