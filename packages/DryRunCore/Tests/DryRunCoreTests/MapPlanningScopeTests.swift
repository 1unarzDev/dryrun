import Testing
@testable import DryRunCore

@Suite("Map session scope")
struct MapPlanningScopeTests {
    @Test func identicalExampleResetStartsANewMapSession() {
        let first = MapPlanningScope(householdID: "family", homeID: "home", isExample: true, homeCoordinate: nil, sessionID: "first")
        let reset = MapPlanningScope(householdID: "family", homeID: "home", isExample: true, homeCoordinate: nil, sessionID: "reset")
        #expect(first != reset)
    }
    @Test func sameAddressAndRecordIDsDoNotMergeRealAndExampleSessions() {
        let coordinate = GeographicCoordinate(latitude: 32.2, longitude: -98.2)!
        let example = MapPlanningScope(householdID: "shared", homeID: "home", isExample: true, homeCoordinate: coordinate)
        let real = MapPlanningScope(householdID: "shared", homeID: "home", isExample: false, homeCoordinate: coordinate)
        let other = MapPlanningScope(householdID: "other", homeID: "home", isExample: true, homeCoordinate: coordinate)
        #expect(Set([example, real, other]).count == 3)
        #expect(example == MapPlanningScope(householdID: "shared", homeID: "home", isExample: true, homeCoordinate: coordinate))
    }

    @Test func missingOrChangedGeocodingInvalidatesMapSession() {
        let first = MapPlanningScope(householdID: "family", homeID: "home", isExample: true,
            homeCoordinate: GeographicCoordinate(latitude: 32.2, longitude: -98.2)!)
        let moved = MapPlanningScope(householdID: "family", homeID: "home", isExample: true,
            homeCoordinate: GeographicCoordinate(latitude: 33.2, longitude: -98.2)!)
        let unknown = MapPlanningScope(householdID: "family", homeID: "home", isExample: true, homeCoordinate: nil)
        #expect(Set([first, moved, unknown]).count == 3)
    }
}
