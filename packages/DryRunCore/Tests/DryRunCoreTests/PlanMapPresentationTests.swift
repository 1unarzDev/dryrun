import Foundation
import Testing
@testable import DryRunCore

@Suite("Consistent map extents, route endpoints and exported place facts")
struct PlanMapPresentationTests {
    private let home = GeographicCoordinate(latitude: 32.2, longitude: -98.2)!
    private let distant = GeographicCoordinate(latitude: 35, longitude: -98.2)!

    @Test func phoneAndExportExtentsKeepTextOnlyNumbersAndReportPartialFailure() {
        let places = [
            SavedPlace(id: "a-text", homeID: "h", purpose: .outsideMeetingPoint, label: "Gate", findingInstructions: "Beside the oak"),
            SavedPlace(id: "b-resource", homeID: "h", purpose: .fallbackDestination, label: "Shop", coordinate: home),
            SavedPlace(id: "c-backup", homeID: "h", purpose: .backupMeetingPlace, label: "Distant family", coordinate: distant)
        ]
        let extents = PlanMapSelection.extents(homeCoordinate: home, places: places)
        #expect(extents.map(\.id) == ["neighborhood", "place|c-backup"])
        #expect(extents[0].homeCoordinate == home)
        #expect(extents[0].places.map(\.number) == [2])
        #expect(extents[1].homeCoordinate == nil)
        #expect(extents[1].places.map(\.number) == [3])
        #expect(PlanMapSelection.missingExtents(homeCoordinate: home, places: places, renderedExtentIDs: ["neighborhood"]).map(\.id) == ["place|c-backup"])
        #expect(PlanMapSelection.missingExtents(homeCoordinate: home, places: places, renderedExtentIDs: Set(extents.map(\.id))).isEmpty)
        #expect(PlanMapSelection.missingExtents(homeCoordinate: home, places: places, renderedExtentIDs: []).count == 2)
        #expect(PlanMapSelection.extents(homeCoordinate: nil, places: [places[0]]).isEmpty)
    }

    @Test func onlyChangedOrDeletedEndpointsInvalidateDirections() {
        let origin = SavedPlace(id: "origin", homeID: "h", purpose: .outsideMeetingPoint, label: "Gate", coordinate: home)
        let destination = SavedPlace(id: "destination", homeID: "h", purpose: .backupMeetingPlace, label: "Library", coordinate: distant)
        let endpoints = MapPlanningRouteEndpoints(origin: .savedPlace(id: origin.id, coordinate: home), destination: .savedPlace(id: destination.id, coordinate: distant))
        var renamed = origin; renamed.label = "South gate"; renamed.findingInstructions = "Across driveway"; renamed.sourcePublisher = "Edited source"
        let unrelated = SavedPlace(id: "other", homeID: "h", purpose: .fallbackDestination, label: "Shop", coordinate: home)
        #expect(endpoints.isCurrent(homeCoordinate: nil, places: [renamed, destination]))
        #expect(endpoints.isCurrent(homeCoordinate: distant, places: [renamed, destination, unrelated]))
        #expect(!endpoints.isCurrent(homeCoordinate: home, places: [destination, unrelated]))
        #expect(!endpoints.isCurrent(homeCoordinate: home, places: [origin, unrelated]))
        var moved = destination; moved.coordinate = home
        #expect(!endpoints.isCurrent(homeCoordinate: home, places: [origin, moved]))
        moved.coordinate = nil
        #expect(!endpoints.isCurrent(homeCoordinate: home, places: [origin, moved]))
        let fromHome = MapPlanningRouteEndpoints(origin: .home(home), destination: .external)
        #expect(fromHome.isCurrent(homeCoordinate: home, places: []))
        #expect(!fromHome.isCurrent(homeCoordinate: distant, places: []))
        #expect(!fromHome.isCurrent(homeCoordinate: nil, places: []))
    }

    @Test func selectedResourceContactProvenanceAndHonestStatusAreSharedInAllLanguages() throws {
        let household = SampleHouseholds.oak
        let official = SavedPlace(id: "b-office", homeID: household.stableHomeID, purpose: .fallbackDestination, label: "Fictional office", coordinate: home,
            addressText: "1 Fictional Road", findingInstructions: "Side entrance", provenance: .officialDirectory, sourceResourceID: "resource.example",
            sourceIDs: ["S41"], sourceCheckedAt: "2026-10-17", sourcePublisher: "Example public agency", contactPhone: "+84 28 3822 0000", websiteURL: "https://example.org")
        let textOnly = SavedPlace(id: "a-text", homeID: household.stableHomeID, purpose: .outsideMeetingPoint, label: "Fictional gate", findingInstructions: "Beside the oak")
        let apple = SavedPlace.appleSuggestion(sourceID: "pharmacy", name: "Fictional pharmacy", coordinate: distant, address: "2 Fictional Road", phone: "+33 1 23 45 67 89", website: nil, homeID: household.stableHomeID)
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let expected = PlanPlacePresentation.lines(for: official, number: 2, localizer: l)
            #expect(expected.allSatisfy { $0.sourceIDs == ["S41"] && !$0.isFallback })
            let text = expected.map(\.text).joined(separator: "\n")
            for retained in ["2. Fictional office", "+84 28 3822 0000", "https://example.org", "2026-10-17", "Example public agency", "Side entrance", l("map.savedSourceNote")] { #expect(text.contains(retained)) }
            let appleText = PlanPlacePresentation.lines(for: apple, number: 3, localizer: l).map(\.text).joined(separator: "\n")
            #expect(appleText.contains(l("map.source.apple")))
            #expect(appleText.contains(l("map.source.checkMissing")))
            #expect(appleText.contains(l("map.savedSourceNote")))
            let doc = PlanBuilder.build(household: household, home: nil, savedPlaces: [official, textOnly], results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
            let section = try #require(doc.pages.flatMap(\.sections).first { $0.id == "neighborhood" })
            #expect(section.lines.suffix(expected.count).map(\.text) == expected.map(\.text))
            #expect(section.lines.first?.text.hasPrefix("1. Fictional gate") == true)
            #expect(doc.visualSnapshot?.savedPlaces.map(\.id) == [textOnly.id, official.id])
        }
    }
}
