import Foundation
import Testing
@testable import DryRunCore

@Suite("Real preparation completion loops")
struct PreparationLoopTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static func household() -> HouseholdProfile {
        var h = SampleHouseholds.oak
        h.preparedness = .init(reviewedAt: date)
        h.contacts = []
        h.housing.waterSource = .unknown
        return h
    }
    static func baseline(_ h: HouseholdProfile, at date: Date = Self.date) -> [Recommendation] {
        BaselinePreparedness.evaluate(household: h, referenceDate: date)
    }

    @Test("A physical drill has its own dated record; an exit check or a digital exercise never supplies it")
    func physicalDrillAndMaintenance() throws {
        var h = Self.household()
        let earlier = try SimFixtures.run(h, "home-fire")
        #expect(earlier.recommendations.contains { $0.actionID == "act.fire.practice-drill" })
        #expect(h.preparedness?.items["fireDrill"] == nil)
        h.preparedness?.items["clearExits"] = .init(available: .confirmed(true), location: "Checked doors", checkedAt: Self.date)
        #expect(Self.baseline(h).contains { $0.actionID == "prep.fireDrill" })
        h.preparedness?.items["fireDrill"] = .init(available: .confirmed(true), location: "Family practiced the recorded escape plan")
        #expect((try SimFixtures.run(h, "home-fire")).recommendations.contains { $0.actionID == "act.fire.practice-drill" })
        h.preparedness?.items["fireDrill"]?.checkedAt = Self.date
        #expect(!Self.baseline(h).contains { $0.actionID == "prep.fireDrill" })
        let after = try SimFixtures.run(h, "home-fire")
        #expect(!after.recommendations.contains { $0.actionID == "act.fire.practice-drill" })
        #expect(after.routes == earlier.routes && after.snapshots == earlier.snapshots, "a drill record is not route or hazard evidence")
        let retained = NextSteps.summarize([earlier], household: h, referenceDate: Self.date)
        #expect(!retained.toDo.contains { ["prep.fireDrill", "act.fire.practice-drill"].contains($0.recommendation.actionID) })
        let later = Self.date.addingTimeInterval(180 * 86_400)
        let stale = try #require(Self.baseline(h, at: later).first { $0.actionID == "prep.fireDrill" })
        #expect(stale.tier == .general && stale.whyKey == "prep.recheck.why")
        #expect(stale.templateValues["days"] == "180")
        #expect(try SimFixtures.run(h, "home-fire") == after, "maintenance never introduces wall-clock time into deterministic rehearsals")
        h.preparedness?.items["fireDrill"]?.checkedAt = later
        #expect(!Self.baseline(h, at: later).contains { $0.actionID == "prep.fireDrill" })
    }

    @Test("Flood planning closes its preparation without certifying a route, refuge or exercise outcome")
    func floodInstructionsAreReadinessOnly() throws {
        var h = Self.household()
        let earlier = try SimFixtures.run(h, "flash-flood")
        #expect(earlier.recommendations.contains { $0.actionID == "act.flood.higher-ground-plan" })
        h.preparedness?.items["floodPlan"] = .init(available: .confirmed(true), notes: "Only a note, no plan recorded")
        #expect(Self.baseline(h).contains { $0.actionID == "prep.floodPlan" })
        h.preparedness?.items["floodPlan"]?.location = "Recorded early-action destination, official instructions and no-car arrangement"
        let after = try SimFixtures.run(h, "flash-flood")
        #expect(!after.recommendations.contains { $0.actionID == "act.flood.higher-ground-plan" })
        #expect(after.routes == earlier.routes && after.snapshots == earlier.snapshots)
        #expect(!NextSteps.summarize([earlier], household: h, referenceDate: Self.date).toDo.contains {
            ["prep.floodPlan", "act.flood.higher-ground-plan"].contains($0.recommendation.actionID)
        })
        h.preparedness?.items["floodPlan"]?.available = .assumed(true)
        #expect(Self.baseline(h).contains { $0.actionID == "prep.floodPlan" }, "an exercise assumption is not a family plan")
    }

    @Test("Well-test planning applies only to a private well and is independent from flood planning or water safety")
    func wellTestingPlanApplicability() throws {
        var h = Self.household()
        for source in [WaterSourceKind.unknown, .municipal] {
            h.housing.waterSource = source
            #expect(!Self.baseline(h).contains { $0.actionID == "prep.wellFloodPlan" })
            #expect(!(try SimFixtures.run(h, "flash-flood")).recommendations.contains { $0.actionID == "act.water.well-test-after-flood" })
        }
        h.housing.waterSource = .privateWell
        h.preparedness?.items["floodPlan"] = .init(available: .confirmed(true), location: "Flood early-action arrangements")
        let earlier = try SimFixtures.run(h, "flash-flood")
        #expect(earlier.recommendations.contains { $0.actionID == "act.water.well-test-after-flood" })
        h.preparedness?.items["wellFloodPlan"] = .init(available: .confirmed(true))
        #expect(Self.baseline(h).contains { $0.actionID == "prep.wellFloodPlan" })
        h.preparedness?.items["wellFloodPlan"]?.location = "Recorded health-department testing contact and instructions"
        let after = try SimFixtures.run(h, "flash-flood")
        #expect(!after.recommendations.contains { $0.actionID == "act.water.well-test-after-flood" })
        #expect(after.snapshots == earlier.snapshots, "knowing whom to contact never marks the water as safe")
        #expect(!NextSteps.summarize([earlier], household: h, referenceDate: Self.date).toDo.contains {
            ["prep.wellFloodPlan", "act.water.well-test-after-flood"].contains($0.recommendation.actionID)
        })
        h.housing.waterSource = .municipal
        h.preparedness?.items["wellFloodPlan"] = nil
        #expect(!NextSteps.summarize([earlier], household: h, referenceDate: Self.date).toDo.contains {
            ["prep.wellFloodPlan", "act.water.well-test-after-flood"].contains($0.recommendation.actionID)
        }, "a retained old scenario result cannot resurrect an inapplicable well task")
    }

    @Test("A named, usable water-utility contact closes only the municipal utility task")
    func utilityContactRoleAndPhone() throws {
        var h = Self.household()
        h.housing.waterSource = .municipal
        let earlier = try SimFixtures.run(h, "water-outage")
        #expect(Self.baseline(h).contains { $0.actionID == "prep.waterUtility" })
        #expect(earlier.recommendations.contains { $0.actionID == "act.water.save-utility-contact" })
        h.contacts = [.init(id: "friend", role: .other, alias: "Friend", phone: "+84 28 3822 0000")]
        #expect(Self.baseline(h).contains { $0.actionID == "prep.waterUtility" })
        h.contacts.append(.init(id: "utility", role: .waterUtility, alias: "Water service"))
        #expect((try SimFixtures.run(h, "water-outage")).recommendations.contains { $0.actionID == "act.water.save-utility-contact" })
        h.contacts[1].phone = "+84 28 3822 0000"
        #expect(!Self.baseline(h).contains { $0.actionID == "prep.waterUtility" })
        var utilityOnly = h; utilityOnly.contacts.removeFirst()
        #expect(Self.baseline(utilityOnly).contains { $0.actionID == "prep.contact" }, "a utility number does not supply a family emergency contact")
        #expect(!(try SimFixtures.run(h, "water-outage")).recommendations.contains { $0.actionID == "act.water.save-utility-contact" })
        #expect(!NextSteps.summarize([earlier], household: h, referenceDate: Self.date).toDo.contains {
            ["prep.waterUtility", "act.water.save-utility-contact"].contains($0.recommendation.actionID)
        })
        h.contacts[1].alias = "   "
        #expect(Self.baseline(h).contains { $0.actionID == "prep.waterUtility" })
        for source in [WaterSourceKind.unknown, .privateWell] {
            h.housing.waterSource = source
            #expect(!Self.baseline(h).contains { $0.actionID == "prep.waterUtility" })
            #expect(!(try SimFixtures.run(h, "water-outage")).recommendations.contains { $0.actionID == "act.water.save-utility-contact" })
        }
    }

    @Test("Current unfinished records merge to one focused preparation per action, including retained exercise results")
    func pendingTaskEquivalentsAndLocales() throws {
        var h = Self.household()
        h.housing.waterSource = .municipal
        let results = try ["home-fire", "flash-flood", "water-outage"].map { try SimFixtures.run(h, $0) }
        let summary = NextSteps.summarize(results, household: h, referenceDate: Self.date)
        let expected = ["prep.fireDrill", "prep.floodPlan", "prep.waterUtility"]
        for id in expected { #expect(summary.toDo.filter { $0.recommendation.actionID == id }.count == 1) }
        #expect(!summary.toDo.contains { ["act.fire.practice-drill", "act.flood.higher-ground-plan", "act.water.save-utility-contact"].contains($0.recommendation.actionID) })
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            for key in ["prep.fireDrill.title", "prep.fireDrill.why", "prep.wellFloodPlan.title", "prep.wellFloodPlan.why", "prep.waterUtility.title", "prep.waterUtility.why", "ui.contact.role.waterUtility"] {
                let text = l.text(key)
                #expect(!text.isMissing && !text.isFallback && text.unfilledPlaceholders.isEmpty, "\(locale):\(key)")
            }
        }
    }

    @Test("Adding the utility role preserves legacy contacts and international values on round trip")
    func contactRoleCompatibility() throws {
        let legacy = """
        [{"id":"existing","role":"utilityMedicalRegistry","alias":"Recorded registry","phone":"+1 (254) 555-0100"}]
        """
        var contacts = try JSONDecoder().decode([HouseholdContact].self, from: Data(legacy.utf8))
        #expect(contacts[0].role == .utilityMedicalRegistry && contacts[0].phone == "+1 (254) 555-0100")
        contacts.append(.init(id: "new", role: .waterUtility, alias: "Water service", phone: "+84 28 3822 0000"))
        let decoded = try JSONDecoder().decode([HouseholdContact].self, from: JSONEncoder().encode(contacts))
        #expect(decoded == contacts)
        #expect(decoded[1].telephoneURL?.absoluteString == "tel:+842838220000")
    }
}
