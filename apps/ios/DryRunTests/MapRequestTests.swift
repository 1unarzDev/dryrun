import XCTest
import DryRunCore
@testable import DryRun

@MainActor
private final class ControlledMapSearch: MapSearching {
    private(set) var query: String?
    private(set) var cancelCount = 0
    private var started: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<[AppleMapSearchResult], Error>?
    func cancel() { cancelCount += 1 } // Deliberately allows a late SDK response after cancellation.
    func search(query: String, region: MapRegionHint?) async throws -> [AppleMapSearchResult] {
        self.query = query; started?.resume(); started = nil
        return try await withCheckedThrowingContinuation { response = $0 }
    }
    func waitForStart() async { if query == nil { await withCheckedContinuation { started = $0 } } }
    func finish(name: String, latitude: Double = 32.2) {
        response?.resume(returning: [AppleMapSearchResult(id: name, name: name,
            coordinate: GeographicCoordinate(latitude: latitude, longitude: -98.2)!, address: "Example road", category: nil)])
        response = nil
    }
}

/// Requires a native build, but uses no network, GPS or real household information.
@MainActor
final class MapRequestTests: XCTestCase {
    func testParallelCategoriesDoNotCancelEachOtherAndOldHomeResultsCannotReplaceNewHome() async {
        let services = (0..<6).map { _ in ControlledMapSearch() }
        var index = 0
        let discovery = NearbyDiscovery(makeService: { let service = services[index]; index += 1; return service })
        let old = Task { await discovery.search(region: MapRegionHint(latitude: 32.2, longitude: -98.2, spanLatitude: 0.1, spanLongitude: 0.1), locale: "en") }
        for service in services.prefix(3) { await service.waitForStart(); XCTAssertEqual(service.cancelCount, 0) }
        XCTAssertEqual(services.prefix(3).compactMap(\.query), ["hospital", "pharmacy", "grocery"])
        discovery.cancel()
        let current = Task { await discovery.search(region: MapRegionHint(latitude: 32.3, longitude: -98.2, spanLatitude: 0.1, spanLongitude: 0.1), locale: "en") }
        for (offset, service) in services.suffix(3).enumerated() { await service.waitForStart(); service.finish(name: "New \(offset)", latitude: 32.3) }
        await current.value
        let newResults = discovery.results
        XCTAssertEqual(newResults.count, 3)
        for (offset, service) in services.prefix(3).enumerated() { service.finish(name: "Old \(offset)") }
        await old.value
        XCTAssertEqual(discovery.results, newResults)
        XCTAssertFalse(discovery.isLoading)
    }

    func testCancelledBatchCannotRepopulateAndDuplicateSuggestionsHaveOneMarker() async {
        let services = (0..<3).map { _ in ControlledMapSearch() }
        var index = 0
        let discovery = NearbyDiscovery(makeService: { let service = services[index]; index += 1; return service })
        let pending = Task { await discovery.search(region: MapRegionHint(latitude: 32.2, longitude: -98.2, spanLatitude: 0.1, spanLongitude: 0.1), locale: "en") }
        for service in services { await service.waitForStart() }
        discovery.cancel()
        for service in services { service.finish(name: "Late duplicate") }
        await pending.value
        XCTAssertTrue(discovery.results.isEmpty)
        XCTAssertFalse(discovery.isLoading)
    }
}

extension MapRequestTests {
    func testOnePlaceFoundInSeveralCategoriesHasOneSuggestion() async {
        let services = (0..<3).map { _ in ControlledMapSearch() }
        var index = 0
        let discovery = NearbyDiscovery(makeService: { let service = services[index]; index += 1; return service })
        let pending = Task { await discovery.search(region: MapRegionHint(latitude: 32.2, longitude: -98.2, spanLatitude: 0.1, spanLongitude: 0.1), locale: "en") }
        for service in services { await service.waitForStart(); service.finish(name: "One clinic") }
        await pending.value
        XCTAssertEqual(discovery.results.count, 1)
    }
}
