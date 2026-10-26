import XCTest
import DryRunCore
@testable import DryRun

@MainActor
private final class ControlledDirections: MapDirectionsPlanning {
    struct Request {
        let origin: GeographicCoordinate
        let destination: GeographicCoordinate
        let mode: MapTravelMode
        let response: CheckedContinuation<MapTravelPreview, Error>
    }
    var requests: [Request] = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    func cancel() { } // Deliberately return late responses after SDK cancellation.
    func preview(from origin: GeographicCoordinate, to destination: GeographicCoordinate, mode: MapTravelMode) async throws -> MapTravelPreview {
        try await withCheckedThrowingContinuation { response in
            requests.append(Request(origin: origin, destination: destination, mode: mode, response: response))
            waiting.removeValue(forKey: requests.count)?.resume()
        }
    }
    func waitForRequest(_ count: Int) async {
        if requests.count < count { await withCheckedContinuation { waiting[count] = $0 } }
    }
    func finish(_ index: Int) {
        let request = requests[index]
        request.response.resume(returning: MapTravelPreview(distanceMeters: 100, expectedTravelTime: 60,
            coordinates: [request.origin, request.destination], mode: request.mode))
    }
}

@MainActor
private final class ControlledOrigin {
    var response: CheckedContinuation<GeographicCoordinate?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func resolve() async -> GeographicCoordinate? {
        await withCheckedContinuation { response = $0; started?.resume(); started = nil }
    }
    func waitForStart() async { if response == nil { await withCheckedContinuation { started = $0 } } }
}

/// No Apple services are called. These tests exercise ignored cancellation and delayed GPS completion.
@MainActor
final class MapDirectionsRequestTests: XCTestCase {
    private let home = GeographicCoordinate(latitude: 32.2, longitude: -98.2)!
    private let clinic = GeographicCoordinate(latitude: 32.21, longitude: -98.21)!
    private let pharmacy = GeographicCoordinate(latitude: 32.22, longitude: -98.22)!

    func testDismissedDestinationCannotReplaceNewDestinationWithLateRoute() async {
        let service = ControlledDirections()
        // Use one shared adapter, as the actual map does.
        let current = MapRoutePreviewModel(service: service)
        let old = current.start(destinationID: "clinic", destination: clinic, mode: .walking) { self.home }
        await service.waitForRequest(1)
        XCTAssertTrue(current.isLoading)
        current.cancel()
        XCTAssertFalse(current.isLoading)
        let replacement = current.start(destinationID: "pharmacy", destination: pharmacy, mode: .driving) { self.home }
        await service.waitForRequest(2)
        service.finish(1); await replacement.value
        XCTAssertEqual(current.result?.destinationID, "pharmacy")
        XCTAssertEqual(current.result?.preview.mode, .driving)
        service.finish(0); await old.value
        XCTAssertEqual(current.result?.destinationID, "pharmacy")
        XCTAssertFalse(current.isLoading)
    }

    func testCancelledGPSResolutionCannotStartDirectionsOrKeepPreviewDisabled() async {
        let service = ControlledDirections(), origin = ControlledOrigin()
        let model = MapRoutePreviewModel(service: service)
        let pending = model.start(destinationID: "clinic", destination: clinic, mode: .walking) { await origin.resolve() }
        await origin.waitForStart()
        model.cancel(clearPreview: true)
        XCTAssertFalse(model.isLoading)
        origin.response?.resume(returning: home); origin.response = nil
        await pending.value
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertNil(model.result)
        XCTAssertNil(model.errorKey)
    }

    func testMissingOriginReportsFailureAndAllowsAnExplicitRetry() async {
        let service = ControlledDirections()
        let current = MapRoutePreviewModel(service: service)
        await current.start(destinationID: "clinic", destination: clinic, mode: .walking) { nil }.value
        XCTAssertFalse(current.isLoading)
        XCTAssertEqual(current.errorKey, "originMissing")
        XCTAssertTrue(service.requests.isEmpty)
        let retry = current.start(destinationID: "clinic", destination: clinic, mode: .transit) { self.home }
        await service.waitForRequest(1)
        service.finish(0); await retry.value
        XCTAssertEqual(current.result?.preview.mode, .transit)
        XCTAssertNil(current.errorKey)
    }
}
