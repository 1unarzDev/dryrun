import XCTest

/// Drives every entry in docs/integration/ui-inventory.md to its screen/sheet/state, asserts the identifiers that
/// prove the state was reached, and keeps one full-screen capture per entry (attachment name "<ID>-<size>-<locale>").
/// Fictional in-memory households only. Beacon is switched off (-noBeaconConfig, -noSavedBeacon) so captures carry
/// deterministic app text; the on-device briefing is never expanded. Captures are still handled by the phone
/// reviewer under the output firewall, like every native capture.
///
/// Filters (pass through xcodebuild as TEST_RUNNER_<NAME>=value):
///   INVENTORY_IDS=PREP,CARD-01     prefix match on entry IDs (default: all)
///   INVENTORY_LOCALE=en|es|vi      language and its matching fictional household (default en / hh-oak)
@MainActor
final class UIInventoryUITests: XCTestCase {
    enum Step {
        /// Tap the element with this exact identifier (scrolling to it first).
        case tap(String)
        /// Tap the first element whose identifier begins with this prefix.
        case tapPrefix(String)
        /// Select a tab bar item by index (0 Prepare, 1 Rehearse, 2 Plan).
        case tab(Int)
    }

    struct Entry {
        let id: String
        var args: [String] = []
        var steps: [Step] = []
        /// Identifiers (exact, or prefix when ending in ".") that must exist once the steps are done.
        var expect: [String] = []
        /// Scroll this identifier into view before the capture, if it exists (not required).
        var reveal: String? = nil
        /// True when the state needs a household, so it uses the locale's fictional household.
        var household = true
    }

    static let households = ["en": "hh-oak", "es": "hh-pine", "vi": "hh-lake"]
    static let hazards = ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"]

