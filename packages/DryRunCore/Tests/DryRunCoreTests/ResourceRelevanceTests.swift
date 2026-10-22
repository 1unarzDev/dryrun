import Foundation
import Testing
@testable import DryRunCore

@Suite("Needs-linked shelters, origin resolution and contextual meetups")
struct ResourceRelevanceTests {
    private let fortWorth = GeographicCoordinate(latitude: 32.7555, longitude: -97.3308)!

    private func place(_ kind: PublicPlace.Kind, lat: Double? = 32.76, lon: Double? = -97.33,
                       stated: [PublicPlace.Stated] = [], pets: String? = nil) -> PublicPlace {
        PublicPlace(id: "p-\(kind.rawValue)", name: "Fictional \(kind.rawValue)", kind: kind, address: "1 Main St", latitude: lat, longitude: lon,
                    phone: nil, source: "Test source", sourceURL: nil, retrievedAt: "2026-10-20", stated: stated, petsAsPublished: pets,
                    role: kind == .openShelter ? nil : "Seasonal")
    }

    // MARK: FEMA field contract (fields verified against the live layer metadata on 2026-10-21)

    @Test func femaParserUsesVerifiedFieldShapesAndKeepsUnknownsUnknown() throws {
        let json = """
        {"features":[
          {"attributes":{"shelter_id":40123,"shelter_name":"Fictional Gym","address":"1 A St","city":"Fort Worth","state":"TX","zip":"76102",
            "shelter_status":"OPEN","wheelchair_accessible":"UNK","ada_compliant":" ","pet_accommodations_code":"NONE","latitude":32.75,"longitude":-97.33}},
          {"attributes":{"shelter_id":40124,"shelter_name":"Fictional Church","address":"2 B St","city":"Arlington","state":"TX","zip":"76010",
            "shelter_status":"OPEN","wheelchair_accessible":"YES","ada_compliant":"NO","pet_accommodations_code":" ","latitude":32.70,"longitude":-97.10}},
          {"attributes":{"shelter_id":40125,"shelter_name":"Closed Hall","address":"3 C St","city":"Dallas","state":"TX","zip":"75201",
            "shelter_status":"CLOSED","wheelchair_accessible":"YES","ada_compliant":"YES","pet_accommodations_code":"UNK","latitude":32.78,"longitude":-96.80}}
        ]}
        """
        let shelters = try PublicPlaces.femaShelters(Data(json.utf8), retrievedAt: "2026-10-21")
        #expect(shelters.map(\.id) == ["fema-40123", "fema-40124"])
        #expect(shelters[0].stated.isEmpty)
        #expect(shelters[0].petsAsPublished == "NONE")
        #expect(shelters[1].stated == [.init(fact: "wheelchairAccessible", value: true), .init(fact: "adaCompliant", value: false)])
        #expect(shelters[1].petsAsPublished == nil)
        #expect(shelters.allSatisfy { $0.retrievedAt == "2026-10-21" && $0.sourceURL != nil })
    }

    @Test func curatedTarrantPlacesCarrySourceDateAndOnlyStatedAccess() throws {
        let data = try Data(contentsOf: LeadTestSupport.contentRoot.appendingPathComponent("places/tarrant-v1.json"))
        let places = try PublicPlaces.curated(data)
        #expect(!places.isEmpty)
        for place in places {
            #expect(!place.source.isEmpty && place.sourceURL?.hasPrefix("https://") == true)
            #expect(place.retrievedAt.count == 10)
            #expect(place.latitude == nil && place.longitude == nil)
            #expect(place.kind != .openShelter)
        }
        let stated = """
        {"retrievedAt":"2026-10-20","places":[{"id":"x","name":"X","kind":"warmingCenter","address":"A","phone":null,
          "source":"S","sourceURL":"https://example.test","role":null,"accessibility":{"wheelchairAccessible":true}}]}
        """
        let parsed = try PublicPlaces.curated(Data(stated.utf8))
        #expect(parsed.first?.stated == [.init(fact: "wheelchairAccessible", value: true)])
    }

    // MARK: Five answers

