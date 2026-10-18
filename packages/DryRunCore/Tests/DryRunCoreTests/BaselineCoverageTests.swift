import Foundation
import Testing
@testable import DryRunCore

@Suite("Layoutless baseline readiness coverage")
struct BaselineCoverageTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func household() -> HouseholdProfile {
        var household = SampleHouseholds.oak
        household.people = [Person(id: "self", alias: "", ageBand: .unknown, isSelf: true)]
        household.isFictional = false; household.regionID = ""
        household.equipment = []; household.backupPower = []; household.pets = []
        household.supplies = Supplies(); household.communications = Communications()
        household.preparedness = PreparednessRecord(reviewedAt: date)
        return household
    }

    static func tasks(_ household: HouseholdProfile) -> [Recommendation] {
        BaselinePreparedness.evaluate(household: household, home: nil, referenceDate: date)
    }

    @Test("Layoutless households get reception readiness without irrelevant clinical, pet, or unsupported enrollment tasks")
    func applicability() {
        var household = Self.household()
        let first = Self.tasks(household)
        #expect(first.contains { $0.actionID == "prep.radio" })
        #expect(!first.contains { ["prep.medication", "prep.equipmentSupplies", "prep.pets", "prep.alerts"].contains($0.actionID) })
        for country in ["FR", "VN", "US"] {
            household.privateLocation = PrivateLocation(countryCode: country)
            #expect(!Self.tasks(household).contains { $0.actionID == "prep.alerts" })
        }
        household.regionID = "48143"
        #expect(Self.tasks(household).contains { $0.actionID == "prep.alerts" })
        household.preparedness?.items["alerts"] = .init(available: .confirmed(true))
        #expect(Self.tasks(household).contains { $0.actionID == "prep.alerts" }, "record the enrollment channel as well as its status")
        household.preparedness?.items["alerts"]?.location = "County alert service on our phones"
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.alerts" })
    }

    @Test("Water amount and storage location are independent facts; checklist ownership never supplies a missing quantity")
    func waterQuantityAndLocation() {
        var household = Self.household()
        household.supplies.storedWaterGallons = .confirmed(3)
        let quantityOnly = Self.tasks(household).first { $0.actionID == "prep.water" }
        #expect(quantityOnly?.whyKey == "prep.location.why")
        household.preparedness?.items["water"] = .init(location: "Pantry lower shelf")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.water" })
        household.supplies.storedWaterGallons = .unknown
        household.preparedness?.items["water"]?.available = .confirmed(true)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.water" && $0.whyKey == "prep.water.why" })
        household.supplies.storedWaterGallons = .confirmed(2)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.water" })
        household.supplies.storedWaterGallons = .confirmed(3)
        household.preparedness?.items["water"]?.available = .confirmed(false)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.water" }, "conflicting records do not silently certify stored water")
    }

    @Test("Canonical supplies can establish having an item, while unknown location and conflicting ownership remain unresolved")
    func canonicalSupplies() {
        var household = Self.household()
        household.supplies.firstAidKit = .confirmed(true)
        household.supplies.flashlights = .confirmed(2)
        household.supplies.shelfStableFoodDays = .confirmed(3)
        household.communications.powerBankCharges = .confirmed(2)
        for id in ["firstAid", "flashlight", "food", "batteries"] {
            #expect(Self.tasks(household).contains { $0.actionID == "prep.\(id)" && $0.whyKey == "prep.location.why" })
            household.preparedness?.items[id] = .init(location: "Hall cabinet")
            #expect(!Self.tasks(household).contains { $0.actionID == "prep.\(id)" })
        }
        household.supplies.firstAidKit = .confirmed(false)
        household.preparedness?.items["firstAid"]?.available = .confirmed(true)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.firstAid" })
        household.supplies.firstAidKit = .unknown
        household.preparedness?.items["firstAid"]?.available = .assumed(true)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.firstAid" }, "an exercise assumption does not establish ownership")
        household.communications.powerBankCharges = .confirmed(0)
        household.preparedness?.items["batteries"] = .init(available: .confirmed(true), location: "Spare flashlight batteries in hall cabinet")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.batteries" }, "no power bank does not rule out spare batteries")
    }

    @Test("Radio ownership needs a findable location; an explicit alternate plan does not change modeled radio ownership")
    func receptionPlan() {
        var household = Self.household()
        household.communications.batteryOrCrankRadio = .confirmed(true)
        #expect(Self.tasks(household).contains { $0.actionID == "prep.radio" && $0.whyKey == "prep.location.why" })
        household.preparedness?.items["radio"] = .init(location: "Kitchen drawer")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.radio" })
        household.communications.batteryOrCrankRadio = .confirmed(false)
        household.preparedness?.items["radio"] = .init(available: .confirmed(true), location: "Agreed accessible reception arrangement with our neighbor")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.radio" })
        #expect(household.communications.batteryOrCrankRadio.confirmedValue == false)
        household.preparedness?.items["radio"] = .init(notes: "We talked about a radio")
        #expect(Self.tasks(household).contains { $0.actionID == "prep.radio" })
    }

    @Test("Pet supplies require both availability and location and only apply to actual recorded pets")
    func petEssentials() {
        var household = Self.household()
        household.pets = [Pet(id: "pet", kind: .cat)]
        household.preparedness?.items["pets"] = .init(available: .confirmed(true))
        #expect(Self.tasks(household).contains { $0.actionID == "prep.pets" && $0.whyKey == "prep.location.why" })
        household.preparedness?.items["pets"]?.location = "Pet bag in hall"
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.pets" })
        household.preparedness?.items["pets"]?.available = .unknown
        #expect(Self.tasks(household).contains { $0.actionID == "prep.pets" })
        household.pets[0].count = 0
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.pets" })
    }

    @Test("Medication availability is scoped to recorded need and independent of cold-storage and electrical evidence")
    func medicalAvailabilityAndSubjects() {
        var household = Self.household()
        household.people[0].emergencyInformation = .init(essentialMedication: "Household-recorded medicine")
        household.people.append(Person(id: "other", alias: "Other", ageBand: .unknown))
        household.equipment = [PoweredEquipment(id: "cold", purpose: .refrigeratedMedication, label: "", personID: "self",
            storageInstructions: "Provider-supplied instructions", storagePlanConfirmed: .confirmed(true))]
        var medications = Self.tasks(household).filter { $0.actionID == "prep.medication" }
        #expect(medications.count == 1 && medications.first?.subjectID == "person.self")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.equipmentSupplies" || $0.actionID == "prep.medicalBackup" || $0.actionID == "prep.coldStorage" })
        household.preparedness?.items["medication.person.self"] = .init(available: .confirmed(true), location: "Medicine bag")
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.medication" })
        household.equipment[0].storagePlanConfirmed = .unknown
        #expect(Self.tasks(household).contains { $0.actionID == "prep.coldStorage" })
        household.people[1].emergencyInformation = .init(essentialMedication: "Another recorded medicine")
        medications = Self.tasks(household).filter { $0.actionID == "prep.medication" }
        #expect(medications.count == 1 && medications.first?.subjectID == "person.other")
        household.preparedness?.items["medication.person.other"] = .init(available: .confirmed(false))
        #expect(Self.tasks(household).contains { $0.actionID == "prep.medication" && $0.subjectID == "person.other" && $0.tier == .unmetEssentialRequirement })
    }

    @Test("Equipment supplies and unassigned medicines keep exact subject keys and cannot be completed by another device")
    func equipmentSuppliesAndUnassignedMedicine() {
        var household = Self.household()
        household.equipment = [PoweredEquipment(id: "device.one", purpose: .oxygenConcentrator, label: ""),
                               PoweredEquipment(id: "device.two", purpose: .oxygenConcentrator, label: ""),
                               PoweredEquipment(id: "medicine", purpose: .refrigeratedMedication, label: "")]
        var tasks = Self.tasks(household)
        #expect(tasks.filter { $0.actionID == "prep.equipmentSupplies" }.count == 2)
        #expect(tasks.contains { $0.actionID == "prep.medication" && $0.subjectID == "equipment.medicine" && $0.templateValues["item"] == "medication.equipment.medicine" })
        household.preparedness?.items["equipmentSupplies.device.one"] = .init(available: .confirmed(true), location: "Device one supply bag")
        household.preparedness?.items["medication.equipment.medicine"] = .init(available: .confirmed(true), location: "Medicine bag")
        tasks = Self.tasks(household)
        #expect(tasks.filter { $0.actionID == "prep.equipmentSupplies" }.map(\.subjectID) == ["equipment.device.two"])
        #expect(!tasks.contains { $0.actionID == "prep.medication" })
        household.equipment[1].isEssential = false
        #expect(!Self.tasks(household).contains { $0.actionID == "prep.equipmentSupplies" })
    }

    @Test("Baseline subjects and missing-location explanations resolve in every supported language without leaking record IDs")
    func localizedSubjectsAndLocations() throws {
        var household = Self.household()
        household.regionID = "48143"
        household.people[0].alias = "PERSON-CANARY"
        household.people[0].emergencyInformation = .init(essentialMedication: "Recorded medicine")
        household.supplies.storedWaterGallons = .confirmed(3)
        household.equipment = [PoweredEquipment(id: "supply.device", purpose: .oxygenConcentrator, label: "CUSTOM-DEVICE-CANARY"),
                               PoweredEquipment(id: "unassigned.med", purpose: .refrigeratedMedication, label: "")]
        for id in ["radio", "medication.person.self", "medication.equipment.unassigned.med", "equipmentSupplies.supply.device"] {
            household.preparedness?.items[id] = .init(available: .confirmed(true))
        }
        let tasks = Self.tasks(household).filter { ["prep.water", "prep.radio", "prep.medication", "prep.equipmentSupplies", "prep.alerts"].contains($0.actionID) }
        #expect(tasks.filter { $0.actionID == "prep.medication" }.count == 2)
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            for task in tasks {
                let values = task.localizedTemplateValues(household: household, localizer: localizer)
                for key in [task.titleKey, task.whyKey] {
                    let text = localizer.text(key, values)
                    #expect(!text.isMissing && !text.isFallback && text.unfilledPlaceholders.isEmpty, "\(locale):\(key)")
                }
                if task.templateValues["item"] != nil {
                    #expect(values["item"] != task.templateValues["item"])
                    #expect(!(values["item"]?.contains("prep.") ?? true))
                }
                if task.subjectID == "person.self" { #expect(values["person"] == "PERSON-CANARY") }
                if task.subjectID == "equipment.supply.device" { #expect(values["device"] == "CUSTOM-DEVICE-CANARY") }
                if task.subjectID == "equipment.unassigned.med" {
                    #expect(values["person"] == household.equipment[1].localizedLabel(localizer))
                }
            }
        }
    }

    @Test("Recorded reception and enrollment close equivalent derived tasks without changing hypothetical service outcomes")
    func derivedMerging() throws {
        var household = Self.household()
        household.regionID = "48143"
        var result = try SimFixtures.run(household, "tornado")
        // Exercise reception failure can persist even when a real alternate arrangement is recorded.
        let radio = Recommendation(actionID: "act.comms.weather-radio", tier: .unmetEssentialRequirement, titleKey: "", whyKey: "", matchedFactIDs: [], causeEventIDs: [], scenarioIDs: ["tornado"], tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: [], verificationStatus: .needsVerification)
        result.recommendations.append(radio)
        let missing = NextSteps.summarize([result], household: household, referenceDate: Self.date)
        #expect(missing.toDo.filter { $0.recommendation.actionID == "prep.radio" }.count == 1)
        #expect(!missing.toDo.contains { $0.recommendation.actionID == "act.comms.weather-radio" })
        household.preparedness?.items["radio"] = .init(available: .confirmed(true), location: "Recorded alternate reception plan")
        household.preparedness?.items["alerts"] = .init(available: .confirmed(true), location: "Recorded county enrollment")
        let complete = NextSteps.summarize([result], household: household, referenceDate: Self.date)
        #expect(!complete.toDo.contains { ["prep.radio", "prep.alerts", "act.comms.weather-radio", "act.alerts.enroll-local"].contains($0.recommendation.actionID) })
        household.regionID = ""
        #expect(!(try SimFixtures.run(household, "tornado")).recommendations.contains { $0.actionID == "act.alerts.enroll-local" })
        household.regionID = "48143"
        #expect(!(try SimFixtures.run(household, "tornado")).recommendations.contains { $0.actionID == "act.alerts.enroll-local" })
        #expect(Self.tasks(household) == Self.tasks(household))
    }
}
