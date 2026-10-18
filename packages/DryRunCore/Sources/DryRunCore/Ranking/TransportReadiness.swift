import Foundation

/// The same recorded access prerequisites feed preparation and exercise transport.
/// This establishes an arrangement, never road safety or present availability during an emergency.
public enum TransportReadiness {
    public static func needsAccessibleTransport(_ household: HouseholdProfile) -> Bool {
        household.people.contains { $0.needs.contains(.usesWheelchair) }
    }
    public static func vehicleAvailability(_ vehicle: Vehicle, household: HouseholdProfile) -> Bool? {
        needsAccessibleTransport(household) ? vehicle.wheelchairAccessible.confirmedValue : true
    }
    public static func alternativeAvailability(_ alternative: TransportAlternative, household: HouseholdProfile) -> Bool? {
        guard let agreed = alternative.agreed.confirmedValue else { return nil }
        return agreed && needsAccessibleTransport(household) ? alternative.wheelchairAccessible.confirmedValue : agreed
    }
    public static func hasRecordedOption(_ household: HouseholdProfile) -> Bool {
        household.transport.vehicles.contains { vehicleAvailability($0, household: household) == true }
            || household.transport.alternatives.contains { alternativeAvailability($0, household: household) == true }
    }
}
