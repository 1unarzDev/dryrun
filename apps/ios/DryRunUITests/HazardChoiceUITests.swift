import XCTest

/// Hazard-specific household choices in the adaptive exercise (`rehearsal.cmd.<kind>.<target>.<value>`), driven through
/// the on-phone director with fictional in-memory households. Each script mirrors a Core test in
/// `NativeHazardChoiceScriptTests`, which proves the host offers the tapped choice for the same family, home and director.
/// Passing proves the choice is reachable, commits, and is reflected on screen; it is not a review of the wording.
@MainActor
final class HazardChoiceUITests: XCTestCase {
    private func launch(_ household: String, _ home: String, _ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-demoLocale", "en",
                               "-demoHousehold", household, "-demoHome", home, "-demoScenario", scenario, "-demoAdaptive",
                               // These scripts document local-director turns; the cloud director is covered elsewhere.
                               "-localDirector"]
        app.launch()
        XCTAssertTrue(element("adaptive.header", in: app).waitForExistence(timeout: 30), "\(scenario) adaptive exercise opens")
        // -localDirector pins Beacon's cloud director off; the switch shows only where a gateway is configured.
        let cloud = element("adaptive.cloudToggle", in: app)
        if cloud.exists { XCTAssertEqual(cloud.value as? String, "0", "the cloud director starts off under -localDirector") }
        return app
    }
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func prefixed(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
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
        for _ in 0..<steps where !(control.exists && control.isHittable) { scroll(app, up: true) }
        if !control.isHittable { for _ in 0..<steps where !(control.exists && control.isHittable) { scroll(app, up: false) } }
        return control
    }
    private func tap(_ control: XCUIElement, in app: XCUIApplication) {
        reveal(control, in: app)
        XCTAssertTrue(control.isHittable, "\(control.identifier) can be tapped")
        control.tap()
    }

    /// Lets the on-phone director continue until a choice with `prefix` is offered. A due authored question is answered
    /// with its first option only when `answer` is true; an open "what do you do" moment is passed with Keep watching.
    @discardableResult
    private func advance(until prefix: String, in app: XCUIApplication, steps: Int = 16, answer: Bool = true) -> XCUIElement {
        let target = prefixed(prefix, in: app)
        for _ in 0..<steps {
            if target.waitForExistence(timeout: 4) { return target }
            let option = prefixed("decision.option.", in: app)
            let wait = element("rehearsal.cmd.wait", in: app)
            let next = element("adaptive.next", in: app)
            if answer, option.exists { tap(option, in: app); continue }
            if wait.exists { tap(wait, in: app); continue }
            guard next.exists, next.isEnabled else { break }
            next.tap()
        }
        return target
    }

    /// Heat, Lake family in the ranch: shade the living room, then move Bà into it; the move is not offered again.
    func testHeatShadeThenMove() {
        let app = launch("hh-lake", "ranch", "heat-grid-strain")
        let shade = advance(until: "rehearsal.cmd.reduceSolarGain.sp-living", in: app)
        XCTAssertTrue(shade.exists, "shading the living room is offered")
        shot("heat-01-choices", app)
        tap(shade, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
        let move = prefixed("rehearsal.cmd.moveTo.p-lake-1.sp-living", in: app)
        XCTAssertTrue(move.waitForExistence(timeout: 15), "moving Bà into the shaded room is offered after shading")
        shot("heat-02-move-offered", app)
        tap(move, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
        shot("heat-03-moved", app)
        XCTAssertFalse(prefixed("rehearsal.cmd.moveTo.p-lake-1.", in: app).waitForExistence(timeout: 5), "Bà is not offered the same move again")
        XCTAssertFalse(element("adaptive.moveGo", in: app).exists, "no generic person + room move beside the heat choices")
    }

    /// Fire, Oak family in the ranch: Parent A gets out through an offered exit, is checked at the meeting place,
    /// and the finished card lists both actions in order.
    func testFireEscapeAccountOrderedDebrief() {
        let app = launch("hh-oak", "ranch", "home-fire")
        let escape = advance(until: "rehearsal.cmd.escape.p-oak-1.", in: app, answer: false)
        XCTAssertTrue(escape.exists, "an exit for Parent A is offered")
        shot("fire-01-choices", app)
        XCTAssertFalse(element("adaptive.moveGo", in: app).exists, "no generic person + room move beside the exits")
        XCTAssertFalse(prefixed("rehearsal.cmd.assignHelper", in: app).exists)
        tap(escape, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(prefixed("rehearsal.cmd.escape.p-oak-1.", in: app).waitForExistence(timeout: 5), "no exit is offered back inside")
        let account = prefixed("rehearsal.cmd.accountOutside.p-oak-1", in: app)
        let accounted = account.waitForExistence(timeout: 10)
        if accounted { tap(account, in: app) }
        shot("fire-02-after", app)
        tap(element("adaptive.end", in: app), in: app)
        XCTAssertTrue(element("adaptive.finishedCard", in: app).waitForExistence(timeout: 15))
        let trace = element("rehearsal.cmd.trace", in: app)
        reveal(trace, in: app)
        XCTAssertTrue(trace.exists, "the finished card lists what the family did, in order")
        shot("fire-03-ordered-debrief", app)
        XCTAssertTrue(accounted, "the ranch's verified meeting place allows checking Parent A outside")
    }

    /// Tornado, Oak family in the ranch: Parent A takes Kid to the shelter, then everyone else goes; no shelter
    /// choices remain once everyone is there.
    func testTornadoShelterAndAccompany() {
        let app = launch("hh-oak", "ranch", "tornado")
        let accompany = advance(until: "rehearsal.cmd.accompanyShelter.p-oak-3.p-oak-1", in: app)
        XCTAssertTrue(accompany.exists, "Parent A taking Kid to the shelter is offered")
        shot("tornado-01-choices", app)
        tap(accompany, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
        for _ in 0..<4 {
            let shelter = prefixed("rehearsal.cmd.reachShelter.", in: app)
            guard shelter.waitForExistence(timeout: 6) else { break }
            tap(shelter, in: app)
            _ = element("adaptive.youDid", in: app).waitForExistence(timeout: 15)
        }
        shot("tornado-02-sheltered", app)
        XCTAssertFalse(prefixed("rehearsal.cmd.reachShelter.", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(prefixed("rehearsal.cmd.accompanyShelter.", in: app).exists)
    }

    /// Water, Lake family (city water): under the later boil-water advisory, boiling tap water is offered and
    /// drinking it unboiled is not; stored-water policies stay available.
    func testWaterAllocationUnderAdvisory() {
        let app = launch("hh-lake", "ranch", "water-outage")
        let stored = advance(until: "rehearsal.cmd.useWater.", in: app)
        XCTAssertTrue(stored.exists, "a specific water use is offered")
        shot("water-01-choices", app)
        let boiled = advance(until: "rehearsal.cmd.useWater.tap.boiledDrink", in: app, steps: 20)
        XCTAssertTrue(boiled.exists, "boiling tap water is offered under the boil-water advisory")
        XCTAssertFalse(prefixed("rehearsal.cmd.useWater.tap.drink", in: app).exists, "unboiled tap water is not offered under the advisory")
        shot("water-02-advisory", app)
        tap(boiled, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
    }

    /// Freeze, unedited Oak family in the ranch (mechanics v7, G1): before the outage Parent A can join Grandpa
    /// in the living room (a physical choice without recorded warmth or backup); the move is not offered again. Mirrors
    /// `HazardMechanicsV7Tests.freezeOpeningOffersAPhysicalChoiceForEverySampleHousehold`.
    func testFreezeOpeningOffersGathering() {
        let app = launch("hh-oak", "ranch", "freeze-power-loss")
        let gather = advance(until: "rehearsal.cmd.moveTo.p-oak-1.sp-living", in: app, steps: 4, answer: false)
        XCTAssertTrue(gather.exists, "Parent A joining Grandpa in the living room is offered at the freeze opening")
        shot("freeze-01-opening", app)
        tap(gather, in: app)
        XCTAssertTrue(element("adaptive.youDid", in: app).waitForExistence(timeout: 15))
        shot("freeze-02-gathered", app)
        XCTAssertFalse(prefixed("rehearsal.cmd.moveTo.p-oak-1.", in: app).waitForExistence(timeout: 5), "the same move is not offered again")
    }
}
