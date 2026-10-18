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

extension HomeMeetingPlacesTests {
    @Test("A confirmed local landmark migrates into card and preparation without inventing geographic coordinates")
    func localLandmarkBecomesTextPlace() throws {
        let home = SampleHomes.ranch
        var household = SampleHouseholds.oak; household.homeID = home.id
        let local = try #require(home.meetingPoint)
        let places = HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: household.updatedAt)
        let place = try #require(places.first)
        #expect(place.label == local.label && place.coordinate == nil && place.homeID == home.id)
        #expect(place.provenance == .fixture)
        let legacyPlaces = HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: nil)
        #expect(legacyPlaces.first?.createdAt == Date(timeIntervalSince1970: 0))
        #expect(legacyPlaces == HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: nil))
        #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: places, recordedAt: household.updatedAt) == places)
        let l = try PlanBuilderTests.localizer("en")
        let doc = PlanBuilder.build(household: household, home: home, results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        #expect(doc.pages.first?.sections.first { $0.id == "outsideMeetingPoint" }?.lines.contains { $0.text.contains(local.label) } == true)
        #expect(!BaselinePreparedness.evaluate(household: household, home: home).contains { $0.id == "prep.nearMeetup" })
        #expect(!doc.isStale(household: household, home: home, contentVersion: "test", savedPlaces: []))
        let linked = HomeMeetingPlaces.synchronize(home, places: places)
        let removed = HomeMeetingPlaces.synchronize(linked, places: [])
        #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: removed, places: [], recordedAt: household.updatedAt).isEmpty)
    }

    @Test("Proposed or unlinked homes cannot silently supply a confirmed family destination")
    func unconfirmedLandmarkStaysUnknown() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.annotations.firstIndex { $0.kind == .outsideMeetingPoint })
        home.annotations[index].verification = .proposed
        #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: LeadTestSupport.fixedDate).isEmpty)
        #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: nil, places: [], recordedAt: LeadTestSupport.fixedDate).isEmpty)
    }

    @Test("Generic marker types never become named family meeting places during migration")
    func defaultMarkerIsNotANamedMeetup() throws {
        for label in ["", "  ", "outsideMeetingPoint", "enum.outsideMeetingPoint"] {
            var home = SampleHomes.ranch
            let index = try #require(home.annotations.firstIndex { $0.kind == .outsideMeetingPoint })
            home.annotations[index].label = label
            #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: nil).isEmpty)
            #expect(BaselinePreparedness.evaluate(household: SampleHouseholds.oak, home: home).contains { $0.id == "prep.nearMeetup" })
        }
    }

    @Test("Canvas edits and deletion update only the linked destination and every derived plan/task")
    func editAndDeleteLinkedMeetup() throws {
        let now = LeadTestSupport.fixedDate
        var home = SampleHomes.ranch
        var place = SavedPlace(id: "near", homeID: home.id, purpose: .outsideMeetingPoint, label: "Original gate",
            coordinate: GeographicCoordinate(latitude: 35, longitude: 140), addressText: "Recorded address",
            findingInstructions: "Old finding note", provenance: .appleMapsSearch, sourceResourceID: "apple:gate", contactPhone: "+81 3 1234 5678", createdAt: now, updatedAt: now)
        let backup = SavedPlace(id: "backup", homeID: home.id, purpose: .backupMeetingPlace, label: "Outside neighborhood")
        let unrelated = SavedPlace(id: "other", homeID: "other-home", purpose: .outsideMeetingPoint, label: "Another household")
        home = HomeMeetingPlaces.synchronize(home, places: [place, backup, unrelated])
        var edited = home
        let index = try #require(edited.annotations.firstIndex { $0.savedPlaceID == place.id })
        edited.annotations[index].label = "Updated gate"
        edited.annotations[index].note = "Beside the blue sign"
        let changedAt = now.addingTimeInterval(60)
        let changed = HomeMeetingPlaces.placesAfterHomeEdit(previous: home, updated: edited, places: [place, backup, unrelated], editedAt: changedAt)
        place.label = "Updated gate"; place.findingInstructions = "Beside the blue sign"; place.updatedAt = changedAt
        #expect(changed == [place, backup, unrelated], "Address, coordinate, identity, provenance, contact and creation date survive contextual edits")
        let linked = HomeMeetingPlaces.synchronize(edited, places: changed)
        #expect(linked.meetingPoint?.label == place.label && linked.meetingPoint?.note == place.findingInstructions)
        let l = try PlanBuilderTests.localizer("en")
        var household = SampleHouseholds.oak; household.homeID = home.id
        let doc = PlanBuilder.build(household: household, home: linked, savedPlaces: changed, results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: now)
        #expect(doc.pages.first?.sections.first { $0.id == "outsideMeetingPoint" }?.lines.contains { $0.text.contains("Updated gate") && $0.text.contains("Beside the blue sign") } == true)
        var removed = linked
        removed.annotations.removeAll { $0.savedPlaceID == place.id }
        let remaining = HomeMeetingPlaces.placesAfterHomeEdit(previous: linked, updated: removed, places: changed, editedAt: changedAt.addingTimeInterval(60))
        #expect(remaining == [backup, unrelated])
        removed = HomeMeetingPlaces.synchronize(removed, places: remaining)
        #expect(removed.meetingPoint == nil)
        #expect(HomeMeetingPlaces.placesIncludingLocalMeetup(home: removed, places: remaining, recordedAt: nil) == remaining)
        #expect(BaselinePreparedness.evaluate(household: household, home: removed, savedPlaces: remaining).contains { $0.id == "prep.nearMeetup" })
        #expect(doc.isStale(household: household, home: removed, contentVersion: "test", savedPlaces: remaining))
    }

    @Test("An unrelated rescan, geometry replacement or deleted room does not delete geographic plans")
    func replacementAndCascadePreservePlaces() throws {
        var original = SampleHomes.ranch
        original.source = .roomPlanScan; original.sourceCaptureFrameID = "capture-before"
        let place = SavedPlace(id: "near", homeID: original.id, purpose: .outsideMeetingPoint, label: "Keep this address", coordinate: .init(latitude: 30, longitude: -90))
        original = HomeMeetingPlaces.synchronize(original, places: [place])
        var rescan = SampleHomes.twoStory
        rescan.id = original.id; rescan.source = .roomPlanScan; rescan.sourceCaptureFrameID = "capture-after"
        rescan.annotations.removeAll { $0.kind == .outsideMeetingPoint }
        #expect(HomeMeetingPlaces.placesAfterHomeEdit(previous: original, updated: rescan, places: [place], editedAt: LeadTestSupport.fixedDate) == [place])
        var replacement = ManualLayout.emptyHome(id: original.id)
        replacement.annotations = []
        #expect(HomeMeetingPlaces.placesAfterHomeEdit(previous: original, updated: replacement, places: [place], editedAt: LeadTestSupport.fixedDate) == [place])
        let index = try #require(original.annotations.firstIndex { $0.savedPlaceID == place.id })
        original.annotations[index].spaceID = "sp-kitchen"
        var roomRemoved = original
        roomRemoved.spaces.removeAll { $0.id == "sp-kitchen" }
        roomRemoved.annotations.removeAll { $0.savedPlaceID == place.id }
        #expect(HomeMeetingPlaces.placesAfterHomeEdit(previous: original, updated: roomRemoved, places: [place], editedAt: LeadTestSupport.fixedDate) == [place])
    }

    @Test("Changing geographic destinations clears a stale local marker position; migration retains its own position")
    func destinationDoesNotInheritAnotherLandmarksPosition() throws {
        var home = SampleHomes.ranch
        let index = try #require(home.annotations.firstIndex { $0.kind == .outsideMeetingPoint })
        home.annotations[index].position = Vec2(-3, 2); home.annotations[index].floorID = home.floors[0].id
        let migrated = HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: [], recordedAt: nil)
        let linked = HomeMeetingPlaces.synchronize(home, places: migrated)
        #expect(linked.meetingPoint?.position == Vec2(-3, 2))
        let different = SavedPlace(id: "different", homeID: home.id, purpose: .outsideMeetingPoint, label: "A different landmark", coordinate: .init(latitude: 36, longitude: 140))
        let changed = HomeMeetingPlaces.synchronize(linked, places: [different])
        #expect(changed.meetingPoint?.position == nil && changed.meetingPoint?.floorID == nil && changed.meetingPoint?.spaceID == nil)
        #expect(changed.meetingPoint?.savedPlaceID == different.id)
    }
}