    @Test func oxygenHouseholdGetsPowerReasonCallToConfirmAndNoClaimedPower() {
        let oak = SampleHouseholds.oak
        let relevance = ResourceRelevancePolicy.forPublicPlace(place(.openShelter), household: oak, origin: fortWorth)
        #expect(relevance.reasons.contains(.poweredEquipment(equipmentID: "eq-oxygen", personID: oak.equipment.first { $0.id == "eq-oxygen" }?.personID)))
        #expect(relevance.unknowns.contains(.medicalPower))
        #expect(relevance.prepareNow.contains(.confirmMedicalPower))
        #expect(relevance.service == .femaOpenShelter(retrievedAt: "2026-10-20"))
        #expect(relevance.unknowns.contains(.roadConditions))
        #expect(relevance.reasons.contains(.pets) && relevance.unknowns.contains(.petPolicy))
    }

    @Test func curatedCenterIsNeverConfirmedOpenAndStepFreeStaysUnknownUnlessStated() {
        let pine = SampleHouseholds.pine
        let unstated = ResourceRelevancePolicy.forPublicPlace(place(.coolingCenter), household: pine, origin: fortWorth)
        #expect(unstated.unknowns.contains(.openNow))
        #expect(unstated.unknowns.contains(.stepFree))
        #expect(unstated.prepareNow.contains(.askStepFree))
        if case .curatedPublic(_, _, let role) = unstated.service { #expect(role == "Seasonal") } else { Issue.record("expected curated service") }
        let stated = ResourceRelevancePolicy.forPublicPlace(place(.coolingCenter, stated: [.init(fact: "wheelchairAccessible", value: true)]),
                                                            household: pine, origin: fortWorth)
        #expect(!stated.unknowns.contains(.stepFree))
        // Even a stated entrance is something to ask about for this person; it is not a route guarantee.
        #expect(stated.prepareNow.contains(.askStepFree))
    }

    @Test func heatSensitivePersonMakesCoolingRelevantAndNoCarLimitsModes() {
        let lake = SampleHouseholds.lake
        let near = ResourceRelevancePolicy.forPublicPlace(place(.coolingCenter), household: lake, origin: fortWorth)
        #expect(near.reasons.contains(.heatSensitive(personID: "p-lake-1")))
        #expect(!near.access.plannableModes.contains("driving"))
        #expect(near.prepareNow.contains(.arrangeTransport))
        #expect(near.reasons.contains(.coldStorage(equipmentID: "eq-insulin")) && near.prepareNow.contains(.bringCooler))
        let far = ResourceRelevancePolicy.forPublicPlace(place(.coolingCenter, lat: 32.9, lon: -97.0), household: lake, origin: fortWorth)
        #expect(far.access.withinOrdinaryRange == false)
        let unknownDistance = ResourceRelevancePolicy.forPublicPlace(place(.coolingCenter, lat: nil, lon: nil), household: lake, origin: fortWorth)
        #expect(unknownDistance.access.straightLineMeters == nil && unknownDistance.access.withinOrdinaryRange == nil)
        let car = ResourceRelevancePolicy.forPublicPlace(place(.warmingCenter), household: SampleHouseholds.oak, origin: fortWorth)
        #expect(car.access.plannableModes.contains("driving"))
        #expect(car.reasons.contains(.coldSensitive(personID: "p-oak-4")))
    }

    @Test func hazardContextOrdersPlaceKindsWithoutDroppingAny() {
        let all = [place(.openShelter), place(.coolingCenter), place(.warmingCenter)]
        #expect(ResourceRelevancePolicy.order(all, context: .init(intent: .heatContinuity)).first?.kind == .coolingCenter)
        #expect(ResourceRelevancePolicy.order(all, context: .init(intent: .freezeContinuity)).first?.kind == .warmingCenter)
        #expect(ResourceRelevancePolicy.order(all, context: .init(intent: .hurricaneAdvance)).first?.kind == .openShelter)
        #expect(ResourceRelevancePolicy.order(all, context: .init()) == all)
        for intent in [MapPlanningContext.Intent.heatContinuity, .freezeContinuity, .flashFlood] {
            #expect(Set(ResourceRelevancePolicy.order(all, context: .init(intent: intent)).map(\.id)) == Set(all.map(\.id)))
        }
    }

    // MARK: Saved address → origin

    @Test func savedPinWinsAndAgreeingCandidatesResolveWithoutReview() {
        let pinned = PrivateLocation(addressLine: "1 Main St", latitude: 32.7, longitude: -97.3)
        #expect(HomeOriginPolicy.decide(location: pinned, candidates: nil) == .saved(GeographicCoordinate(latitude: 32.7, longitude: -97.3)!))
        let typed = PrivateLocation(addressLine: "100 Fictional Ave", city: "Fort Worth", administrativeArea: "TX", countryCode: "US")
        #expect(HomeOriginPolicy.geocodingQuery(typed) == "100 Fictional Ave, Fort Worth, TX")
        let a = GeographicCoordinate(latitude: 32.75, longitude: -97.33)!, b = GeographicCoordinate(latitude: 32.7505, longitude: -97.3302)!
        #expect(HomeOriginPolicy.decide(location: typed, candidates: [.init(coordinate: a, countryCode: "US"), .init(coordinate: b, countryCode: "US")])
                == .resolvedFromAddress(a))
    }

