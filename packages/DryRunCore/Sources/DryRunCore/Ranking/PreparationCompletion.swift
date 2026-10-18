import Foundation

/// A completion applies to one subject and the recorded facts at that time. No randomized hashing.
public enum PreparationCompletion {
    public static func fingerprint(for recommendation: Recommendation, household: HouseholdProfile, home: HomeModel? = nil) -> String? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func encoded<T: Encodable>(_ value: T) -> String? { (try? encoder.encode(value))?.base64EncodedString() }
        guard let subject = recommendation.subjectID else { return nil }
        let parts = subject.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "equipment":
            guard let equipment = household.equipment.first(where: { $0.id == parts[1] }) else { return nil }
            struct EquipmentEvidence: Encodable { let equipment: PoweredEquipment; let backups: [BackupPowerSource] }
            return encoded(EquipmentEvidence(equipment: equipment, backups: household.backupPower.filter { equipment.compatibleBackupIDs.contains($0.id) }.sorted { $0.id < $1.id }))
        case "person": return household.people.first(where: { $0.id == parts[1] }).flatMap(encoded)
        case "backup": return household.backupPower.first(where: { $0.id == parts[1] }).flatMap(encoded)
        case "room": return home?.spaces.first(where: { $0.id == parts[1] }).flatMap(encoded)
        default: return nil
        }
    }
    public static func isValid(_ completion: CompletedPreparation, for recommendation: Recommendation, household: HouseholdProfile, home: HomeModel?) -> Bool {
        guard completion.taskID == recommendation.id else { return false }
        // Factual baseline work disappears only after its real records satisfy evaluation.
        guard !recommendation.actionID.hasPrefix("prep.") else { return false }
        guard recommendation.subjectID != nil else { return completion.subjectID == nil }
        guard let original = completion.factFingerprint, let current = fingerprint(for: recommendation, household: household, home: home) else { return false }
        return original == current
    }
}
