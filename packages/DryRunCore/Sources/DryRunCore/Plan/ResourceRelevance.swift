import Foundation

/// Ordinary-conditions access to a destination: straight-line distance from the household origin and the
/// travel modes this household can plan with. Never a statement about roads, closures or step-free routing.
public struct OrdinaryAccess: Sendable, Hashable {
    public let straightLineMeters: Double?
    /// "walking", "transit", "driving": driving only when a household vehicle is recorded.
    public let plannableModes: [String]
    /// The radius the household's recorded transport makes an ordinary trip (walk 3 km without a car, 15 km by car).
    public let ordinaryRangeMeters: Double
    /// Nil when the distance is unknown.
    public var withinOrdinaryRange: Bool? { straightLineMeters.map { $0 <= ordinaryRangeMeters } }

    public static func of(destination: GeographicCoordinate?, origin: GeographicCoordinate?, household: HouseholdProfile) -> OrdinaryAccess {
        let hasCar = household.transport.hasVehicle
        let range = ResourceSuggestionPlanner.travel(transport: hasCar ? "car" : "noCar").km * 1000
        let meters: Double? = {
            guard let destination, let origin else { return nil }
            return ResourceRelevancePolicy.haversineMeters(origin, destination)
        }()
        return OrdinaryAccess(straightLineMeters: meters, plannableModes: hasCar ? ["driving", "walking"] : ["walking", "transit"],
                              ordinaryRangeMeters: range)
    }
}

/// The five answers every important resource owes a family: why it matters to them, what a source actually
/// verifies, what is still unknown, how far it is under ordinary conditions, and what to prepare now.
/// Deterministic from saved facts and source records; Beacon may rephrase but cannot add a capability.
public struct ResourceRelevance: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// Base purpose of the place kind (cooling/warming/shelter) or of the open preparation task.
        case placePurpose(PublicPlace.Kind)
        case openTask(taskID: String, purposeKey: String)
        case poweredEquipment(equipmentID: String, personID: String?)
        case coldStorage(equipmentID: String)
        case heatSensitive(personID: String)
        case coldSensitive(personID: String)
        case stepFree(personID: String)
        case pets
    }
    public enum Service: Sendable, Hashable {
        /// FEMA ESF6-SS lists the shelter as OPEN at retrieval time; that is the only verified service.
        case femaOpenShelter(retrievedAt: String)
        /// A curated public page names the facility and its seasonal role; it is not confirmed open now.
        case curatedPublic(source: String, retrievedAt: String, role: String?)
        case officialDirectory(publisher: String, checkedAt: String, reviewed: Bool)
        /// A map listing is a business name and address only.
        case mapListing
    }
    public enum Unknown: String, Sendable, Hashable, CaseIterable {
        case openNow, hours, medicalPower, stepFree, petPolicy, stock, compatibility, eligibility, roadConditions
    }
    public enum Preparation: String, Sendable, Hashable, CaseIterable {
        case callAhead, confirmMedicalPower, bringCooler, askStepFree, askPets, arrangeTransport, checkOfficialSource
    }

    public let reasons: [Reason]
    public let service: Service
    public let unknowns: [Unknown]
    public let access: OrdinaryAccess
    public let prepareNow: [Preparation]
}

