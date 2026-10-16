import Foundation
import Testing
@testable import DryRunCore

@Suite("Private geographic planning places")
struct PrivatePlacesTests {
    @Test("Coordinates reject partial, non-finite, and out-of-range values")
    func coordinateValidation() {
        #expect(GeographicCoordinate(latitude: 32.22, longitude: -98.20) != nil)
        #expect(GeographicCoordinate(latitude: 90, longitude: 180) != nil)
        #expect(GeographicCoordinate(latitude: 90.01, longitude: 0) == nil)
        #expect(GeographicCoordinate(latitude: 0, longitude: -180.01) == nil)
        #expect(GeographicCoordinate(latitude: .nan, longitude: 0) == nil)
        #expect(GeographicCoordinate(latitude: 0, longitude: .infinity) == nil)
    }

    @Test("Saved place keeps geographic coordinates distinct from indoor Vec2")
    func savedPlaceRoundTrip() throws {
        let c = try #require(GeographicCoordinate(latitude: 32.2201556, longitude: -98.2023049))
        let place = SavedPlace(homeID: "home-sample-ranch", purpose: .outsideMeetingPoint,
                               label: "County courthouse", coordinate: c, addressText: "100 W Washington",
                               provenance: .officialDirectory, sourceResourceID: "r-48143-oem")
        let data = try DryRunJSON.encoder().encode(place)
        let decoded = try DryRunJSON.decoder().decode(SavedPlace.self, from: data)
        #expect(decoded.coordinate == c)
        #expect(decoded.homeID == "home-sample-ranch")
        #expect(decoded.purpose == .outsideMeetingPoint)
    }
}
