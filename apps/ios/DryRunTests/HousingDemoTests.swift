import XCTest
import DryRunCore
@testable import DryRun

/// Authored on Linux; must execute with Xcode. Demo switches never constitute native evidence.
@MainActor
final class HousingDemoTests: XCTestCase {
    func testHousingLaunchRequiresFictionalHouseholdAndWhitelistsModels() {
        let isolated = DemoLaunch(arguments: ["app", "-demoHome", "manufactured"])
        XCTAssertFalse(isolated.isActive)
        XCTAssertFalse(isolated.usesInMemoryStore)
        let active = DemoLaunch(arguments: ["app", "-demoHousehold", "hh-oak", "-demoHome", "apartment-complex"])
        XCTAssertTrue(active.usesInMemoryStore)
        XCTAssertEqual(active.homeID, SampleHomes.apartmentComplex.id)
        XCTAssertNil(DemoLaunch(arguments: ["app", "-demoHome", "arbitrary-path"]).homeID)
    }
    func testEachHousingDemoUsesOneCanonicalHomeAcrossHouseholdAndPlan() async throws {
        for home in [SampleHomes.apartmentComplex, .manufactured, .twoStory] {
            let store = InMemoryPrivateDataStore()
            let model = AppModel(store: store)
            await model.useSampleHousehold(SampleHouseholds.oak, demoHome: home)
            XCTAssertEqual(model.home?.id, home.id)
            XCTAssertEqual(model.household?.stableHomeID, home.id)
            XCTAssertEqual(model.household?.housing.floorCount, home.floors.count)
            XCTAssertNil(model.household?.privateLocation)
            XCTAssertNil(model.household?.siteHazards)
            XCTAssertTrue(model.household?.isFictional == true)
            XCTAssertEqual(model.household?.housing.homeType, home.dwellingType ?? (home.id.contains("apartment") ? .apartment : .singleFamily))
            guard case .loaded(let snapshot) = await store.load() else { XCTFail("Missing atomic demo snapshot"); continue }
            XCTAssertEqual(snapshot.home, model.home)
            XCTAssertEqual(snapshot.household, model.household)
        }
    }
}
