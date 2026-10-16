import Foundation

// Public (non-household) data contract. Mirrors services/public-api/src/schema.ts (Zod).
// Contract tests decode the same JSON fixtures in Swift and TypeScript. Owner: Agent C (with lead).

public enum ReviewState: String, Codable, Sendable, Hashable { case reviewed, draft, needsReview, unverified }
public enum DataClassification: String, Codable, Sendable, Hashable { case live, demo, curated, fixture }
public enum CoverageStatus: String, Codable, Sendable, Hashable { case verifiedPartial, oemOnly, notStarted, statewideOnly }
public enum ActivationState: String, Codable, Sendable, Hashable { case active, inactive, unknown, notApplicable }

public struct SourceRef: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var publisher: String
    public var title: String
    public var url: String
    public var checkedAt: String
    public var reviewState: ReviewState
    public init(id: String, publisher: String, title: String, url: String, checkedAt: String, reviewState: ReviewState) {
        self.id = id; self.publisher = publisher; self.title = title; self.url = url; self.checkedAt = checkedAt; self.reviewState = reviewState
    }
}

public struct ContactPoint: Codable, Sendable, Hashable {
    public var phone: String?
    public var phoneNote: String?
    public var url: String?
    public var address: String?
    public init(phone: String? = nil, phoneNote: String? = nil, url: String? = nil, address: String? = nil) {
        self.phone = phone; self.phoneNote = phoneNote; self.url = url; self.address = address
    }
}

/// A geographic coordinate in degrees. This is deliberately separate from the
/// indoor `Vec2` model (which is measured in metres) and from MapKit types.
/// Coordinates are accepted only when both values are finite and in range.
public struct GeographicCoordinate: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey { case latitude, longitude }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try c.decode(Double.self, forKey: .latitude)
        let longitude = try c.decode(Double.self, forKey: .longitude)
        guard let value = Self(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorruptedError(forKey: .latitude, in: c,
                                                   debugDescription: "latitude/longitude out of range or non-finite")
        }
        self = value
    }
}

public enum ResourceServiceType: String, Codable, Sendable, Hashable, CaseIterable {
    case emergencyManagement, publicHealth, waterProvider, electricUtility, transportation, assistanceLine,
         assistanceRegistry, disasterAssistance, warmingCenter, coolingCenter, shelter, alertEnrollment, other
}

public struct PublicResource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var publisher: String
    public var serviceType: ResourceServiceType
    public var jurisdiction: String
    public var regionIDs: [String]
    public var contact: ContactPoint
    public var summary: String
    /// For sites (shelters/centres): activation must come from source evidence. Unknown is not "open".
    public var activation: ActivationState
    public var latitude: Double?
    public var longitude: Double?
    /// Source IDs for the coordinate only (the service source remains in `sourceIDs`).
    /// Omitted for list-only contacts and legacy v1 records.
    public var coordinateSourceIDs: [String]?
    public var coordinateCheckedAt: String?
    public var accessibilityNote: String?
    public var petPolicy: String?
    public var sourceIDs: [String]
    public var checkedAt: String
    public var expiresAt: String?
    public var reviewState: ReviewState
    public var classification: DataClassification
}

public struct RegionInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var nwsZoneIDs: [String]
    public var nwsCountyIDs: [String]
    public var coverage: CoverageStatus
    public var coverageNote: String?
    public var inTX25: String
    /// Optional browsing context. These values frame a county; they do not
    /// represent a resource, district boundary, or alert polygon.
    public var mapCenterLatitude: Double?
    public var mapCenterLongitude: Double?
    public var mapSpanLatitude: Double?
    public var mapSpanLongitude: Double?
}

public struct RegionPack: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var contentVersion: String
    public var packID: String
    public var generatedAt: String
    public var expiresAt: String?
    public var classification: DataClassification
    public var regions: [RegionInfo]
    public var resources: [PublicResource]
    public var sources: [SourceRef]
}

/// Official alert, normalised without changing the official text.
public struct PublicAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var event: String
    public var headline: String?
    public var description: String
    public var instruction: String?
    public var severity: String
    public var areaDesc: String
    public var affectedZones: [String]
    public var sent: String
    public var effective: String?
    public var expires: String?
    public var ends: String?
    public var fetchedAt: String
    public var sourceURL: String
    public var classification: DataClassification
}

public struct AlertsEnvelope: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var regionID: String
    public var fetchedAt: String
    public var status: String
    public var alerts: [PublicAlert]
}
