import Foundation

/// Ordinary advance-planning searches, never evidence of stock, activation or
/// disaster-safe travel. Supply ownership changes discovery instead of causing
/// repeated purchase suggestions for an already recorded extinguisher.
public enum MapDiscoveryNeeds {
    public static func queries(for household: HouseholdProfile?) -> [String] {
        var queries = ["hospital", "pharmacy", "grocery"]
        guard let household else { return queries }
        if household.preparedness?.items["extinguisher"]?.available.confirmedValue != true {
            queries.append("hardware store")
        }
        return queries
    }
}
