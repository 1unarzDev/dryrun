import Foundation
import CoreLocation
import MapKit
import DryRunCore

/// App-layer adapter for Apple local search. It owns the MapKit request and
/// returns plain Sendable values to the view; no query is sent to Dry Run's
/// public API. Search is started only after an explicit user action.
@MainActor
final class AppleMapSearchService {
    private var activeSearch: MKLocalSearch?

    func cancel() {
        activeSearch?.cancel()
        activeSearch = nil
    }

    func search(query: String, region: MapRegionHint?) async throws -> [AppleMapSearchResult] {
        cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let region { request.region = region.mapRegion }
        let search = MKLocalSearch(request: request)
        activeSearch = search
        defer { if activeSearch === search { activeSearch = nil } }
        let response = try await search.start()
        return response.mapItems.compactMap { item in
            let coordinate = item.placemark.coordinate
            guard let c = GeographicCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
            let id = item.placemark.title.map { "\($0)|\(c.latitude)|\(c.longitude)" } ?? "\(c.latitude)|\(c.longitude)"
            let address = [item.placemark.subThoroughfare, item.placemark.thoroughfare,
                           item.placemark.locality, item.placemark.administrativeArea]
                .compactMap { $0 }.joined(separator: " ")
            return AppleMapSearchResult(id: id, name: item.name ?? item.placemark.name ?? trimmed,
                                        coordinate: c, address: address.isEmpty ? nil : address,
                                        category: item.pointOfInterestCategory?.rawValue)
        }
    }
}

@MainActor
final class AppleMapDirectionsService {
    private var activeDirections: MKDirections?

    func cancel() {
        activeDirections?.cancel()
        activeDirections = nil
    }

    func preview(from origin: GeographicCoordinate, to destination: GeographicCoordinate,
                 mode: MapTravelMode) async throws -> MapTravelPreview {
        cancel()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)))
        request.transportType = mode.mapKitType
        let directions = MKDirections(request: request)
        activeDirections = directions
        defer { if activeDirections === directions { activeDirections = nil } }
        let response = try await directions.calculate()
        guard let route = response.routes.first else { throw MapDirectionsError.noRoute }
        let points = route.polyline.points()
        let coordinates = (0..<route.polyline.pointCount).compactMap { index in
            let p = points[index].coordinate
            return GeographicCoordinate(latitude: p.latitude, longitude: p.longitude)
        }
        return MapTravelPreview(distanceMeters: route.distance, expectedTravelTime: route.expectedTravelTime,
                                coordinates: coordinates, mode: mode)
    }
}

enum MapDirectionsError: Error, LocalizedError, Sendable {
    case noRoute
    var errorDescription: String? {
        switch self { case .noRoute: "Apple Maps did not return a route for that mode." }
    }
}

/// Location is optional and deliberately inert until the user taps the
/// recenter or travel-preview action. Opening Help/map never prompts.
@MainActor
final class OptionalLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?
    private(set) var error: Error?
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        authorization = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOneShot() async -> CLLocation? {
        error = nil
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
                self.continuation = continuation
                switch self.manager.authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse:
                    self.manager.requestLocation()
                case .notDetermined:
                    self.manager.requestWhenInUseAuthorization()
                default:
                    self.authorization = self.manager.authorizationStatus
                    continuation.resume(returning: nil)
                    self.continuation = nil
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.continuation?.resume(returning: nil)
                self?.continuation = nil
            }
        })
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
