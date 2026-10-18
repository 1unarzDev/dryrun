import Foundation

public enum SavedPlacePurpose: String, Codable, Sendable, Hashable, CaseIterable {
    case outsideMeetingPoint
    case backupMeetingPlace
    case fallbackDestination
    case exteriorHydrant
    case homeReference
}

public enum SavedPlaceProvenance: String, Codable, Sendable, Hashable {
    case userSelected
    case appleMapsSearch
    case officialDirectory
    case fixture
}

/// A private planning place. Coordinates are retained only after an explicit user save.
/// A text-only place remains useful when no coordinate is available.
public struct SavedPlace: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var homeID: String
    public var purpose: SavedPlacePurpose
    public var label: String
    public var coordinate: GeographicCoordinate?
    public var addressText: String?
    /// Household-authored directions for finding a landmark; useful without map tiles.
    public var findingInstructions: String?
    public var provenance: SavedPlaceProvenance
    public var sourceResourceID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, homeID: String, purpose: SavedPlacePurpose,
                label: String, coordinate: GeographicCoordinate? = nil, addressText: String? = nil,
                findingInstructions: String? = nil, provenance: SavedPlaceProvenance = .userSelected, sourceResourceID: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.homeID = homeID
        self.purpose = purpose
        self.label = label
        self.coordinate = coordinate
        self.addressText = addressText
        self.findingInstructions = findingInstructions
        self.provenance = provenance
        self.sourceResourceID = sourceResourceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
