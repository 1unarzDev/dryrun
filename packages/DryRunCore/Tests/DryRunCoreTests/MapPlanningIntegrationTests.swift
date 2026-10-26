import Foundation
import Testing
@testable import DryRunCore

@Suite("Connected map planning records")
struct MapPlanningIntegrationTests {
    @Test func addressUnitAndNoOpEditsRetainExplicitCoverageWithoutInferringANewRegion() {
        let original = PrivateLocation(addressLine: "Fictional address", latitude: 32.2, longitude: -98.2, unit: "1", city: "Example", administrativeArea: "TX", postalCode: "00000", countryCode: "US")
        #expect(HomeLocationChange.regionID(previous: original, updated: original, existingRegionID: "48143") == "48143")
        var unitOnly = original; unitOnly.unit = "Apartment 2"
        #expect(HomeLocationChange.regionID(previous: original, updated: unitOnly, existingRegionID: "48143") == "48143")
        for changed in [PrivateLocation(addressLine: "New fictional address", countryCode: "US"),
                        PrivateLocation(addressLine: original.addressLine, latitude: 32.3, longitude: -98.2, countryCode: "US"),
                        PrivateLocation(addressLine: original.addressLine, countryCode: "VN"), PrivateLocation()] {
            #expect(HomeLocationChange.regionID(previous: original, updated: changed, existingRegionID: "48143") == "unsupported")
        }
        #expect(HomeLocationChange.regionID(previous: nil, updated: original, existingRegionID: "48143") == "unsupported")
        #expect(HomeLocationChange.regionID(previous: original, updated: original, existingRegionID: "48001") == "unsupported")
        #expect(HomeLocationChange.regionID(previous: nil, updated: PrivateLocation(administrativeArea: "Erath County"), existingRegionID: "") == "unsupported")
    }

