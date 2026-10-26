import XCTest
import DryRunCore
@testable import DryRun

final class RehearsalNamesTests: XCTestCase {
    private func localizer(_ locale: String) throws -> Localizer {
        try ContentLibrary.load(from: ContentLocator.contentRoot()).localizer(for: locale)
    }

    func testOpaqueDottedIDsUseTheLongestExactSubjectAndPreserveCustomLabels() throws {
        var household = SampleHouseholds.oak
        household.equipment = [
            PoweredEquipment(id: "device", purpose: .oxygenConcentrator, label: "Short device"),
            PoweredEquipment(id: "device.runtime", purpose: .communicationDevice, label: "Family's device")
        ]
        household.backupPower = [
            BackupPowerSource(id: "battery", kind: .portableBatteryStation, label: "Short battery"),
            BackupPowerSource(id: "battery.setup", kind: .portableBatteryStation, label: "Family's battery")
        ]
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            XCTAssertEqual(UnknownNames.describe("equipment.device.runtime.runtime", household: household, localizer: l), l("spatial.fact.equipment.runtime", ["name": "Family's device"]))
            XCTAssertEqual(UnknownNames.describe("backup.battery.setup.setupConfirmed", household: household, localizer: l), l("spatial.fact.backup.setup", ["name": "Family's battery"]))
            XCTAssertEqual(UnknownNames.describe("equipment.device.runtime", household: household, localizer: l), "Family's device")
            XCTAssertEqual(UnknownNames.describe("equipment.deviceExtra.runtime", household: household, localizer: l), l("spatial.information-to-record"))
            XCTAssertEqual(ServiceNames.name("res.device.device.runtime.runtime", household: household, localizer: l), l("spatial.device-runtime", ["name": "Family's device"]))
        }
    }

    func testUnnamedSelfAndOtherPersonUseLocalizedLabelsWithoutExposingUnknownIDs() throws {
        var household = SampleHouseholds.oak
        household.people = [Person(id: "resident", alias: "Short person", ageBand: .unknown),
                            Person(id: "resident.self", alias: "", ageBand: .unknown, isSelf: true),
                            Person(id: "other.person", alias: "", ageBand: .unknown)]
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            XCTAssertEqual(UnknownNames.describe("person.resident.self.helperPersonID", household: household, localizer: l), l("spatial.fact.person.helper", ["name": l("family.you")]))
            XCTAssertEqual(UnknownNames.describe("person.other.person", household: household, localizer: l), l("ui.person"))
            XCTAssertEqual(UnknownNames.describe("future.fact-with-no-translation", household: household, localizer: l), l("spatial.information-to-record"))
            XCTAssertEqual(ServiceNames.name("future.service", household: household, localizer: l), l("spatial.information-to-record"))
            XCTAssertEqual(UnknownNames.describe("person.resident.self.unknownSuffix", household: household, localizer: l), l("spatial.information-to-record"))
        }
    }

    func testQuantityDisplayUsesSelectedLanguageAndCountWithoutChangingEvidenceUnits() throws {
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            for (unit, key) in [("gal", "gallons"), ("h", "hours"), ("min", "minutes"), ("charges", "charges"), ("days", "days"), ("people", "people"), ("Wh", "watt-hours"), ("L", "litres")] {
                for count in [1.0, 2.5] {
                    let number = PlanFormatting.number(count, locale: locale)
                    let expected = l("spatial.quantity.\(key).\(count == 1 ? "one" : "other")", ["number": number])
                    XCTAssertEqual(ServiceNames.quantity(count, unit: unit, localizer: l, countryCode: "US"), expected)
                    XCTAssertFalse(expected.hasPrefix("spatial."))
                }
            }
            XCTAssertEqual(ServiceNames.quantity(.nan, unit: "h", localizer: l), l("common.status.unknown"))
        }
        let spanish = try localizer("es")
        XCTAssertEqual(ServiceNames.quantity(1, unit: "gal", localizer: spanish), "3,8 L")
        XCTAssertEqual(ServiceNames.quantity(1, unit: "charges", localizer: spanish), "1 carga")
        XCTAssertEqual(ServiceNames.quantity(2, unit: "charges", localizer: spanish), "2 cargas")
        XCTAssertTrue(ServiceNames.quantity(1.5, unit: "gal", localizer: spanish, countryCode: "US").contains("1,5"))
    }
    func testExerciseTimeIsLocalizedWithSpokenPluralFormsAndNoRawClockAbbreviations() throws {
        let english = try localizer("en"), spanish = try localizer("es"), vietnamese = try localizer("vi")
        XCTAssertEqual(RehearsalPresentation.spokenTime(minutes: 61, localizer: english), "Exercise time: 1 hour, 1 minute after the scenario starts")
        XCTAssertEqual(RehearsalPresentation.spokenTime(minutes: 122, localizer: spanish), "Tiempo del ejercicio: 2 horas, 2 minutos desde el inicio del escenario")
        XCTAssertEqual(RehearsalPresentation.spokenTime(minutes: 0, localizer: vietnamese), "Thời gian diễn tập: 0 giờ, 0 phút sau khi tình huống bắt đầu")
        XCTAssertEqual(RehearsalPresentation.compactTime(minutes: 61, localizer: spanish), "+1 h 01 min")
        XCTAssertEqual(RehearsalPresentation.compactTime(minutes: 61, localizer: vietnamese), "+1 giờ 01 phút")
    }

    func testMissingStartNeverExposesAnInternalRoomIDAndComparisonsKeepTheirOrder() throws {
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            let home = SampleHomes.ranch
            XCTAssertEqual(RehearsalPresentation.startingRoom("sp-living", in: home, localizer: l), home.space("sp-living")?.label)
            XCTAssertEqual(RehearsalPresentation.startingRoom("raw.deleted.room", in: home, localizer: l), l("spatial.unknown-start-room"))
            let comparison = RehearsalPresentation.transition(name: "Family supplied name", before: "BEFORE", after: "AFTER", localizer: l)
            XCTAssertTrue(comparison.contains("Family supplied name"))
            let before = try XCTUnwrap(comparison.range(of: "BEFORE")), after = try XCTUnwrap(comparison.range(of: "AFTER"))
            XCTAssertLessThan(before.lowerBound, after.lowerBound)
            XCTAssertFalse(comparison.contains("spatial."))
        }
        let spanish = try localizer("es")
        XCTAssertEqual(RehearsalPresentation.transition(name: "Agua", before: "1 L", after: "2 L", localizer: spanish), "Agua: cambia de 1 L a 2 L")
    }

    func testAuthoredOriginAndCurrentPreparationFactsHaveUsefulLocalizedExplanations() throws {
        let household = SampleHouseholds.oak
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            for (fact, key) in [("home.fireOrigin.opaque.room", "home.fireOrigin"), ("home.portal.dotted.opening", "home.portal"), ("contacts", "contacts"), ("transport.destinations.conditions", "transport.destinations.conditions"), ("savedPlaces", "savedPlaces")] {
                let description = UnknownNames.describe(fact, household: household, localizer: l)
                XCTAssertEqual(description, l("spatial.fact." + key))
                XCTAssertNotEqual(description, l("spatial.information-to-record"))
            }
            let check = UnknownNames.describe("preparedness.smokeAlarms.checkedAt", household: household, localizer: l)
            XCTAssertEqual(check, l("spatial.fact.preparation", ["item": l("prep.smokeAlarms.title")]))
            XCTAssertFalse(check.contains("preparedness."))
        }
    }

    func testKnownScanReviewNotesLocalizeWithoutTranslatingPrivateNotesOrSDKDiagnostics() throws {
        let notes = [
            "Scan session did not finish; parts of the home may be missing.",
            "Room 12: no floor outline; using the outline of its walls. Needs measurement.",
            "Opening opaque.surface.id is near more than two rooms; confirm where it leads.",
            "Stairs detected. Choose both landings; overlapping rooms do not establish a connection.",
            "Confirm each captured floor's relation to exterior ground. The lowest captured story is not necessarily ground level.",
            "Scanned area exceeds Apple's published multiroom recommendation; check for missing or misplaced rooms.",
            "Scanned doors and openings are proposals. Confirm each connection and choose your exterior exits."
        ]
        for locale in ["en", "es", "vi"] {
            let l = try localizer(locale)
            for note in notes {
                let rendered = SpatialStrings.scanImportNote(note, localizer: l)
                XCTAssertFalse(rendered.contains("spatial."))
                XCTAssertFalse(rendered.contains("opaque.surface.id"))
                if locale != "en" { XCTAssertNotEqual(rendered, note) }
            }
            let personal = "Family supplied note: do not change {this}."
            XCTAssertEqual(SpatialStrings.scanImportNote(personal, localizer: l), personal)
            let sdk = "Tracking error from the operating system"
            XCTAssertEqual(SpatialStrings.scanImportNote(sdk, localizer: l), sdk)
            XCTAssertEqual(SpatialStrings.scanImportNote("Room X: no floor outline; using the outline of its walls. Needs measurement.", localizer: l), "Room X: no floor outline; using the outline of its walls. Needs measurement.")
        }
        XCTAssertTrue(SpatialStrings.scanImportNote(notes[1], localizer: try localizer("es")).contains("Habitación 12"))
    }

}
