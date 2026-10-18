import Foundation
import Testing
@testable import DryRunCore

@Suite("Family preparation revision")
struct FamilyPreparationRevisionTests {
    @Test func medicationStorageDoesNotBecomeElectricalEquipment() {
        let medication = PoweredEquipment(id: "med", purpose: .refrigeratedMedication, label: "", needsRefrigeration: false)
        #expect(!medication.requiresElectricalPower)
        #expect(medication.requiresColdStorage)
        var h = SampleHouseholds.oak; h.equipment = [medication]; h.backupPower = []; h.supplies.coolerAndIcePacks = .unknown
        let gaps = OutageCardBuilder.gaps(for: medication, in: h)
        #expect(!gaps.contains(.noCompatibleBackup)); #expect(!gaps.contains(.runtimeUnknown))
        let baseline = BaselinePreparedness.evaluate(household: h)
        #expect(!baseline.contains { $0.actionID == "prep.medicalBackup" })
        #expect(baseline.contains { $0.actionID == "prep.coldStorage" })
    }
    @Test func mixedRequirementsTrackPowerAndColdStorage() {
        let eq = PoweredEquipment(id: "mixed", purpose: .refrigeratedMedication, label: "", refrigeratedStorage: .confirmed(true), electricalRequirement: .confirmed(true))
        var h = SampleHouseholds.oak; h.equipment = [eq]; h.supplies.coolerAndIcePacks = .unknown
        let tasks = BaselinePreparedness.evaluate(household: h)
        #expect(tasks.contains { $0.id == "prep.medicalBackup|equipment.mixed" })
        #expect(tasks.contains { $0.id == "prep.coldStorage|equipment.mixed" })
    }
    @Test func legacyNonMedicationStorageCanBeClarifiedWithoutChangingItsPowerRequirement() throws {
        let old = PoweredEquipment(id: "legacy", purpose: .other, label: "Recorded item", needsRefrigeration: true)
        var item = try JSONDecoder().decode(PoweredEquipment.self, from: JSONEncoder().encode(old))
        #expect(item.needsRefrigeration && item.refrigeratedStorage == nil)
        #expect(item.requiresElectricalPower && item.requiresColdStorage)
        var household = SampleHouseholds.oak; household.equipment = [item]
        #expect(BaselinePreparedness.evaluate(household: household).contains { $0.actionID == "prep.coldStorage" })
        item.refrigeratedStorage = .confirmed(false)
        household.equipment = [item]
        #expect(item.requiresElectricalPower && !item.requiresColdStorage)
        #expect(!BaselinePreparedness.evaluate(household: household).contains { $0.actionID == "prep.coldStorage" })
        item.refrigeratedStorage = .unknown
        household.equipment = [item]
        #expect(BaselinePreparedness.evaluate(household: household).contains { $0.actionID == "prep.coldStorage" }, "an unresolved inherited answer still needs review")
    }
    @Test func taskSubjectsAndFingerprintsDoNotLeakAcrossDevices() {
        var h = SampleHouseholds.oak
        let first = h.equipment[0]
        var second = first; second.id = "ventilator-other-person"; second.label = "Personal model"
        h.equipment.append(second)
        let tasks = BaselinePreparedness.evaluate(household: h).filter { $0.actionID == "prep.medicalBackup" }
        #expect(tasks.count == 2); #expect(Set(tasks.map(\.id)).count == 2)
        let rec = Recommendation(actionID: "test.check", tier: .blockingUnknownFact, titleKey: "", whyKey: "", matchedFactIDs: [], causeEventIDs: [], scenarioIDs: [], tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: [], verificationStatus: .unknown, subjectID: "equipment.\(first.id)")
        let fingerprint = PreparationCompletion.fingerprint(for: rec, household: h)
        let record = CompletedPreparation(actionID: rec.actionID, completedAt: Date(), subjectID: rec.subjectID, factFingerprint: fingerprint)
        #expect(PreparationCompletion.isValid(record, for: rec, household: h, home: nil))
        h.equipment[1].label = "Changed unrelated device"
        #expect(PreparationCompletion.isValid(record, for: rec, household: h, home: nil))
        h.equipment[0].documentedBackupRuntimeHours = .confirmed(4)
        #expect(!PreparationCompletion.isValid(record, for: rec, household: h, home: nil))
        #expect(!PreparationCompletion.isValid(CompletedPreparation(actionID: rec.actionID, completedAt: Date()), for: rec, household: h, home: nil))
    }
    @Test func cardExistsWithoutMedicalEquipmentOrLayoutAndHonorsSelections() throws {
        var h = SampleHouseholds.oak; h.equipment = []; h.isFictional = false
        h.people[0].emergencyInformation = .init(severeAllergies: "Private allergy")
        let l = try PlanBuilderTests.localizer("en")
        let without = FamilyEmergencyCardBuilder.page(household: h, localizer: l)
        #expect(!without.sections.flatMap(\.lines).contains { $0.text.contains("Private allergy") })
        let with = FamilyEmergencyCardBuilder.page(household: h, localizer: l, selection: .init(includeCriticalInformation: true))
        #expect(with.sections.flatMap(\.lines).contains { $0.text.contains("Private allergy") })
        #expect(with.sections.contains { $0.id == "contacts" })
        #expect(with.sections.contains { $0.id == "outsideMeetingPoint" })
    }
    @Test func legacyLabelsAndOriginalMedicineAnswersSurviveMigration() throws {
        let old = PoweredEquipment(id: "old", purpose: .oxygenConcentrator, label: "Oxygen concentrator")
        let decoded = try JSONDecoder().decode(PoweredEquipment.self, from: JSONEncoder().encode(old))
        #expect(decoded.label.isEmpty); #expect(decoded.legacyOriginalLabel == "Oxygen concentrator")
        var custom = old; custom.label = "My Acme 2026"
        #expect(try JSONDecoder().decode(PoweredEquipment.self, from: JSONEncoder().encode(custom)).label == custom.label)
        let medication = PoweredEquipment(id: "med", purpose: .refrigeratedMedication, label: "Original medicine", needsRefrigeration: false)
        let migrated = try JSONDecoder().decode(PoweredEquipment.self, from: JSONEncoder().encode(medication))
        #expect(!migrated.needsRefrigeration); #expect(migrated.refrigeratedStorage == nil); #expect(!migrated.requiresElectricalPower)
    }
    @Test func medicineAndEquipmentCardSelectionsAreIndependent() throws {
        var h = SampleHouseholds.oak
        let personID = h.people[0].id
        h.equipment = [
            PoweredEquipment(id: "medicine", purpose: .refrigeratedMedication, label: "MEDICINE-CANARY", personID: personID),
            PoweredEquipment(id: "device", purpose: .oxygenConcentrator, label: "DEVICE-CANARY", personID: personID)
        ]
        let l = try PlanBuilderTests.localizer("en")
        func text(_ selection: FamilyCardSelection) -> String {
            FamilyEmergencyCardBuilder.page(household: h, localizer: l, selection: selection).sections.flatMap(\.lines).map(\.text).joined(separator: "\n")
        }
        let critical = text(.init(includeCriticalInformation: true))
        #expect(critical.contains("DEVICE-CANARY")); #expect(!critical.contains("MEDICINE-CANARY"))
        let medication = text(.init(includeMedication: true))
        #expect(medication.contains("MEDICINE-CANARY")); #expect(!medication.contains("DEVICE-CANARY"))
        let omitted = text(.init())
        #expect(!omitted.contains("DEVICE-CANARY") && !omitted.contains("MEDICINE-CANARY"))
    }
    @Test func namedContactWithoutPhoneIsIncompleteAndInternationalNumberIsPreserved() {
        let incomplete = HouseholdContact(id: "x", role: .outOfAreaContact, alias: "Friend")
        #expect(!incomplete.hasUsablePhone)
        let international = HouseholdContact(id: "y", role: .other, alias: "Relative", phone: "+84 28 3822 0000", relationship: "Aunt")
        #expect(international.hasUsablePhone); #expect(international.phone == "+84 28 3822 0000")
        #expect(international.telephoneURL?.absoluteString == "tel:+842838220000")
    }
    @Test func universalCardIncludesSelectedContinuityWithoutInferringSupportOrLeakingNotes() throws {
        var h = SampleHouseholds.oak
        let personID = h.people[0].id
        let helperID = h.people[1].id
        h.people[0].helperPersonID = helperID
        h.equipment = [PoweredEquipment(id: "mixed", purpose: .refrigeratedMedication, label: "MEDICINE-CONTINUITY", personID: personID,
                                        compatibleBackupIDs: ["owned"], carePlanNotes: "PRIVATE-NOTE-CANARY", refrigeratedStorage: .confirmed(true), electricalRequirement: .confirmed(true),
                                        storageInstructions: "USER-STORAGE-CANARY", storagePlanConfirmed: .confirmed(false))]
        h.backupPower = [BackupPowerSource(id: "owned", kind: .portableBatteryStation, label: "BACKUP-CANARY")]
        h.transport = Transport(alternatives: [TransportAlternative(id: "ride", kind: .friendOrFamily, contactID: h.contacts.first?.id, agreed: .confirmed(true))])
        h.preparedness = .init(items: ["firstAid": .init(available: .confirmed(true), location: "SUPPLY-LOCATION-CANARY", notes: "SUPPLY-PRIVATE-CANARY")])
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            func page(_ selection: FamilyCardSelection) -> PlanPage {
                FamilyEmergencyCardBuilder.page(household: h, localizer: l, selection: selection)
            }
            func text(_ page: PlanPage) -> String { page.sections.flatMap(\.lines).map(\.text).joined(separator: "\n") }
            let selected = page(.init(includeMedication: true, includeContacts: false))
            let selectedText = text(selected)
            #expect(selectedText.contains("USER-STORAGE-CANARY") && selectedText.contains("BACKUP-CANARY"))
            #expect(selectedText.contains(l("plan.equipment.runtimeUnknown")))
            #expect(selectedText.contains(l("card.gap.storagePlanUnconfirmed")))
            #expect(!selectedText.contains("PRIVATE-NOTE-CANARY") && !selectedText.contains("SUPPLY-PRIVATE-CANARY"))
            #expect(selectedText.contains("SUPPLY-LOCATION-CANARY"))
            #expect(!selectedText.contains("{"))
            #expect(selected.sections.firstIndex { $0.id == "continuity" }! > selected.sections.firstIndex { $0.id == "backupMeetingPlace" }!)
            #expect(selected.sections.last?.id == "review")
            let omitted = text(page(.init(includeCriticalInformation: true)))
            #expect(!omitted.contains("USER-STORAGE-CANARY") && !omitted.contains("MEDICINE-CONTINUITY") && !omitted.contains("BACKUP-CANARY"))
            var withoutEquipment = h; withoutEquipment.equipment = []
            let noEquipment = text(FamilyEmergencyCardBuilder.page(household: withoutEquipment, localizer: l))
            #expect(noEquipment.contains("SUPPLY-LOCATION-CANARY"))
            #expect(!noEquipment.contains(l("plan.equipment.runtimeUnknown")))
        }
    }
    @Test func alarmMarkerDoesNotCompleteFunctionalCheck() {
        var h = SampleHouseholds.oak
        h.preparedness = .init(items: ["smokeAlarms": .init(available: .confirmed(true), location: "Hall")])
        #expect(BaselinePreparedness.evaluate(household: h).contains { $0.actionID == "prep.smokeAlarms" })
        h.preparedness?.items["smokeAlarms"]?.checkedAt = Date()
        #expect(BaselinePreparedness.evaluate(household: h).contains { $0.actionID == "prep.smokeAlarms" }, "a functional check does not establish coverage")
        h.preparedness?.items["smokeAlarms"]?.coverageReviewed = .confirmed(true)
        #expect(!BaselinePreparedness.evaluate(household: h).contains { $0.actionID == "prep.smokeAlarms" })
    }
    @Test func maintenanceUsesRecordedDatesAndStaysBelowEssentialGaps() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var h = SampleHouseholds.oak
        h.preparedness = .init(items: [
            "smokeAlarms": .init(available: .confirmed(true), location: "Hall", checkedAt: now.addingTimeInterval(-31 * 86_400), coverageReviewed: .confirmed(true)),
            "firstAid": .init(available: .confirmed(true), location: "Cupboard", checkedAt: now.addingTimeInterval(-181 * 86_400))
        ], reviewedAt: now.addingTimeInterval(-181 * 86_400))
        let stale = BaselinePreparedness.evaluate(household: h, referenceDate: now)
        #expect(stale.contains { $0.actionID == "prep.reviewCard" && $0.tier == .general })
        #expect(stale.contains { $0.actionID == "prep.smokeAlarms" && $0.tier == .general && $0.templateValues["days"] == "30" })
        #expect(stale.contains { $0.actionID == "prep.firstAid" && $0.tier == .general })
        #expect(stale.firstIndex { $0.tier == .unmetEssentialRequirement }! < stale.firstIndex { $0.actionID == "prep.reviewCard" }!)
        #expect(stale == BaselinePreparedness.evaluate(household: h, referenceDate: now))
        h.preparedness?.reviewedAt = now
        h.preparedness?.items["smokeAlarms"]?.checkedAt = now
        h.preparedness?.items["firstAid"]?.checkedAt = now
        let fresh = BaselinePreparedness.evaluate(household: h, referenceDate: now)
        #expect(!fresh.contains { ["prep.reviewCard", "prep.smokeAlarms", "prep.firstAid"].contains($0.actionID) })
        h.preparedness?.items["smokeAlarms"]?.available = .confirmed(false)
        #expect(BaselinePreparedness.evaluate(household: h, referenceDate: now).contains { $0.actionID == "prep.smokeAlarms" && $0.tier == .unmetEssentialRequirement })
    }
    @Test func heatingFuelAloneCannotDismissCOAlarmReview() {
        var h = SampleHouseholds.oak
        h.housing.heatingFuel = .none; h.backupPower = []
        #expect(BaselinePreparedness.evaluate(household: h).contains { $0.actionID == "prep.coAlarms" })
        h.backupPower = [BackupPowerSource(id: "generator", kind: .portableGenerator, label: "")]
        #expect(BaselinePreparedness.evaluate(household: h).contains { $0.actionID == "prep.coAlarms" })
    }
}


