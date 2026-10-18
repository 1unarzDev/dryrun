import Foundation

/// Recorded planning prerequisites, not a clinical interruption window or a prediction of runtime.
/// Uses the same initial allocation as the exercise, including other loads sharing the source.
public enum MedicalBackupReadiness {
    public static func assignment(for equipment: PoweredEquipment, in household: HouseholdProfile) -> BackupAssignment? {
        guard equipment.requiresElectricalPower else { return nil }
        let energy = Dictionary(uniqueKeysWithValues: household.backupPower.map { ($0.id, $0.usableEnergyWh.confirmedValue) })
        return BackupAllocator().allocate(household: household, gridAvailable: false, energyRemaining: energy)
            .assignments[Load.equipment(equipment.id)]
    }

    public static func hasRecordedRuntime(_ equipment: PoweredEquipment) -> Bool {
        equipment.documentedBackupRuntimeHours.confirmedValue.map { $0.isFinite && $0 > 0 } == true
    }

    public static func isReady(_ equipment: PoweredEquipment, in household: HouseholdProfile) -> Bool {
        !equipment.requiresElectricalPower || (assignment(for: equipment, in: household)?.state == .operational && hasRecordedRuntime(equipment))
    }
}