public enum ResourceRelevancePolicy {
    /// Relevance of a FEMA shelter or curated cooling/warming center to this household.
    public static func forPublicPlace(_ place: PublicPlace, household: HouseholdProfile, origin: GeographicCoordinate?) -> ResourceRelevance {
        var reasons: [ResourceRelevance.Reason] = [.placePurpose(place.kind)]
        var unknowns: [ResourceRelevance.Unknown] = []
        var prepare: [ResourceRelevance.Preparation] = [.callAhead]
        let service: ResourceRelevance.Service
        switch place.kind {
        case .openShelter:
            service = .femaOpenShelter(retrievedAt: place.retrievedAt)
            unknowns.append(.hours)
        case .coolingCenter, .warmingCenter:
            service = .curatedPublic(source: place.source, retrievedAt: place.retrievedAt, role: place.role)
            unknowns += [.openNow, .hours]
            prepare.append(.checkOfficialSource)
        }
        for person in household.people {
            if place.kind == .coolingCenter && person.needs.contains(.heatSensitive) { reasons.append(.heatSensitive(personID: person.id)) }
            if place.kind == .warmingCenter && person.needs.contains(.coldSensitive) { reasons.append(.coldSensitive(personID: person.id)) }
        }
        let essential = household.equipment.filter(\.isEssential)
        let powered = essential.filter(\.requiresElectricalPower)
        for equipment in powered { reasons.append(.poweredEquipment(equipmentID: equipment.id, personID: equipment.personID)) }
        if !powered.isEmpty { unknowns.append(.medicalPower); prepare.append(.confirmMedicalPower) }
        let cold = essential.filter(\.requiresColdStorage)
        for equipment in cold { reasons.append(.coldStorage(equipmentID: equipment.id)) }
        if !cold.isEmpty { prepare.append(.bringCooler) }
        // Step-free access is stated by the source or it is unknown; a "true" statement still needs a call.
        if let person = household.people.first(where: \.requiresStepFreeRoute) {
            reasons.append(.stepFree(personID: person.id))
            let stated = place.stated.first { $0.fact == "wheelchairAccessible" }?.value
            if stated != true { unknowns.append(.stepFree) }
            prepare.append(.askStepFree)
        }
        if !household.pets.isEmpty {
            reasons.append(.pets)
            if place.petsAsPublished == nil { unknowns.append(.petPolicy) }
            prepare.append(.askPets)
        }
        let destination = place.latitude.flatMap { lat in place.longitude.flatMap { GeographicCoordinate(latitude: lat, longitude: $0) } }
        let access = OrdinaryAccess.of(destination: destination, origin: origin, household: household)
        if !household.transport.hasVehicle || access.withinOrdinaryRange == false { prepare.append(.arrangeTransport) }
        unknowns.append(.roadConditions)
        return ResourceRelevance(reasons: reasons, service: service, unknowns: unknowns, access: access, prepareNow: prepare)
    }

    /// Hazard context decides which kind of place leads; nearest-first order is kept within each kind.
    public static func order(_ places: [PublicPlace], context: MapPlanningContext) -> [PublicPlace] {
        let lead: [PublicPlace.Kind]
        switch context.intent {
        case .heatContinuity: lead = [.coolingCenter]
        case .freezeContinuity: lead = [.warmingCenter]
        case .hurricaneAdvance, .flashFlood, .tornadoShelter: lead = [.openShelter]
        case .ordinary, .structureFire, .waterContinuity: return places
        }
        return places.filter { lead.contains($0.kind) } + places.filter { !lead.contains($0.kind) }
    }