    @Test func disagreeingOrMissingCandidatesNeverGuess() {
        let typed = PrivateLocation(addressLine: "100 Main St", unit: "2B", countryCode: "US")
        #expect(HomeOriginPolicy.geocodingQuery(typed) == "100 Main St")
        let fw = GeographicCoordinate(latitude: 32.75, longitude: -97.33)!, dallas = GeographicCoordinate(latitude: 32.78, longitude: -96.80)!
        #expect(HomeOriginPolicy.decide(location: typed, candidates: [.init(coordinate: fw, countryCode: "US"), .init(coordinate: dallas, countryCode: "US")])
                == .ambiguous(count: 2))
        #expect(HomeOriginPolicy.decide(location: typed, candidates: []) == .unresolved)
        #expect(HomeOriginPolicy.decide(location: typed, candidates: nil) == .unresolved)
        let abroad = GeographicCoordinate(latitude: 51.5, longitude: -0.1)!
        #expect(HomeOriginPolicy.decide(location: typed, candidates: [.init(coordinate: abroad, countryCode: "GB")]) == .unresolved)
        #expect(HomeOriginPolicy.decide(location: typed, candidates: [.init(coordinate: abroad, countryCode: "GB"), .init(coordinate: fw, countryCode: "US")])
                == .resolvedFromAddress(fw))
        #expect(HomeOriginPolicy.decide(location: PrivateLocation(addressLine: "  "), candidates: nil) == .noAddress)
        #expect(HomeOriginPolicy.decide(location: nil, candidates: nil) == .noAddress)
    }

    // MARK: Contextual meetups

    @Test func meetupsAreContextualAndReuseSavedPlacesAndOutOfAreaContact() {
        let oak = SampleHouseholds.oak
        let home = oak.stableHomeID
        let gather = SavedPlace(id: "g", homeID: home, purpose: .outsideMeetingPoint, label: "Mailbox")
        let other = SavedPlace(id: "o", homeID: "another-home", purpose: .backupMeetingPlace, label: "Elsewhere")
        let fire = MeetingPlanPolicy.needs(context: .init(intent: .structureFire, phase: .simulation), household: oak, places: [gather, other])
        #expect(fire.map(\.purpose) == [.immediateOutdoor, .neighborhood, .outOfArea])
        #expect(fire[0].status == .place(id: "g") && fire[0].isPrimary)
        #expect(fire[1].status == .missing)
        #expect(fire[2].status == .contact(id: "ct-oak-1"))

        let tornado = MeetingPlanPolicy.needs(context: .init(intent: .tornadoShelter, phase: .incident), household: oak, places: [gather])
        #expect(!tornado.map(\.purpose).contains(.immediateOutdoor))
        #expect(tornado.allSatisfy { !$0.isPrimary })

        let hurricane = MeetingPlanPolicy.needs(context: .init(intent: .hurricaneAdvance), household: SampleHouseholds.lake, places: [])
        #expect(hurricane.first?.purpose == .outOfArea && hurricane.first?.isPrimary == true)
        #expect(hurricane.first?.status == .missing)
        #expect(MeetingPlanPolicy.needs(context: .init(), household: oak, places: []).allSatisfy { !$0.isPrimary })
    }
}
