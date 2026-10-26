import Foundation

/// Apple administrative names are not trusted coverage IDs. Only unchanged geographic/address facts
/// may retain an existing explicit supported selection; apartment details do not change coverage.
public enum HomeLocationChange {
    public static func regionID(previous: PrivateLocation?, updated: PrivateLocation, existingRegionID: String) -> String {
        guard PublicDataPolicy.isAllowedRegionID(existingRegionID), var previous else { return "unsupported" }
        var updated = updated
        previous.unit = nil; updated.unit = nil
        return previous == updated ? existingRegionID : "unsupported"
    }
}
