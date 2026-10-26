import XCTest

/// Authored smoke matrix. Only a dedicated output reviewer may execute/inspect
/// its attachments because the native feature can display generated material.
@MainActor
final class FamilyHazardMatrixUITests: XCTestCase {
    func testEverySelectableFamilyMakesAChoiceInEveryHazard() {
        let families = ["hh-oak", "hh-lake", "hh-pine"]
        let hazards = ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"]
        for family in families {
            for hazard in hazards {
                let app = XCUIApplication()
                app.launchArguments = ["-uiTestingInMemory", "-disableAnimations", "-demoHousehold", family,
                                       "-demoLocale", "en", "-demoScenario", hazard, "-demoStep", "decision"]
                app.launch()
                let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "decision.option.")).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 20), "Expected a meaningful authored decision: \(family)/\(hazard)")
                for _ in 0..<6 where option.exists && !option.isHittable { app.swipeUp() }
                XCTAssertTrue(option.isHittable, "Decision must be reachable: \(family)/\(hazard)")
                guard option.exists && option.isHittable else { app.terminate(); continue }
                let before = XCTAttachment(screenshot: app.screenshot())
                before.name = "matrix-\(family)-\(hazard)-decision"; before.lifetime = .keepAlways; add(before)
                option.tap()
                let feedback = app.descendants(matching: .any).matching(identifier: "rehearsal.choiceFeedback").firstMatch
                XCTAssertTrue(feedback.waitForExistence(timeout: 15), "Accepted choice must render its consequence: \(family)/\(hazard)")
                let after = XCTAttachment(screenshot: app.screenshot())
                after.name = "matrix-\(family)-\(hazard)-accepted"; after.lifetime = .keepAlways; add(after)
                app.terminate()
            }
        }
    }
}
