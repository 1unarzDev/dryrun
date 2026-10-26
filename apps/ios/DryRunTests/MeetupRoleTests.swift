import XCTest
import DryRunCore
@testable import DryRun

/// GEO-02 reviewer finding: Oak's distant backup meetup (Abilene) filled the "Nearby" row of Where to meet.
/// These run the native demo-load path that produced that state; demo switches never constitute device evidence.
@MainActor
final class MeetupRoleTests: XCTestCase {
    func testOakDemoBackupMeetupFillsOnlyTheOutOfAreaPlaceRole() async throws {
        let model = AppModel(store: InMemoryPrivateDataStore())
        await model.useSampleHousehold(SampleHouseholds.oak)
        let household = try XCTUnwrap(model.household)
        let places = model.savedPlaces.filter { $0.homeID == household.stableHomeID }
        let backup = try XCTUnwrap(places.first { $0.id == "demo-backup-meetup" })
        XCTAssertEqual(MeetingPlanPolicy.role(of: backup.purpose), .outOfAreaPlace)
        for intent in [MapPlanningContext.Intent.ordinary, .structureFire, .tornadoShelter, .flashFlood, .freezeContinuity,
                       .heatContinuity, .waterContinuity, .hurricaneAdvance] {
            let needs = MeetingPlanPolicy.needs(context: MapPlanningContext(intent: intent), household: household, places: places)
            for need in needs {
                guard case .place(let id) = need.status, let place = places.first(where: { $0.id == id }) else { continue }
                XCTAssertEqual(MeetingPlanPolicy.role(of: place.purpose), need.purpose, "\(intent) \(need.purpose)")
            }
            XCTAssertEqual(needs.first { $0.purpose == .outOfAreaPlace }?.status, .place(id: backup.id), "\(intent)")
            XCTAssertNotEqual(needs.first { $0.purpose == .immediateOutdoor }?.status, .place(id: backup.id), "\(intent)")
        }
    }

    func testDemoAddressLaunchSavesATypedAddressWithoutAPin() async throws {
        XCTAssertNil(DemoLaunch(arguments: ["app", "-demoHousehold", "hh-pine"]).address)
        XCTAssertNil(DemoLaunch(arguments: ["app", "-demoAddress", "arbitrary"]).address)
        let launch = DemoLaunch(arguments: ["app", "-demoHousehold", "hh-pine", "-demoAddress", "resolvable"])
        XCTAssertEqual(launch.address, .resolvable)
        let model = AppModel(store: InMemoryPrivateDataStore())
        await model.useSampleHousehold(SampleHouseholds.pine, demoAddress: launch.address?.location)
        let location = try XCTUnwrap(model.household?.privateLocation)
        XCTAssertEqual(location.addressLine, "500 W 3rd St")
        XCTAssertNil(location.latitude)
        XCTAssertNil(location.longitude)
        XCTAssertEqual(HomeOriginPolicy.decide(location: location, candidates: nil), .unresolved)
        // Without the flag the example family's facts are unchanged.
        let plain = AppModel(store: InMemoryPrivateDataStore())
        await plain.useSampleHousehold(SampleHouseholds.pine)
        XCTAssertEqual(plain.household?.privateLocation, SampleHouseholds.pine.privateLocation)
    }
}
