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
            for (unit, key) in [("gal", "gallons"), ("h", "hours"), ("charges", "charges"), ("days", "days"), ("people", "people"), ("Wh", "watt-hours"), ("L", "litres")] {
                for count in [1.0, 2.5] {
                    let number = PlanFormatting.number(count, locale: locale)
                    let expected = l("spatial.quantity.\(key).\(count == 1 ? "one" : "other")", ["number": number])
                    XCTAssertEqual(ServiceNames.quantity(count, unit: unit, localizer: l), expected)
                    XCTAssertFalse(expected.hasPrefix("spatial."))
                }
            }
            XCTAssertEqual(ServiceNames.quantity(.nan, unit: "h", localizer: l), l("common.status.unknown"))
        }
        let spanish = try localizer("es")
        XCTAssertEqual(ServiceNames.quantity(1, unit: "charges", localizer: spanish), "1 carga")
        XCTAssertEqual(ServiceNames.quantity(2, unit: "charges", localizer: spanish), "2 cargas")
        XCTAssertTrue(ServiceNames.quantity(1.5, unit: "gal", localizer: spanish).contains("1,5"))
    }
}