    /// Keep in the same order and with the same IDs as docs/integration/ui-inventory.md.
    static var entries: [Entry] {
        let prepare = ["-demoTab", "prepare"], plan = ["-demoTab", "plan"]
        var list: [Entry] = [
            // Onboarding and setup
            Entry(id: "ONB-01", expect: ["onboarding.demo"], household: false),
            Entry(id: "ONB-02", steps: [.tap("onboarding.moreExamples")], expect: ["onboarding.sample."], household: false),
            Entry(id: "ONB-03", steps: [.tap("onboarding.create")], expect: ["setup.next"], household: false),
            // Prepare
            Entry(id: "PREP-01", args: prepare, expect: ["rings.card", "next.actions", "next.step."]),
            Entry(id: "PREP-02", args: prepare, steps: [.tap("next.info")], expect: ["next.about"]),
            Entry(id: "PREP-03", args: prepare, steps: [.tap("rings.info")], expect: ["rings.caveat"]),
            Entry(id: "PREP-04", args: prepare, steps: [.tap("next.showAll")], expect: ["next.actions"]),
            Entry(id: "PREP-05", args: prepare, expect: ["family.panel"], reveal: "family.panel"),
            Entry(id: "PREP-06", args: prepare, steps: [.tapPrefix("family.panel.person.")], expect: ["focused.save", "family.relationship."]),
            Entry(id: "PREP-07", args: prepare, steps: [.tap("family.panel.editAll")], expect: ["family.householdName"]),
            Entry(id: "PREP-08", args: prepare, steps: [.tap("next.family"), .tap("family.addPerson")], expect: ["family.personName.", "family.relationship."]),
            Entry(id: "PREP-09", args: prepare, steps: [.tapPrefix("next.step.")]),
            Entry(id: "PREP-10", args: prepare, expect: ["next.questions"], reveal: "next.questions"),
            Entry(id: "PREP-11", args: prepare, reveal: "next.recordedSection"),
            Entry(id: "PREP-12", args: prepare, expect: ["score.card"], reveal: "score.card"),
            Entry(id: "PREP-13", args: prepare, steps: [.tap("score.how")], reveal: "score.how"),
            Entry(id: "PREP-14", args: prepare, steps: [.tap("next.inventory")], expect: ["inventory.kind"]),
            Entry(id: "PREP-15", args: prepare, steps: [.tap("next.shopping")], expect: ["shop.kit"]),
            Entry(id: "PREP-16", args: prepare, steps: [.tap("next.whereToGo")]),
            Entry(id: "PREP-17", args: prepare + ["-demoAlert", "tornado"], expect: ["alert.banner"]),
            Entry(id: "PREP-18", args: prepare, reveal: "next.finishCard"),
            // Emergency card
            Entry(id: "CARD-01", args: prepare, steps: [.tap("next.outageCard")], expect: ["card.page"]),
            Entry(id: "CARD-02", args: prepare, steps: [.tap("next.outageCard"), .tap("card.addDevice")], expect: ["medical.save"]),
            Entry(id: "CARD-03", args: prepare, steps: [.tap("next.outageCard"), .tap("card.share")], expect: ["pdf.preview"]),
            // Home
            Entry(id: "HOME-01", args: prepare + ["-demoHomeMode", "2d"], steps: [.tap("next.home")], expect: ["home.scene"]),
            Entry(id: "HOME-02", args: prepare + ["-demoHomeMode", "3d"], steps: [.tap("next.home")], expect: ["home.scene"]),
            Entry(id: "HOME-03", args: prepare + ["-demoHomeMode", "rooms"], steps: [.tap("next.home")]),
            Entry(id: "HOME-04", args: prepare + ["-demoHomeMode", "rooms"], steps: [.tap("next.home"), .tapPrefix("home.editRoom.")], expect: ["home.save"]),
            Entry(id: "HOME-05", args: prepare + ["-demoHome", "twostory", "-demoHomeMode", "2d", "-demoHomeFloor", "1"], steps: [.tap("next.home")], expect: ["home.scene"]),
            // Plan
            Entry(id: "PLAN-01", args: plan, expect: ["plan.familyCard"]),
            Entry(id: "PLAN-02", args: plan, steps: [.tap("plan.help")], expect: ["help.outageCard"]),
            Entry(id: "PLAN-03", args: plan, steps: [.tap("plan.help"), .tap("help.outageCard")], expect: ["card.page"]),
            Entry(id: "PLAN-04", args: plan, steps: [.tap("plan.addContact")], expect: ["contacts.name.", "contacts.relationship.", "contacts.phone."]),
            Entry(id: "PLAN-05", args: plan, steps: [.tap("plan.address")], expect: ["address.save"]),
            Entry(id: "PLAN-06", args: plan, steps: [.tap("plan.map")]),
            Entry(id: "PLAN-07", args: plan, steps: [.tap("plan.meetup.outsideMeetingPoint")]),
            Entry(id: "PLAN-08", args: plan, steps: [.tap("plan.share")], expect: ["share.preview"]),
            Entry(id: "PLAN-09", args: plan, steps: [.tap("plan.share"), .tap("share.preview")], expect: ["pdf.preview"]),
            Entry(id: "PLAN-10", args: plan + ["-demoPlan", "all"], steps: [.tap("plan.viewSaved")]),
            // Rehearse
            Entry(id: "REH-01", args: ["-demoTab", "rehearse"], expect: ["scenario.home-fire", "practice.open"]),
            Entry(id: "REH-02", args: ["-demoTab", "rehearse"], steps: [.tap("practice.open")], expect: ["practice.start"]),
            Entry(id: "REH-03", args: ["-demoScenario", "home-fire", "-demoAdaptive"], expect: ["adaptive.header"]),
        ]
        // Four states per hazard: REH-<hazard>-START / -DECISION / -END / -DEBRIEF.
        for hazard in hazards {
            let base = ["-demoScenario", hazard], tag = "REH-\(hazard)"
            list.append(Entry(id: "\(tag)-START", args: base + ["-demoStep", "start"], expect: ["rehearsal.step"]))
            list.append(Entry(id: "\(tag)-DECISION", args: base + ["-demoStep", "decision"], expect: ["decision.option."]))
            list.append(Entry(id: "\(tag)-END", args: base + ["-demoStep", "end"], expect: ["rehearsal.debrief"]))
            list.append(Entry(id: "\(tag)-DEBRIEF", args: base + ["-demoStep", "end"], steps: [.tap("rehearsal.debrief")], expect: ["debrief.goPrepare"]))
        }
        list += [
            // Settings
            Entry(id: "SET-01", args: prepare, steps: [.tap("app.settings")], expect: ["settings.language", "settings.done"]),
            Entry(id: "SET-02", args: prepare, steps: [.tap("app.settings")], expect: ["settings.sampleLoad"], reveal: "settings.sampleLoad"),
            Entry(id: "SET-03", args: prepare, steps: [.tap("app.settings")], reveal: "settings.delete"),
        ]
        return list
    }

