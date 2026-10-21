import Foundation

/// Explicit, family-started lookups of public federal planning records for the saved address: FEMA's National Flood
/// Hazard Layer (flood zone and, where FEMA publishes one, the static base flood elevation with its vertical datum) and
/// USGS 3DEP terrain elevation. Only the coordinates are sent, and only after the family agrees. Results pre-fill the
/// location-record form for review; they are never saved on their own, and nothing FEMA or USGS does not state is
/// filled in: no uncertainty, and no datum unless the record names it.
public enum OfficialSiteLookup {
    public static let femaPublisher = "FEMA National Flood Hazard Layer"
    public static let femaSourceURL = "https://msc.fema.gov/portal/home"
    public static let usgsPublisher = "USGS 3D Elevation Program"
    public static let usgsSourceURL = "https://apps.nationalmap.gov/epqs/"

    public struct FloodRecord: Sendable, Equatable {
        /// FEMA flood zone, e.g. "AE", "X". Planning context only; not a forecast or a statement about this building.
        public var zone: String
        public var subtype: String?
        /// FEMA's special flood hazard area flag, when stated.
        public var specialFloodHazardArea: Bool?
        /// Static base flood elevation in feet, only when FEMA publishes one here.
        public var baseFloodElevationFeet: Double?
        /// Vertical datum exactly as FEMA states it (e.g. "NAVD88"); nil when not stated.
        public var verticalDatum: String?
        /// FIRM database ID (county/community study), kept as the dataset version.
        public var studyID: String?
    }

    public enum FloodResult: Sendable, Equatable {
        case record(FloodRecord)
        /// No mapped flood hazard area at this point (unmapped, or outside FEMA's digital maps).
        case notMapped
        /// The point touches more than one differing zone; the family must read the map itself.
        case ambiguous
    }

    public struct TerrainElevation: Sendable, Equatable {
        public var feet: Double
        public var resolutionMeters: Double?
    }

    public enum LookupError: Error, Equatable { case invalidLocation, unreadable, serviceError }

    static func validated(latitude: Double, longitude: Double) throws -> (Double, Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0) else { throw LookupError.invalidLocation }
        return (latitude, longitude)
    }

    public static func floodQueryURL(latitude: Double, longitude: Double) throws -> URL {
        let (lat, lon) = try validated(latitude: latitude, longitude: longitude)
        var c = URLComponents(string: "https://hazards.fema.gov/arcgis/rest/services/public/NFHL/MapServer/28/query")!
        c.queryItems = [
            .init(name: "geometry", value: "{\"x\":\(lon),\"y\":\(lat)}"), .init(name: "geometryType", value: "esriGeometryPoint"),
            .init(name: "inSR", value: "4326"), .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
            .init(name: "outFields", value: "DFIRM_ID,FLD_ZONE,ZONE_SUBTY,SFHA_TF,STATIC_BFE,V_DATUM,LEN_UNIT"),
            .init(name: "returnGeometry", value: "false"), .init(name: "f", value: "json"),
        ]
        guard let url = c.url else { throw LookupError.invalidLocation }
        return url
    }

    public static func elevationQueryURL(latitude: Double, longitude: Double) throws -> URL {
        let (lat, lon) = try validated(latitude: latitude, longitude: longitude)
        var c = URLComponents(string: "https://epqs.nationalmap.gov/v1/json")!
        c.queryItems = [.init(name: "x", value: "\(lon)"), .init(name: "y", value: "\(lat)"), .init(name: "wkid", value: "4326"),
                        .init(name: "units", value: "Feet"), .init(name: "includeDate", value: "false")]
        guard let url = c.url else { throw LookupError.invalidLocation }
        return url
    }

    public static func parseFlood(_ data: Data) throws -> FloodResult {
        struct Attributes: Decodable {
            var DFIRM_ID: String?; var FLD_ZONE: String?; var ZONE_SUBTY: String?; var SFHA_TF: String?
            var STATIC_BFE: Double?; var V_DATUM: String?; var LEN_UNIT: String?
        }
        struct Feature: Decodable { var attributes: Attributes }
        struct Body: Decodable { var features: [Feature]?; var error: [String: AnyCodableValue]? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw LookupError.unreadable }
        guard body.error == nil, let features = body.features else { throw LookupError.serviceError }
        func text(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.count <= 80 else { return nil }
            return t
        }
        let records: [FloodRecord] = features.compactMap { f in
            let a = f.attributes
            guard let zone = text(a.FLD_ZONE) else { return nil }
            var record = FloodRecord(zone: zone, subtype: text(a.ZONE_SUBTY), specialFloodHazardArea: a.SFHA_TF.flatMap { $0 == "T" ? true : $0 == "F" ? false : nil },
                                     baseFloodElevationFeet: nil, verticalDatum: nil, studyID: text(a.DFIRM_ID))
            // FEMA uses -9999 for "no static BFE". A BFE without a stated datum or with a non-foot unit is not used.
            if let bfe = a.STATIC_BFE, bfe.isFinite, bfe > -1000, bfe < 30000, let datum = text(a.V_DATUM),
               (text(a.LEN_UNIT)?.lowercased() ?? "feet") == "feet" {
                record.baseFloodElevationFeet = bfe; record.verticalDatum = datum
            }
            return record
        }
        guard let first = records.first else { return .notMapped }
        return records.allSatisfy({ $0 == first }) ? .record(first) : .ambiguous
    }

    public static func parseElevation(_ data: Data) throws -> TerrainElevation? {
        struct Body: Decodable { var value: AnyCodableValue?; var resolution: Double? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw LookupError.unreadable }
        // USGS returns -1000000 (or a non-number) where it has no elevation.
        guard let value = body.value?.number, value.isFinite, value > -1500, value < 30000 else { return nil }
        return TerrainElevation(feet: value, resolutionMeters: body.resolution.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }
}

/// Minimal JSON scalar for service fields whose type varies (USGS `value` may be a number or a string).
public enum AnyCodableValue: Decodable, Sendable, Equatable {
    case number(Double), string(String), other
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .other }
    }
    var number: Double? {
        switch self { case .number(let d): d; case .string(let s): Double(s); case .other: nil }
    }
}