    @Test func meetingPinsKeepTheirSlotsAndOriginalNumbersAheadOfOptionalResources() {
        let home = GeographicCoordinate(latitude: 32.2, longitude: -98.2)!
        let far = GeographicCoordinate(latitude: 35, longitude: -98.2)!
        var places = (0..<7).map { SavedPlace(id: "a-local-\($0)", homeID: "home", purpose: .fallbackDestination, label: "Local \($0)", coordinate: home) }
        places += (0..<3).map { SavedPlace(id: "b-distant-\($0)", homeID: "home", purpose: .fallbackDestination, label: "Distant \($0)", coordinate: far) }
        places += [SavedPlace(id: "z-near", homeID: "home", purpose: .outsideMeetingPoint, label: "Near meetup", coordinate: home),
                   SavedPlace(id: "z-backup", homeID: "home", purpose: .backupMeetingPlace, label: "Backup meetup", coordinate: far)]
        for input in [places, places.reversed().map { $0 }] {
            let selection = PlanMapSelection.panels(homeCoordinate: home, places: input)
            #expect(selection.local.count == 6)
            #expect(selection.distant.count == 2)
            #expect(selection.local.first?.place.id == "z-near")
            #expect(selection.distant.first?.place.id == "z-backup")
            for entry in selection.local + selection.distant { #expect(input[entry.number - 1] == entry.place) }
            #expect(Set(selection.local.map(\.place.id)) == Set(PlanMapSelection.panels(homeCoordinate: home, places: places).local.map(\.place.id)))
        }
        let tight = PlanMapSelection.panels(homeCoordinate: home, places: places, localLimit: 0, distantLimit: 0)
        #expect(tight.local.map(\.place.id) == ["z-near"])
        #expect(tight.distant.map(\.place.id) == ["z-backup"])
    }

    @Test func textOnlyMeetingPlacesNeverInventPinsAndNoHomeUsesTheNearMeetingOrigin() {
        let coordinate = GeographicCoordinate(latitude: 10.8, longitude: 106.7)!
        let text = SavedPlace(id: "a-text", homeID: "home", purpose: .outsideMeetingPoint, label: "Mailbox", findingInstructions: "Beside the gate")
        let backup = SavedPlace(id: "z-backup", homeID: "home", purpose: .backupMeetingPlace, label: "Library", coordinate: coordinate)
        let empty = PlanMapSelection.panels(homeCoordinate: nil, places: [text])
        #expect(empty.origin == nil && empty.local.isEmpty && empty.distant.isEmpty)
        let withBackup = PlanMapSelection.panels(homeCoordinate: nil, places: [text, backup])
        #expect(withBackup.origin == coordinate)
        #expect(withBackup.local.map(\.number) == [2])
        #expect(withBackup.local.first?.place.id == backup.id)
    }

    private func official() throws -> PublicResource {
        let json = """
        {"id":"official.resource","name":"Fictional public office","publisher":"Example public agency","serviceType":"emergencyManagement","jurisdiction":"example","regionIDs":["48143"],
        "contact":{"phone":"+84 28 3822 0000","url":"https://example.org/office","address":"1 Fictional Street"},
        "summary":"Fictional fixture for source preservation.","activation":"unknown","latitude":32.2,"longitude":-98.2,
        "sourceIDs":["S41"],"checkedAt":"2026-10-17","reviewState":"needsReview","classification":"fixture"}
        """
        return try DryRunJSON.decoder().decode(PublicResource.self, from: Data(json.utf8))
    }

    @Test func officialCoordinateAndListOnlySourcesStayUsefulAfterSavingAndReloading() throws {
        let resource = try official()
        let coordinate = SavedPlace.officialResource(resource, homeID: "personal-home")
        #expect(coordinate.purpose == .fallbackDestination)
        #expect(coordinate.coordinate == resource.planningCoordinate)
        #expect(coordinate.sourceResourceID == resource.id)
        #expect(coordinate.sourceIDs == resource.sourceIDs)
        #expect(coordinate.sourceCheckedAt == resource.checkedAt)
        #expect(coordinate.sourcePublisher == resource.publisher)
        #expect(coordinate.provenance == .officialDirectory)
        #expect(coordinate.contactPhone == "+84 28 3822 0000")
        #expect(coordinate.websiteURL == "https://example.org/office")
        #expect(try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(coordinate)) == coordinate)
        var listOnly = resource; listOnly.latitude = nil; listOnly.longitude = nil
        let text = SavedPlace.officialResource(listOnly, homeID: "personal-home")
        #expect(text.coordinate == nil)
        #expect(text.addressText == "1 Fictional Street")
        #expect(text.sourceResourceID == resource.id && text.contactPhone == coordinate.contactPhone)
        #expect(PublicDataPolicy.activationDisplay(for: resource, now: LeadTestSupport.fixedDate) == .notApplicable)
    }

    @Test func appleSuggestionsRetainSourceIdentityWithoutBecomingAMeetupOrClaimingReview() throws {
        let saved = SavedPlace.appleSuggestion(sourceID: "place.id", name: "Fictional pharmacy", coordinate: GeographicCoordinate(latitude: 10.8, longitude: 106.7)!,
            address: "Fictional address", phone: "+84 28 3822 0000", website: "https://example.org", homeID: "personal-home")
        #expect(saved.purpose == .fallbackDestination)
        #expect(saved.sourceResourceID == "apple:place.id")
        #expect(saved.sourceCheckedAt == nil && saved.sourcePublisher == nil)
        #expect(saved.provenance == .appleMapsSearch)
        #expect(try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(saved)) == saved)
        let explicitlyMeeting = SavedPlace.appleSuggestion(sourceID: "place.id", name: saved.label, coordinate: saved.coordinate!, address: saved.addressText,
            phone: saved.contactPhone, website: saved.websiteURL, homeID: saved.homeID, purpose: .outsideMeetingPoint)
        #expect(explicitlyMeeting.purpose == .outsideMeetingPoint)
    }

    @Test func oldPlaceSnapshotsDecodeWithoutNewSourceAndContactMetadata() throws {
        let old = SavedPlace(id: "old-place", homeID: "personal-home", purpose: .outsideMeetingPoint, label: "Gate", addressText: "Old address", findingInstructions: "At the mailbox", sourceResourceID: "legacy-source")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        for key in ["sourceIDs", "sourceCheckedAt", "sourcePublisher", "contactPhone", "websiteURL"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(SavedPlace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored == old)
        #expect(restored.id == "old-place" && restored.homeID == "personal-home")
        #expect(restored.sourceCheckedAt == nil && restored.contactPhone == nil)
    }
}
