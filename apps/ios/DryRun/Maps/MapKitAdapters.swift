import Foundation
import Observation
import CoreLocation
import MapKit
import DryRunCore

/// App-layer adapter for Apple local search. It owns the MapKit request and
/// returns plain Sendable values to the view; no query is sent to Dry Run's
/// public API. Search is started only after an explicit user action.
@MainActor
protocol MapSearching: AnyObject, Sendable {
    func cancel()
    func search(query: String, region: MapRegionHint?) async throws -> [AppleMapSearchResult]
}

@MainActor
final class AppleMapSearchService: MapSearching {
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
                                        category: item.pointOfInterestCategory?.rawValue, phone: item.phoneNumber, website: item.url?.absoluteString)
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
// @preconcurrency: the manager is created on the main actor, so Core Location calls this delegate on the main thread.
final class OptionalLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
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

/// Each category has its own adapter: a cancel-previous request cannot cancel a sibling category.
@MainActor
@Observable
final class NearbyDiscovery {
    var enabled = true
    private(set) var results: [AppleMapSearchResult] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = 0
    private var services: [any MapSearching] = []
    private let makeService: @MainActor () -> any MapSearching
    init(makeService: @escaping @MainActor () -> any MapSearching = { AppleMapSearchService() }) { self.makeService = makeService }
    func cancel(clearResults: Bool = false) { generation += 1; services.forEach { $0.cancel() }; services = []; isLoading = false; if clearResults { results = []; error = nil } }
    func search(region: MapRegionHint, locale: String) async {
        cancel(); guard enabled else { return }
        generation += 1; let ticket = generation
        isLoading = true; error = nil
        let queries = ["hospital", "pharmacy", "grocery"]
        services = queries.map { _ in makeService() }
        let requests = services
        let found = await withTaskGroup(of: (Int, [AppleMapSearchResult]?).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask { @MainActor in (index, try? await requests[index].search(query: query, region: region)) }
            }
            var values: [(Int, [AppleMapSearchResult]?)] = []
            for await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }
        guard ticket == generation else { return }
        isLoading = false
        let center = region.center.clLocation
        let maxDistance = region.spanLatitude * 111000 * 0.8
        var seen = Set<String>()
        results = found.flatMap { pair in
            (pair.1 ?? []).filter { center.distance(from: $0.coordinate.clLocation) <= maxDistance }
                .sorted { center.distance(from: $0.coordinate.clLocation) < center.distance(from: $1.coordinate.clLocation) }
                .prefix(3).map { result in
                    AppleMapSearchResult(id: result.id, name: result.name, coordinate: result.coordinate, address: result.address,
                                         category: queries[pair.0], phone: result.phone, website: result.website)
                }
        }.filter { result in
            // MapKit can return the same place for several category queries.
            let key = "\(result.name.lowercased())|\(Int(result.coordinate.latitude * 10000))|\(Int(result.coordinate.longitude * 10000))"
            return seen.insert(key).inserted
        }
        if found.allSatisfy({ $0.1 == nil }) {
            error = locale == "es" ? "La búsqueda de Apple no está disponible. Los lugares guardados siguen disponibles." : locale == "vi" ? "Không thể tìm bằng Apple. Các địa điểm đã lưu vẫn dùng được." : "Apple search is unavailable. Saved places remain available."
        }
    }
}

struct AddressSuggestion: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

/// Address input is independent of GPS. The app sends this query only to Apple.
@MainActor
@Observable
final class AddressCompletionService: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var activeResolution: MKLocalSearch?
    private(set) var suggestions: [AddressSuggestion] = []
    private(set) var failed = false
    private var generation = 0
    override init() {
        super.init(); completer.delegate = self; completer.resultTypes = .address
    }
    func update(_ query: String) { generation += 1; suggestions = []; failed = false; completer.queryFragment = query }
    func cancel() { generation += 1; completer.cancel(); activeResolution?.cancel(); activeResolution = nil; suggestions = [] }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(6).map { AddressSuggestion(id: UUID(), title: $0.title, subtitle: $0.subtitle, completion: $0) }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { failed = true }
    func resolve(_ suggestion: AddressSuggestion) async throws -> PrivateLocation {
        generation += 1; let ticket = generation
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        activeResolution?.cancel(); activeResolution = search
        let timeout = Task { @MainActor in do { try await Task.sleep(for: .seconds(8)); search.cancel() } catch { } }
        defer { timeout.cancel(); if activeResolution === search { activeResolution = nil } }
        let response = try await search.start()
        guard ticket == generation, let placemark = response.mapItems.first?.placemark else { throw CancellationError() }
        return PrivateLocation(addressLine: [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", "),
                               latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude,
                               city: placemark.locality, administrativeArea: placemark.administrativeArea,
                               postalCode: placemark.postalCode, countryCode: placemark.isoCountryCode)
    }
}
