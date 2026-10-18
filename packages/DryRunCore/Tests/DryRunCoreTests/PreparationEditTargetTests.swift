import Testing
@testable import DryRunCore

@Suite("Preparation task editor routing")
struct PreparationEditTargetTests {
    private func action(_ id: String, subject: String? = nil) -> Recommendation {
        Recommendation(actionID: id, tier: .general, titleKey: "title", whyKey: "why", matchedFactIDs: [], causeEventIDs: [], scenarioIDs: [],
            tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: [], verificationStatus: .needsVerification, subjectID: subject)
    }
    @Test func contactsMeetingPurposesAndPeopleKeepTheirIntendedContext() {
        #expect(PreparationEditTarget.resolve(action("prep.outOfAreaContact"), home: nil) == .contact(.outOfAreaContact))
        #expect(PreparationEditTarget.resolve(action("act.water.save-utility-contact"), home: nil) == .contact(.waterUtility))
        #expect(PreparationEditTarget.resolve(action("prep.backupMeetup"), home: nil) == .meeting(.backupMeetingPlace))
        #expect(PreparationEditTarget.resolve(action("act.fire.meeting-point"), home: nil) == .meeting(.outsideMeetingPoint))
        #expect(PreparationEditTarget.resolve(action("prep.helper", subject: "person.parent.one"), home: nil) == .family(personID: "parent.one"))
    }
    @Test func medicalAvailabilityOpensItsOwnRecordInsteadOfElectricalEquipment() {
        #expect(PreparationEditTarget.resolve(action("prep.medication", subject: "person.child.one"), home: nil)
            == .checklist(id: "medication.person.child.one", titleKey: "prep.medication.title"))
        #expect(PreparationEditTarget.resolve(action("prep.medication", subject: "equipment.medicine.one"), home: nil)
            == .checklist(id: "medication.equipment.medicine.one", titleKey: "prep.medication.title"))
        #expect(PreparationEditTarget.resolve(action("prep.equipmentSupplies", subject: "equipment.device.one"), home: nil)
            == .checklist(id: "equipmentSupplies.device.one", titleKey: "prep.equipmentSupplies.title"))
        #expect(PreparationEditTarget.resolve(action("prep.medicalBackup", subject: "equipment.device.one"), home: nil) == .equipment("device.one"))
    }
    @Test func factualActionsOpenFocusedInputsWithoutLayoutRequirements() {
        for id in ["prep.water", "act.water.store-3day"] { #expect(PreparationEditTarget.resolve(action(id), home: nil) == .water) }
        #expect(PreparationEditTarget.resolve(action("act.comms.power-bank"), home: nil) == .communications)
        #expect(PreparationEditTarget.resolve(action("act.heat.ask-blower"), home: nil) == .housing)
        #expect(PreparationEditTarget.resolve(action("act.alerts.enroll-local"), home: nil) == .checklist(id: "alerts", titleKey: "prep.alerts.title"))
        #expect(PreparationEditTarget.resolve(action("act.tornado.choose-shelter"), home: nil) == .homeSetup)
    }
    @Test func exactSpatialSubjectsArePreservedAndInventoryWindowsAreNotDefaultExitReviews() throws {
        let home = SampleHomes.ranch
        let room = try #require(home.spaces.first)
        #expect(PreparationEditTarget.resolve(action("act.tornado.choose-shelter", subject: "room.\(room.id)"), home: home) == .home(elementID: room.id))
        let target = PreparationEditTarget.resolve(action("act.fire.verify-second-exit"), home: home)
        if case .home(let opening) = target, let opening { #expect(home.portal(opening)?.kind != .window) }
        else { Issue.record("A home with openings should open the home editor") }
    }
}
