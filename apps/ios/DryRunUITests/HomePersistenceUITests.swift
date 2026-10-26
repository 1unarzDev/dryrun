import XCTest

/// Physical-device persistence check in a UUID-isolated encrypted test vault.
/// Originals and failure attachments are restricted to dedicated reviewers.
@MainActor
final class HomePersistenceUITests: XCTestCase {
    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let item = control(id, in: app)
        _ = item.waitForExistence(timeout: 10)
        for _ in 0..<12 where !item.isHittable { app.swipeUp() }
        XCTAssertTrue(item.isHittable, "Control must be reachable: \(id)")
        if item.isHittable { item.tap() }
    }
    private func openEditor(_ app: XCUIApplication) {
        tap("next.home", in: app)
        tap("home.edit", in: app)
    }
    func testRoomAndOpeningEditsSurvivePhysicalAppRelaunch() {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingVaultID", namespace, "-disableAnimations", "-demoHousehold", "hh-oak", "-demoLocale", "en"]
        app.launch()
        openEditor(app)
        tap("home.editRoom.sp-living", in: app)
        let name = app.textFields["home.roomName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        let previous = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Persistence test room")
        tap("home.save", in: app)
        tap("home.edit", in: app)
        tap("home.editOpening.pt-front", in: app)
        let kind = app.buttons["home.opening.type.window"]
        XCTAssertTrue(kind.waitForExistence(timeout: 10))
        kind.tap()
        tap("home.save", in: app)
        app.terminate()

        // No demo flag: restore the actual encrypted test data rather than reset it.
        app.launchArguments = ["-uiTestingVaultID", namespace, "-disableAnimations"]
        app.launch()
        openEditor(app)
        tap("home.editRoom.sp-living", in: app)
        XCTAssertEqual(app.textFields["home.roomName"].value as? String, "Persistence test room")
        tap("home.allItems", in: app)
        tap("home.editOpening.pt-front", in: app)
        XCTAssertTrue(app.buttons["home.opening.type.window"].isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "physical-home-restored-opening"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
        // Retained namespace is synthetic evidence; it contains no owner data.
    }
}
