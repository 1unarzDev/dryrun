import XCTest

/// Beacon without launch configuration: no -aiGateway arguments and no gateway environment, as when the app is
/// opened from the home screen. The gateway must come from the bundled BeaconGateway.json that
/// scripts/mac/beacon-gateway.sh writes; run that script on the Mac first. Fictional in-memory household only.
@MainActor
final class BeaconUnpluggedUITests: XCTestCase {
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testBeaconTailorsPrepareFromBundledConfig() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-noSavedBeacon"]
        app.launch()

        let more = element("onboarding.moreExamples", in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 20), "Onboarding did not appear")
        more.tap()
        let oak = element("onboarding.sample.hh-oak", in: app)
        XCTAssertTrue(oak.waitForExistence(timeout: 5))
        oak.tap()

        // The card exists only when the app found a gateway; here that can only be the bundled config.
        let card = element("next.ai", in: app)
        // Drag near the leading edge so the gesture never lands on a task row or map.
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.72))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.38))
        for _ in 0..<12 where !(card.exists && card.isHittable) {
            if !card.waitForExistence(timeout: 3) || !card.isHittable { low.press(forDuration: 0.05, thenDragTo: high) }
        }
        XCTAssertTrue(card.exists, "No Beacon card: BeaconGateway.json missing from the build")

        // Tailored without a tap; a live answer, not the recorded replay.
        let applied = element("next.ai.applied", in: app)
        XCTAssertTrue(applied.waitForExistence(timeout: 120), "Beacon did not tailor Prepare")
        XCTAssertFalse(element("next.ai.replay", in: app).exists, "Showed the replay: phone could not reach the gateway")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "beacon-prepare-unplugged"; shot.lifetime = .keepAlways
        add(shot)
    }
}