extension FamilyPreparationRevisionTests {
    @Test("Legacy card review never becomes a joint family review")
    func cardAndJointReviewMigrateIndependently() throws {
        let cardDate = Date(timeIntervalSince1970: 1_700_000_000)
        let jointDate = cardDate.addingTimeInterval(86_400)
        let legacy = PreparednessRecord(items: ["firstAid": .init(location: "Cupboard")], reviewedAt: cardDate)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "jointlyReviewedAt")
        var restored = try JSONDecoder().decode(PreparednessRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.reviewedAt == cardDate)
        #expect(restored.jointlyReviewedAt == nil)
        #expect(restored.items == legacy.items)
        restored.jointlyReviewedAt = jointDate
        let roundTrip = try JSONDecoder().decode(PreparednessRecord.self, from: JSONEncoder().encode(restored))
        #expect(roundTrip.reviewedAt == cardDate && roundTrip.jointlyReviewedAt == jointDate)
        restored.reviewedAt = jointDate.addingTimeInterval(86_400)
        #expect(restored.jointlyReviewedAt == jointDate)
        restored.jointlyReviewedAt = nil
        #expect(restored.reviewedAt != nil)
    }

    @Test("Item changes reopen physical checks and their coverage or awareness without invalidating note edits")
    func itemEditsInvalidateOnlyDependentEvidence() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = PreparationFact(available: .confirmed(true), location: "Hall", checkedAt: date,
                                       notes: "Original note", coverageReviewed: .confirmed(true), familyAware: .confirmed(true))
        var moved = original; moved.location = "Bedroom"
        let corrected = original.applyingEdits(moved)
        #expect(corrected.location == "Bedroom")
        #expect(corrected.checkedAt == nil && corrected.coverageReviewed == nil && corrected.familyAware == nil)
        var removed = original; removed.available = .confirmed(false)
        let missing = original.applyingEdits(removed)
        #expect(missing.available.confirmedValue == false)
        #expect(missing.checkedAt == nil && missing.coverageReviewed == nil && missing.familyAware == nil)
        var noted = original; noted.notes = "New finding instructions"
        #expect(original.applyingEdits(noted) == noted)
        var restamped = original; restamped.available = .confirmed(true, verifiedAt: date.addingTimeInterval(60))
        #expect(original.applyingEdits(restamped) == restamped, "restamping the same availability is not a changed item")
        var fresh = corrected; fresh.checkedAt = date.addingTimeInterval(60); fresh.coverageReviewed = .confirmed(true)
        #expect(corrected.applyingEdits(fresh) == fresh, "a deliberate subsequent check survives once item facts are unchanged")
        var household = SampleHouseholds.oak
        household.preparedness = .init(items: ["smokeAlarms": original, "extinguisher": original])
        household.preparedness?.items["smokeAlarms"] = corrected
        let tasks = BaselinePreparedness.evaluate(household: household, referenceDate: date)
        #expect(tasks.contains { $0.actionID == "prep.smokeAlarms" })
        #expect(!tasks.contains { $0.actionID == "prep.extinguisher" }, "unrelated item remains checked")
    }

    @Test("Changing equipment type resets support evidence while retaining a genuine custom name")
    func typeChangeInvalidatesOldSupport() {
        var equipment = PoweredEquipment(id: "example", purpose: .refrigeratedMedication, label: "Family custom model",
            compatibleBackupIDs: ["old-source"], documentedBackupRuntimeHours: .confirmed(4),
            refrigeratedStorage: .confirmed(true), electricalRequirement: .confirmed(false),
            storageInstructions: "Household-recorded instructions", storagePlanConfirmed: .confirmed(true))
        equipment.changePurpose(to: .oxygenConcentrator)
        #expect(equipment.label == "Family custom model")
        #expect(equipment.requiresElectricalPower)
        #expect(!equipment.requiresColdStorage)
        #expect(equipment.compatibleBackupIDs.isEmpty)
        #expect(equipment.documentedBackupRuntimeHours.confirmedValue == nil)
        equipment.changePurpose(to: .refrigeratedMedication)
        #expect(!equipment.requiresElectricalPower)
        #expect(equipment.requiresColdStorage)
        #expect(equipment.storagePlanConfirmed == nil)
        #expect(equipment.storageInstructions == "Household-recorded instructions")
    }
}


extension FamilyPreparationRevisionTests {
    @Test("Switching backup kind retains ownership/custom name but requires fresh setup and device compatibility")
    func backupTypeChangeRequiresNewEvidence() {
        var household = SampleHouseholds.oak
        var source = BackupPowerSource(id: "source", kind: .portableBatteryStation, label: "Our custom source",
            usableEnergyWh: .confirmed(2000), continuousOutputW: .confirmed(1000), setupConfirmed: .confirmed(true))
        household.backupPower = [source]
        household.equipment[0].compatibleBackupIDs = [source.id]
        household.equipment[0].documentedBackupRuntimeHours = .confirmed(4)
        source.changeKind(to: .portableGenerator)
        household.backupPower[0] = source
        household.invalidateBackupCompatibility(for: source.id)
        #expect(source.id == "source" && source.label == "Our custom source")
        #expect(source.setupConfirmed.confirmedValue == nil)
        #expect(source.safeOutdoorPlacementConfirmed.confirmedValue == nil)
        #expect(source.usableEnergyWh.confirmedValue == nil)
        #expect(household.equipment[0].compatibleBackupIDs.isEmpty)
        #expect(household.equipment[0].documentedBackupRuntimeHours.confirmedValue == nil)
    }
}
