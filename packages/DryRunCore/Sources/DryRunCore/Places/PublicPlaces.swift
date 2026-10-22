import Foundation

/// Public shelters and cooling/warming centers for the "where to go" map. Every fact carries its source; an
/// accessibility note exists only when the source states it, and no place is ever described as having backup power.
public struct PublicPlace: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable { case openShelter, coolingCenter, warmingCenter }
    /// A source-stated fact, e.g. ("wheelchairAccessible", true) from FEMA's wheelchair_accessible field.
    public struct Stated: Codable, Sendable, Hashable { public var fact: String; public var value: Bool }

    public var id: String
    public var name: String
    public var kind: Kind
    public var address: String
    public var latitude: Double?
    public var longitude: Double?
    public var phone: String?
    public var source: String
    public var sourceURL: String?
    public var retrievedAt: String
    public var stated: [Stated]
    /// FEMA's pet accommodation text as published (shown verbatim with its source), when it says anything.
    public var petsAsPublished: String?
    public var role: String?
}

public enum PublicPlaces {
    private struct Curated: Decodable {
        struct Place: Decodable {
            let id: String; let name: String; let kind: PublicPlace.Kind; let address: String; let phone: String?
            let source: String; let sourceURL: String?; let role: String?
            /// Source-stated accessibility facts only (e.g. {"wheelchairAccessible": true}); null when the page says nothing.
            let accessibility: [String: Bool]?
        }
        let retrievedAt: String
        let places: [Place]
    }

    public static func curated(_ data: Data) throws -> [PublicPlace] {
        let file = try JSONDecoder().decode(Curated.self, from: data)
        return file.places.map {
            PublicPlace(id: $0.id, name: $0.name, kind: $0.kind, address: $0.address, latitude: nil, longitude: nil, phone: $0.phone,
                        source: $0.source, sourceURL: $0.sourceURL, retrievedAt: file.retrievedAt,
                        stated: ($0.accessibility ?? [:]).sorted { $0.key < $1.key }.map { PublicPlace.Stated(fact: $0.key, value: $0.value) },
                        petsAsPublished: nil, role: $0.role)
        }
    }

    private struct Fema: Decodable {
        struct Feature: Decodable { let attributes: [String: FemaValue] }
        let features: [Feature]
    }
    private enum FemaValue: Decodable {
        case text(String), number(Double), none
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else { self = .none }
        }
        var text: String? { if case .text(let s) = self { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }; return nil }
        var number: Double? { if case .number(let d) = self { return d }; return nil }
    }

    /// FEMA ESF6-SS Open Shelters (gis.fema.gov NSS/OpenShelters layer 0) query JSON; only OPEN shelters are kept.
    public static func femaShelters(_ data: Data, retrievedAt: String) throws -> [PublicPlace] {
        try JSONDecoder().decode(Fema.self, from: data).features.compactMap { feature in
            let a = feature.attributes
            guard a["shelter_status"]?.text?.uppercased() == "OPEN", let name = a["shelter_name"]?.text else { return nil }
            let id = a["shelter_id"]?.text ?? a["shelter_id"]?.number.map { String(Int($0)) } ?? name
            let address = [a["address"]?.text, a["city"]?.text, a["state"]?.text, a["zip"]?.text].compactMap { $0 }.joined(separator: ", ")
            var stated: [PublicPlace.Stated] = []
            for (field, fact) in [("wheelchair_accessible", "wheelchairAccessible"), ("ada_compliant", "adaCompliant")] {
                switch a[field]?.text?.uppercased() {
                case "YES", "Y": stated.append(.init(fact: fact, value: true))
                case "NO", "N": stated.append(.init(fact: fact, value: false))
                default: break
                }
            }
            let pets = a["pet_accommodations_code"]?.text.flatMap { ["UNK", "UNKNOWN"].contains($0.uppercased()) ? nil : $0 }
            return PublicPlace(id: "fema-\(id)", name: name, kind: .openShelter, address: address,
                               latitude: a["latitude"]?.number, longitude: a["longitude"]?.number, phone: nil,
                               source: "FEMA Open Shelters (ESF6-SS, American Red Cross data)",
                               sourceURL: "https://gis.fema.gov/arcgis/rest/services/NSS/OpenShelters/FeatureServer/0",
                               retrievedAt: retrievedAt, stated: stated, petsAsPublished: pets, role: nil)
        }
    }

    /// What to ask before going, from this household's records (deterministic; Beacon may only rephrase).
    public static func householdNotes(_ household: HouseholdProfile) -> [AlertResponse.Step] {
        var notes: [AlertResponse.Step] = []
        for equipment in household.equipment where equipment.isEssential {
            let person = equipment.personID.flatMap { id in household.people.first { $0.id == id } }
            if equipment.requiresElectricalPower {
                notes.append(.init(key: person == nil ? "power" : "power-person",
                                   values: ["equipment": .equipment(equipment.id)].merging(person.map { ["person": .person($0.id)] } ?? [:]) { a, _ in a },
                                   sourceIDs: ["S25"]))
            }
            if equipment.requiresColdStorage {
                notes.append(.init(key: "cold", values: ["equipment": .equipment(equipment.id)], sourceIDs: ["S25"]))
            }
        }
        if let person = household.people.first(where: \.requiresStepFreeRoute) {
            notes.append(.init(key: "step-free", values: ["person": .person(person.id)], sourceIDs: []))
        }
        if !household.pets.isEmpty { notes.append(.init(key: "pets", values: [:], sourceIDs: [])) }
        return notes
    }

    /// Places within `kilometers` of the origin, nearest first; places without coordinates are kept at the end.
    public static func near(_ places: [PublicPlace], latitude: Double, longitude: Double, kilometers: Double) -> [PublicPlace] {
        func distance(_ p: PublicPlace) -> Double? {
            guard let lat = p.latitude, let lon = p.longitude else { return nil }
            let r = 6371.0, dLat = (lat - latitude) * .pi / 180, dLon = (lon - longitude) * .pi / 180
            let h = sin(dLat / 2) * sin(dLat / 2) + cos(latitude * .pi / 180) * cos(lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
            return 2 * r * asin(min(1, sqrt(h)))
        }
        let located = places.compactMap { p in distance(p).map { (p, $0) } }.filter { $0.1 <= kilometers }.sorted { $0.1 < $1.1 }.map(\.0)
        return located + places.filter { $0.latitude == nil || $0.longitude == nil }
    }
}
