import Foundation
import Testing
@testable import DryRunCore

@Suite("Ordinary map estimate presentation")
struct PlanningMeasurementsTests {
    @Test func distanceUsesHomeUnitsAndSelectedLanguageWithoutChangingGeometry() throws {
        let es = try PlanBuilderTests.localizer("es")
        let vi = try PlanBuilderTests.localizer("vi")
        #expect(PlanningMeasurements.distance(meters: 1500, countryCode: "ES", localizer: es) == "1,5 km")
        #expect(PlanningMeasurements.distance(meters: 1500, countryCode: "VN", localizer: vi) == "1,5 km")
        #expect(PlanningMeasurements.distance(meters: 1609.344, countryCode: "us", localizer: es) == "1 mi")
        #expect(PlanningMeasurements.distance(meters: 30.48, countryCode: "US", localizer: es) == "100 pies")
        #expect(PlanningMeasurements.distance(meters: 1609.344, countryCode: "GB", localizer: vi) == "1 mi")
        #expect(PlanningMeasurements.distance(meters: 500, countryCode: nil, localizer: vi) == "500 m")
        #expect(PlanningMeasurements.duration(seconds: 61, localizer: vi) == "Khoảng 2 phút")
        #expect(PlanningMeasurements.duration(seconds: 60, localizer: es) == "Aprox. 1 min")
    }

    @Test func invalidEstimatesStayUnknownRatherThanDisplayingNaNOrNegativeTravel() throws {
        for code in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(code)
            for invalid in [-1, Double.nan, Double.infinity] {
                #expect(PlanningMeasurements.distance(meters: invalid, countryCode: "US", localizer: l) == l("common.status.unknown"))
                #expect(PlanningMeasurements.duration(seconds: invalid, localizer: l) == l("common.status.unknown"))
            }
        }
    }

    @Test("Water presentation agrees across recommendations, authored events and full plans without rewriting facts")
    func waterPresentationAcrossTheJourney() throws {
        var h = SampleHouseholds.oak
        h.supplies.storedWaterGallons = .confirmed(1)
        h.privateLocation = .init(countryCode: "VN")
        let event = SimulationEvent(id: "water", simMinute: 60, phaseID: "exercise",
                                    titleKey: "scenario.common.checkpoint.water-target",
                                    templateValues: ["people": "4", "target": "12", "stored": "1", "initial": "1"],
                                    evidence: .init(ruleID: "rule.resource.water-storage-target"))
        let raw = event.templateValues
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let target = PlanningMeasurements.water(gallons: 12, countryCode: "VN", localizer: l)
            let stored = PlanningMeasurements.water(gallons: 1, countryCode: "VN", localizer: l)
            let values = event.localizedTemplateValues(household: h, localizer: l)
            #expect(values["target"] == target && values["stored"] == stored && values["initial"] == stored)
            let text = l(event.titleKey, values)
            #expect(text.contains(target) && text.contains(stored) && !text.contains("gallon") && !text.contains("galones"))
            let unknown = SimulationEvent(id: "unknown", simMinute: 0, phaseID: "exercise", titleKey: "scenario.common.recovery.water-not-refilled",
                                          templateValues: ["stored": "unknown"], evidence: .init(ruleID: "test"))
            #expect(unknown.localizedTemplateValues(household: h, localizer: l)["stored"] == l("common.status.unknown"))
            let baseline = BaselinePreparedness.evaluate(household: h, home: nil, savedPlaces: [], referenceDate: LeadTestSupport.fixedDate)
            let water = try #require(baseline.first { $0.actionID == "prep.water" })
            #expect(l(water.whyKey, water.localizedTemplateValues(household: h, localizer: l)).contains(target))
            let doc = PlanBuilder.build(household: h, home: nil, results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
            let planLine = try #require(doc.pages.flatMap(\.sections).flatMap(\.lines).first { $0.key == "plan.water.target" })
            #expect(planLine.text.contains(target) && planLine.text.contains(stored) && planLine.unfilledPlaceholders.isEmpty)
            #expect(PlanningMeasurements.water(gallons: 1, countryCode: "us", localizer: l) == l("spatial.quantity.gallons.one", ["number": "1"]))
            #expect(PlanningMeasurements.water(gallons: 1, countryCode: nil, localizer: l) == stored)
            for invalid in [-1, Double.nan, Double.infinity] {
                #expect(PlanningMeasurements.water(gallons: invalid, countryCode: "US", localizer: l) == l("common.status.unknown"))
            }
        }
        #expect(event.templateValues == raw && h.supplies.storedWaterGallons.confirmedValue == 1)
    }


    @Test("Rehearsal event subjects use exact evidence IDs, localized defaults and recorded custom names")
    func eventSubjectsAndRouteReasons() throws {
        var h = SampleHouseholds.oak
        h.people = [Person(id: "resident", alias: "Wrong person", ageBand: .unknown), Person(id: "resident.self", alias: "", ageBand: .unknown, isSelf: true), Person(id: "helper", alias: "USER-HELPER", ageBand: .unknown)]
        h.people[1].helperPersonID = "helper"
        h.equipment = [PoweredEquipment(id: "eq", purpose: .other, label: "Wrong device"), PoweredEquipment(id: "eq.runtime", purpose: .oxygenConcentrator, label: "")]
        h.backupPower = [BackupPowerSource(id: "battery", kind: .portableBatteryStation, label: "Wrong backup"), BackupPowerSource(id: "battery.setup", kind: .portableBatteryStation, label: "")]
        let event = SimulationEvent(id: "subject", simMinute: 0, phaseID: "exercise", titleKey: "service.device.on-backup",
                                    templateValues: ["device": "", "backup": "", "person": "", "helper": "USER-HELPER", "reason": "blockedByScenario"],
                                    evidence: .init(ruleID: "test", factIDs: ["equipment.eq.runtime.documentedBackupRuntimeHours", "backup.battery.setup.setupConfirmed", "person.resident.self.helperPersonID"]))
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let values = event.localizedTemplateValues(household: h, localizer: l)
            #expect(values["device"] == h.equipment[1].localizedLabel(l))
            #expect(values["backup"] == h.backupPower[1].localizedLabel(l))
            #expect(values["person"] == l("family.you") && values["helper"] == "USER-HELPER")
            #expect(values["reason"] == l("reason.blockedByScenario"))
            #expect(!values.values.contains { $0.hasPrefix("family.") || $0.hasPrefix("card.") || $0.hasPrefix("enum.") })
            var custom = h; custom.equipment[1].label = "USER-MODEL 2.5"; custom.backupPower[1].label = "USER-BATTERY"
            let customValues = event.localizedTemplateValues(household: custom, localizer: l)
            #expect(customValues["device"] == "USER-MODEL 2.5" && customValues["backup"] == "USER-BATTERY")
            #expect(event.localizedTemplateValues(household: nil, localizer: l).values.allSatisfy { !$0.isEmpty })
        }
        #expect(event.templateValues["device"] == "" && h.equipment[1].label == "")
    }

}
