import Foundation
import Testing
@testable import DryRunCore

@Suite("Focused household deletion")
struct HouseholdEditingTests {
    private func household() -> HouseholdProfile {
        var household = SampleHouseholds.oak
        household.people = [
            Person(id: "self", alias: "Recorded self", ageBand: .unknown, helperPersonID: "removed", isSelf: true),
            Person(id: "removed", alias: "Accidental resident", ageBand: .unknown),
            Person(id: "remaining", alias: "Other resident", ageBand: .unknown, helperPersonID: "self")
        ]
        household.equipment = [
            PoweredEquipment(id: "device", purpose: .oxygenConcentrator, label: "Keep device", personID: "removed", carePlanNotes: "Recorded instructions"),
            PoweredEquipment(id: "other-device", purpose: .communicationDevice, label: "Other device", personID: "self")
        ]
        household.preparedness = .init(items: [
            "medication.person.removed": .init(location: "Removed resident's bag"),
            "medication.person.self": .init(location: "Self bag"),
            "equipmentSupplies.device": .init(location: "Device supplies"),
            "medication.equipment.device": .init(location: "Item bag"),
            "equipmentSupplies.other-device": .init(location: "Other device supplies")
        ])
        household.completedPreparations = [
            .init(actionID: "act.assist.assign-helper", completedAt: LeadTestSupport.fixedDate, subjectID: "person.removed"),
            .init(actionID: "act.backup.confirm-medical-backup", completedAt: LeadTestSupport.fixedDate, subjectID: "equipment.device"),
            .init(actionID: "act.assist.assign-helper", completedAt: LeadTestSupport.fixedDate, subjectID: "person.self")
        ]
        return household
    }

    @Test("Removing an accidental resident clears only their references and preserves equipment and the identifiable self")
    func removeResident() throws {
        var updated = household()
        let original = updated
        #expect(HouseholdEditing.removePerson("removed", from: &updated))
        #expect(updated.people.map(\.id) == ["self", "remaining"])
        #expect(updated.people[0].isSelf == true && updated.people[0].alias == "Recorded self")
        #expect(updated.people[0].helperPersonID == nil && updated.people[1].helperPersonID == "self")
        var expectedDevice = original.equipment[0]; expectedDevice.personID = nil
        #expect(updated.equipment == [expectedDevice, original.equipment[1]])
        #expect(updated.preparedness?.items["medication.person.removed"] == nil)
        #expect(updated.preparedness?.items["medication.person.self"] == original.preparedness?.items["medication.person.self"])
        #expect(updated.preparedness?.items["equipmentSupplies.device"] != nil)
        #expect(!updated.completedPreparations.contains { $0.subjectID == "person.removed" })
        #expect(updated.completedPreparations.contains { $0.subjectID == "person.self" })
        #expect(updated.backupPower == original.backupPower && updated.contacts == original.contacts && updated.transport == original.transport)
        #expect(updated.homeID == original.homeID && updated.privateLocation == original.privateLocation)
        #expect(try JSONDecoder().decode(HouseholdProfile.self, from: JSONEncoder().encode(updated)) == updated)
    }

    @Test("Self and the last legacy resident cannot be deleted; failed or missing deletions leave the draft intact")
    func protectSelfAndLastResident() {
        var updated = household(); let original = updated
        #expect(!HouseholdEditing.canRemovePerson("self", from: updated))
        #expect(!HouseholdEditing.removePerson("self", from: &updated))
        #expect(!HouseholdEditing.removePerson("unknown", from: &updated))
        #expect(updated == original)
        updated.people = [Person(id: "legacy", alias: "Recorded resident", ageBand: .unknown)]
        let single = updated
        #expect(!HouseholdEditing.removePerson("legacy", from: &updated))
        #expect(updated == single)
    }

    @Test("Removing equipment clears exact item evidence without deleting shared sources or unrelated people and facts")
    func removeEquipment() {
        var updated = household(); let original = updated
        #expect(HouseholdEditing.removeEquipment("device", from: &updated))
        #expect(updated.equipment == [original.equipment[1]])
        #expect(updated.preparedness?.items["equipmentSupplies.device"] == nil)
        #expect(updated.preparedness?.items["medication.equipment.device"] == nil)
        #expect(updated.preparedness?.items["equipmentSupplies.other-device"] != nil)
        #expect(updated.preparedness?.items["medication.person.removed"] != nil)
        #expect(!updated.completedPreparations.contains { $0.subjectID == "equipment.device" })
        #expect(updated.people == original.people && updated.backupPower == original.backupPower && updated.contacts == original.contacts)
        let after = updated
        #expect(!HouseholdEditing.removeEquipment("device", from: &updated))
        #expect(updated == after)
    }

    @Test("The transactional home candidate drops only deleted residents' window suitability with one revision change")
    func windowReferences() throws {
        let original = household(); var updated = original
        var home = SampleHomes.ranch
        let index = try #require(home.portals.firstIndex { $0.kind == .window })
        home.portals[index].emergencyEscapePersonIDs = ["self", "removed", "remaining"]
        home.portals[index].emergencyEscapeConfirmed = true
        #expect(HouseholdEditing.homeAfterRemovingResidents(previous: original, updated: updated, home: home) == home)
        #expect(HouseholdEditing.removePerson("removed", from: &updated))
        let candidate = try #require(HouseholdEditing.homeAfterRemovingResidents(previous: original, updated: updated, home: home))
        #expect(candidate.portals[index].emergencyEscapePersonIDs == ["self", "remaining"])
        #expect(candidate.portals[index].emergencyEscapeConfirmed == true)
        #expect(candidate.revision == home.revision + 1)
        #expect(candidate.spaces == home.spaces && candidate.annotations == home.annotations)
        #expect(HouseholdEditing.homeAfterRemovingResidents(previous: updated, updated: updated, home: candidate) == candidate)
        #expect(HouseholdEditing.homeAfterRemovingResidents(previous: original, updated: updated, home: nil) == nil)
    }

    @Test("Destructive explanations resolve in EN, ES and VI with exact subject names")
    func localizedConfirmations() throws {
        let keys = ["native.removePerson", "native.removePersonConfirm", "native.removePersonNote", "native.removeEquipment", "native.removeEquipmentConfirm", "native.removeEquipmentNote"]
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            for key in keys {
                let text = localizer.text(key, ["person": "PERSON-CANARY", "device": "DEVICE-CANARY"])
                #expect(!text.isMissing && !text.isFallback && text.unfilledPlaceholders.isEmpty)
            }
        }
    }
}
