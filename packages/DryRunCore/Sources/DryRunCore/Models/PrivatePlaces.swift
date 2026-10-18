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
    public var sourceIDs: [String]?
    /// Source review date is distinct from when this household saved or edited the place.
    public var sourceCheckedAt: String?
    public var sourcePublisher: String?
    public var contactPhone: String?
    public var websiteURL: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, homeID: String, purpose: SavedPlacePurpose,
                label: String, coordinate: GeographicCoordinate? = nil, addressText: String? = nil,
                findingInstructions: String? = nil, provenance: SavedPlaceProvenance = .userSelected, sourceResourceID: String? = nil,
                sourceIDs: [String]? = nil, sourceCheckedAt: String? = nil, sourcePublisher: String? = nil, contactPhone: String? = nil, websiteURL: String? = nil,
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
        self.sourceIDs = sourceIDs
        self.sourceCheckedAt = sourceCheckedAt
        self.sourcePublisher = sourcePublisher
        self.contactPhone = contactPhone
        self.websiteURL = websiteURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Plain source adapters shared by the planner and persistence tests. Saving never implies activation.
public extension SavedPlace {
    static func officialResource(_ resource: PublicResource, homeID: String, purpose: SavedPlacePurpose = .fallbackDestination) -> Self {
        return Self(homeID: homeID, purpose: purpose, label: resource.name, coordinate: resource.planningCoordinate,
                    addressText: resource.contact.address, provenance: .officialDirectory, sourceResourceID: resource.id,
                    sourceIDs: Array(Set(resource.sourceIDs + (resource.coordinateSourceIDs ?? []))).sorted(), sourceCheckedAt: resource.checkedAt, sourcePublisher: resource.publisher,
                    contactPhone: resource.contact.phone, websiteURL: resource.contact.url)
    }

    static func appleSuggestion(sourceID: String, name: String, coordinate: GeographicCoordinate, address: String?,
                                phone: String?, website: String?, homeID: String, purpose: SavedPlacePurpose = .fallbackDestination) -> Self {
        Self(homeID: homeID, purpose: purpose, label: name, coordinate: coordinate, addressText: address,
             provenance: .appleMapsSearch, sourceResourceID: "apple:\(sourceID)", contactPhone: phone, websiteURL: website)
    }
}

public extension PublicResource {
    var planningCoordinate: GeographicCoordinate? {
        latitude.flatMap { latitude in longitude.flatMap { GeographicCoordinate(latitude: latitude, longitude: $0) } }
    }
}
