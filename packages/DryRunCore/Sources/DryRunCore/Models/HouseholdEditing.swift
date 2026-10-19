import Foundation

/// Focused destructive edits preserve unrelated household records and never invent replacement assignments.
public enum HouseholdEditing {
    public static func canRemovePerson(_ id: String, from household: HouseholdProfile) -> Bool {
        household.people.count > 1 && household.people.contains { $0.id == id && $0.isSelf != true }
    }

    @discardableResult
    public static func removePerson(_ id: String, from household: inout HouseholdProfile) -> Bool {
        guard canRemovePerson(id, from: household) else { return false }
        household.people.removeAll { $0.id == id }
        for index in household.people.indices where household.people[index].helperPersonID == id {
            household.people[index].helperPersonID = nil
        }
        // Device ownership/clinical instructions survive; the resident association needs a new explicit answer.
        for index in household.equipment.indices where household.equipment[index].personID == id {
            household.equipment[index].personID = nil
        }
        household.preparedness?.items.removeValue(forKey: "medication.person.\(id)")
        household.completedPreparations.removeAll { $0.subjectID == "person.\(id)" }
        return true
    }

    @discardableResult
    public static func removeEquipment(_ id: String, from household: inout HouseholdProfile) -> Bool {
        guard household.equipment.contains(where: { $0.id == id }) else { return false }
        household.equipment.removeAll { $0.id == id }
        household.preparedness?.items.removeValue(forKey: "equipmentSupplies.\(id)")
        household.preparedness?.items.removeValue(forKey: "medication.equipment.\(id)")
        household.completedPreparations.removeAll { $0.subjectID == "equipment.\(id)" }
        return true
    }

    /// Called by the app's transactional household save; a failed save must retain the committed home.
    /// Deleted residents lose window suitability; explicit dwelling-type edits also update the home safety context. Geometry and unrelated answers stay intact.
    public static func homeAfterRemovingResidents(previous: HouseholdProfile, updated: HouseholdProfile, home: HomeModel?) -> HomeModel? {
        let removed = Set(previous.people.map(\.id)).subtracting(updated.people.map(\.id))
        guard var home else { return home }
        var changed = false
        if previous.housing.homeType != updated.housing.homeType {
            home.dwellingType=updated.housing.homeType
            changed=true
        }
        for index in home.portals.indices {
            guard let ids = home.portals[index].emergencyEscapePersonIDs else { continue }
            let retained = ids.filter { !removed.contains($0) }
            if retained != ids {
                home.portals[index].emergencyEscapePersonIDs = retained
                changed = true
            }
        }
        if changed { home.bumpRevision() }
        return home
    }
}