    static func haversineMeters(_ a: GeographicCoordinate, _ b: GeographicCoordinate) -> Double {
        let r = 6_371_000.0, dLat = (b.latitude - a.latitude) * .pi / 180, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// Starting from the saved address: a saved pin wins; otherwise on-device geocoding candidates are used
/// automatically only when they agree. Disagreeing candidates ask the family to review, never a guess.
public enum HomeOriginPolicy {
    public enum Decision: Sendable, Hashable {
        case saved(GeographicCoordinate)
        case resolvedFromAddress(GeographicCoordinate)
        case ambiguous(count: Int)
        case unresolved
        case noAddress
    }
    public struct Candidate: Sendable, Hashable {
        public let coordinate: GeographicCoordinate
        public let countryCode: String?
        public init(coordinate: GeographicCoordinate, countryCode: String?) { self.coordinate = coordinate; self.countryCode = countryCode }
    }
    /// Candidates within this distance of the first describe the same home.
    public static let agreementMeters = 250.0

    /// The query sent to the on-device geocoder: the saved address with locality hints, never the unit number.
    public static func geocodingQuery(_ location: PrivateLocation?) -> String? {
        guard let line = location?.addressLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        let extras = [location?.city, location?.administrativeArea, location?.postalCode].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty && !line.localizedCaseInsensitiveContains($0) }
        return ([line] + extras).joined(separator: ", ")
    }

    public static func savedCoordinate(_ location: PrivateLocation?) -> GeographicCoordinate? {
        guard let lat = location?.latitude, let lon = location?.longitude else { return nil }
        return GeographicCoordinate(latitude: lat, longitude: lon)
    }

    public static func decide(location: PrivateLocation?, candidates: [Candidate]?) -> Decision {
        if let saved = savedCoordinate(location) { return .saved(saved) }
        guard geocodingQuery(location) != nil else { return .noAddress }
        guard let candidates else { return .unresolved }
        let country = location?.countryCode?.uppercased()
        let usable = candidates.filter { candidate in
            guard let country, !country.isEmpty, let code = candidate.countryCode?.uppercased() else { return true }
            return code == country
        }
        guard let first = usable.first else { return .unresolved }
        let agree = usable.allSatisfy { ResourceRelevancePolicy.haversineMeters(first.coordinate, $0.coordinate) <= agreementMeters }
        return agree ? .resolvedFromAddress(first.coordinate) : .ambiguous(count: usable.count)
    }
}

/// A small set of meeting roles made contextual to the situation, reusing saved meetups and the
/// household's out-of-area contact. There is no separate reconnection workflow or record type.
///
/// Roles are explicit and fixed per record type: an `outsideMeetingPoint` is the immediate gathering point right
/// outside this home; a `backupMeetingPlace` is, by its definition across the app ("backup meeting place outside
/// the neighborhood"), an out-of-area place. No saved record type describes a nearby neighborhood meeting place,
/// so no "nearby" row is shown and a backup place can never be presented as nearby.
public enum MeetingPlanPolicy {
    public enum Purpose: String, Sendable, Hashable, CaseIterable {
        /// Right outside this home after leaving the building (fire).
        case immediateOutdoor
        /// The saved backup meeting place outside the neighborhood.
        case outOfAreaPlace
        /// Someone outside the area everyone checks in with when local options fail.
        case outOfAreaContact
    }
    public enum Status: Sendable, Hashable {
        case place(id: String)
        case contact(id: String)
        case missing
    }
    public struct Need: Sendable, Hashable {
        public let purpose: Purpose
        public let status: Status
        /// The purpose the situation depends on first.
        public let isPrimary: Bool
    }

    public static func purposes(for intent: MapPlanningContext.Intent) -> [Purpose] {
        switch intent {
        case .ordinary, .structureFire: [.immediateOutdoor, .outOfAreaPlace, .outOfAreaContact]
        // Sheltering at home comes first; if people are apart after the warning, checking in comes before travelling.
        case .tornadoShelter, .flashFlood, .freezeContinuity, .heatContinuity, .waterContinuity: [.outOfAreaContact, .outOfAreaPlace]
        case .hurricaneAdvance: [.outOfAreaPlace, .outOfAreaContact]
        }
    }

    /// The only saved-place purpose that may fill a role; nil for the contact role.
    public static func savedPurpose(_ purpose: Purpose) -> SavedPlacePurpose? {
        switch purpose {
        case .immediateOutdoor: .outsideMeetingPoint
        case .outOfAreaPlace: .backupMeetingPlace
        case .outOfAreaContact: nil
        }
    }

    /// The meeting role a saved place plays, or nil when it is not a meetup.
    public static func role(of purpose: SavedPlacePurpose) -> Purpose? {
        Purpose.allCases.first { savedPurpose($0) == purpose }
    }

    public static func needs(context: MapPlanningContext, household: HouseholdProfile, places: [SavedPlace]) -> [Need] {
        let homePlaces = PlanMapSelection.displayOrder(places.filter { $0.homeID == household.stableHomeID })
        let order = purposes(for: context.intent)
        return order.enumerated().map { index, purpose in
            let status: Status
            if let saved = savedPurpose(purpose) {
                status = homePlaces.first { $0.purpose == saved }.map { .place(id: $0.id) } ?? .missing
            } else {
                status = household.contacts.first { $0.role == .outOfAreaContact && $0.isComplete }.map { .contact(id: $0.id) } ?? .missing
            }
            let primary = index == 0 && context.intent != .ordinary
                && !(context.intent == .tornadoShelter || context.intent == .freezeContinuity || context.intent == .heatContinuity || context.intent == .waterContinuity)
            return Need(purpose: purpose, status: status, isPrimary: primary)
        }
    }
}