    // MARK: Runs

    func testInventoryOrdinaryText() { run(size: nil, suffix: "std") }

    func testInventoryAccessibilityText() {
        run(size: "UICTContentSizeCategoryAccessibilityXXL", suffix: "axxxl")
    }

    private func run(size: String?, suffix: String) {
        let filters = env("INVENTORY_IDS")
        let locale = ProcessInfo.processInfo.environment["INVENTORY_LOCALE"].flatMap { Self.households[$0] != nil ? $0 : nil } ?? "en"
        var ran = 0
        for entry in Self.entries {
            if let filters, !filters.contains(where: { entry.id.hasPrefix($0) }) { continue }
            capture(entry, locale: locale, size: size, suffix: suffix)
            ran += 1
        }
        XCTAssertGreaterThan(ran, 0, "INVENTORY_IDS matched no entry")
    }

    // MARK: Driving

    private func capture(_ entry: Entry, locale: String, size: String?, suffix: String) {
        let app = XCUIApplication()
        var args = ["-uiTestingInMemory", "-disableAnimations", "-noBeaconConfig", "-noSavedBeacon", "-demoLocale", locale]
        if entry.household { args += ["-demoHousehold", Self.households[locale] ?? "hh-oak"] }
        args += entry.args
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args
        app.launch()
        defer { app.terminate() }
        let label = "\(entry.id)-\(suffix)-\(locale)"
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 20)

        for step in entry.steps {
            switch step {
            case .tab(let index):
                app.tabBars.buttons.element(boundBy: index).tap()
            case .tap(let id):
                guard tapElement(element(id, in: app), in: app) else { XCTFail("\(label): \(id) not reachable"); return shot(label + "-blocked", app) }
            case .tapPrefix(let prefix):
                guard tapElement(element(prefix: prefix, in: app), in: app) else { XCTFail("\(label): no \(prefix)* reachable"); return shot(label + "-blocked", app) }
            }
            settle()
        }
        for id in entry.expect {
            let target = id.hasSuffix(".") ? element(prefix: id, in: app) : element(id, in: app)
            if !reveal(target, in: app) { XCTFail("\(label): expected \(id) after the steps") }
        }
        if let id = entry.reveal { _ = reveal(element(id, in: app), in: app) }
        settle()
        shot(label, app)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func element(prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Lazy stacks add rows only near the viewport, so scroll (from the leading edge, away from rows and maps)
    /// until the element exists and is hittable.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        var found = element.waitForExistence(timeout: 15)
        for _ in 0..<14 where !(found && element.isHittable) {
            scrollUp(app)
            found = element.waitForExistence(timeout: 1)
        }
        return found
    }

    private func tapElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard reveal(element, in: app) else { return false }
        // Some controls exist before their content is ready (the debrief button until the demo reaches its end).
        let deadline = Date().addingTimeInterval(20)
        while !element.isEnabled && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        element.tap()
        return true
    }

    private func scrollUp(_ app: XCUIApplication) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.72))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.38))
        low.press(forDuration: 0.05, thenDragTo: high)
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(1.2)) }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func env(_ key: String) -> [String]? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }
}
