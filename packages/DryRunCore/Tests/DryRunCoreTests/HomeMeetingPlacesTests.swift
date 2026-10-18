import Foundation
import Testing
@testable import DryRunCore

@Suite("Geographic and indoor meeting place linkage")
struct HomeMeetingPlacesTests {
    @Test func namedGeographicMeetupUpdatesIndoorReferenceWithoutInventingCoordinates() throws {
        var home = SampleHomes.ranch
        home.annotations.removeAll { $0.kind == .outsideMeetingPoint }
        let place = SavedPlace(id: "family-nearby", homeID: home.id, purpose: .outsideMeetingPoint,
                               label: "Fictional gate", coordinate: GeographicCoordinate(latitude: 35, longitude: 140),
                               findingInstructions: "Beside the large sign")
        let linked = HomeMeetingPlaces.synchronize(home, places: [place])
        let annotation = try #require(linked.meetingPoint)
        #expect(annotation.savedPlaceID == place.id)
        #expect(annotation.label == place.label)
        #expect(annotation.note == place.findingInstructions)
        #expect(annotation.position == nil)
        #expect(linked.portals == home.portals)
        #expect(linked.spaces == home.spaces)
    }

    @Test func editDeleteAndUnrelatedResourcePreserveCorrectAssociations() throws {
        let home = SampleHomes.ranch
        var place = SavedPlace(id: "near", homeID: home.id, purpose: .outsideMeetingPoint, label: "First label")
        let linked = HomeMeetingPlaces.synchronize(home, places: [place])
        place.label = "Updated label"
        #expect(HomeMeetingPlaces.synchronize(linked, places: [place]).meetingPoint?.label == "Updated label")
        #expect(HomeMeetingPlaces.synchronize(linked, places: []).meetingPoint == nil)
        #expect(HomeMeetingPlaces.synchronize(home, places: []).meetingPoint == home.meetingPoint)
        place.homeID = "another-home"
        #expect(HomeMeetingPlaces.synchronize(home, places: [place]).meetingPoint == home.meetingPoint)
        place.homeID = home.id; place.purpose = .backupMeetingPlace
        #expect(HomeMeetingPlaces.synchronize(home, places: [place]).meetingPoint == home.meetingPoint)
    }
}
