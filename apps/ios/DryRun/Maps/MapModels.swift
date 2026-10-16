import Foundation
import Observation
import CoreLocation
import MapKit
import DryRunCore

/// Stable, namespaced IDs keep directory records, Apple results, and private
/// places distinct when map and list selection are synchronized.
enum MapSelectionID {
    static func directory(_ id: String) -> String { "directory:\(id)" }
    static func apple(_ id: String) -> String { "apple:\(id)" }
    static func saved(_ id: String) -> String { "saved:\(id)" }
}

struct MapRegionHint: Sendable, Hashable {
    var center: GeographicCoordinate
    var spanLatitude: Double
    var spanLongitude: Double

    init(latitude: Double, longitude: Double, spanLatitude: Double, spanLongitude: Double) {
        guard let center = GeographicCoordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("Map region catalog contains an invalid geographic coordinate")
        }
        self.init(center: center, spanLatitude: spanLatitude, spanLongitude: spanLongitude)
    }

    init(center: GeographicCoordinate, spanLatitude: Double, spanLongitude: Double) {
        self.center = center
        self.spanLatitude = max(0.05, min(spanLatitude, 180))
        self.spanLongitude = max(0.05, min(spanLongitude, 360))
    }

    var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                           span: MKCoordinateSpan(latitudeDelta: spanLatitude, longitudeDelta: spanLongitude))
    }
}

enum MapRegionCatalog {
    /// Deliberate browsing frames. They are approximate county context and
    /// never used as a resource location or as an alert boundary.
    static let fallback: [String: MapRegionHint] = [
        "tx-statewide": MapRegionHint(latitude: 31.9686, longitude: -99.9018, spanLatitude: 12, spanLongitude: 18),
        "48093": MapRegionHint(latitude: 31.90, longitude: -98.57, spanLatitude: 0.9, spanLongitude: 1.1),
        "48133": MapRegionHint(latitude: 32.40, longitude: -98.83, spanLatitude: 0.9, spanLongitude: 1.1),
        "48143": MapRegionHint(latitude: 32.22, longitude: -98.20, spanLatitude: 0.8, spanLongitude: 1.0),
        "48221": MapRegionHint(latitude: 32.44, longitude: -97.79, spanLatitude: 0.8, spanLongitude: 1.0),
        "48237": MapRegionHint(latitude: 33.24, longitude: -98.16, spanLatitude: 0.9, spanLongitude: 1.0),
        "48363": MapRegionHint(latitude: 32.76, longitude: -98.30, spanLatitude: 1.0, spanLongitude: 1.2),
        "48425": MapRegionHint(latitude: 32.23, longitude: -97.78, spanLatitude: 0.7, spanLongitude: 0.9),
        "48429": MapRegionHint(latitude: 32.75, longitude: -98.90, spanLatitude: 1.0, spanLongitude: 1.2),
        "48503": MapRegionHint(latitude: 33.18, longitude: -98.74, spanLatitude: 1.0, spanLongitude: 1.2),
        "48059": MapRegionHint(latitude: 32.28, longitude: -99.41, spanLatitude: 1.0, spanLongitude: 1.2),
        "48251": MapRegionHint(latitude: 32.46, longitude: -97.38, spanLatitude: 0.9, spanLongitude: 1.0),
        "48367": MapRegionHint(latitude: 32.76, longitude: -97.80, spanLatitude: 0.9, spanLongitude: 1.1),
        "48439": MapRegionHint(latitude: 32.77, longitude: -97.29, spanLatitude: 1.1, spanLongitude: 1.2)
    ]

    static func hint(for region: RegionInfo?) -> MapRegionHint {
        if let region,
           let lat = region.mapCenterLatitude,
           let lon = region.mapCenterLongitude,
           let coordinate = GeographicCoordinate(latitude: lat, longitude: lon) {
            return MapRegionHint(center: coordinate,
                                 spanLatitude: region.mapSpanLatitude ?? 0.8,
                                 spanLongitude: region.mapSpanLongitude ?? 1.0)
        }
        return fallback[region?.id ?? "tx-statewide"] ?? fallback["tx-statewide"] ?? MapRegionHint(latitude: 0, longitude: 0, spanLatitude: 1, spanLongitude: 1)
    }
}

/// A shared, deterministic resource snapshot for Help's list, map, and plan
/// generation. Bundled data is immediately available; a validated cached or
/// refreshed pack overlays it by resource ID. Browsing a county does not alter
/// the household's region.
@MainActor
@Observable
final class RegionalResourcesStore {
    private let bundled: ContentLibrary
    private let client: PublicAPIClient
    var overrides: [String: RegionPack] = [:]
    private var generation = 0
    private(set) var selectedRegionID: String
    private(set) var freshness: PublicAPIClient.Freshness = .unavailable
    private(set) var isRefreshing = false

    init(content: ContentLibrary, client: PublicAPIClient, regionID: String) {
        bundled = content
        self.client = client
        selectedRegionID = regionID
    }

    var regionIDs: [String] {
        var ids = bundled.regionPacks.flatMap(\.regions).map(\.id)
        for pack in overrides.values { ids.append(contentsOf: pack.regions.map(\.id)) }
        return Array(Set(ids)).sorted { lhs, rhs in
            if lhs == "tx-statewide" { return true }
            if rhs == "tx-statewide" { return false }
            return lhs < rhs
        }
    }

    var region: RegionInfo? {
        regionInfo(for: selectedRegionID)
    }

    func regionInfo(for regionID: String) -> RegionInfo? {
        overrides.values.lazy.flatMap(\.regions).first(where: { $0.id == regionID })
            ?? bundled.region(regionID)
    }

    var resources: [PublicResource] {
        resources(for: selectedRegionID)
    }

    /// Returns the current validated snapshot for an explicit region without changing the user's browsing county.
    func resources(for regionID: String) -> [PublicResource] {
        var byID: [String: PublicResource] = [:]
        // Keep the old ContentLibrary order while allowing a newer validated
        // pack to replace obsolete records with the same ID.
        for resource in bundled.resources(forRegion: regionID) { byID[resource.id] = resource }
        for pack in overrides.values {
            for resource in pack.resources where resource.regionIDs.contains(regionID) || resource.regionIDs.contains("tx-statewide") {
                byID[resource.id] = resource
            }
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func select(regionID: String) {
        guard regionIDs.contains(regionID), regionID != selectedRegionID else { return }
        selectedRegionID = regionID
        generation += 1
    }

    func refresh() async {
        let regionID = selectedRegionID
        generation += 1
        let ticket = generation
        isRefreshing = true
        defer { if ticket == generation { isRefreshing = false } }
        let (pack, result) = await client.refreshRegionPack(regionID: regionID)
        guard ticket == generation, selectedRegionID == regionID else { return }
        freshness = result
        if let pack { overrides[pack.packID] = pack }
    }

    func hint() -> MapRegionHint { MapRegionCatalog.hint(for: region) }

    func source(_ id: String) -> SourceRef? {
        overrides.values.lazy.flatMap(\.sources).first(where: { $0.id == id })
            ?? bundled.regionPacks.lazy.flatMap(\.sources).first(where: { $0.id == id })
            ?? bundled.source(id)
    }

    func regionName(_ id: String) -> String {
        if id == "tx-statewide" { return "Texas statewide" }
        return overrides.values.lazy.flatMap(\.regions).first(where: { $0.id == id })?.name
            ?? bundled.region(id)?.name
            ?? "County \(id)"
    }
}

struct AppleMapSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coordinate: GeographicCoordinate
    let address: String?
    let category: String?
    var selectionID: String { MapSelectionID.apple(id) }
}

enum MapTravelMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case walking, driving, transit
    var id: String { rawValue }
    var title: String {
        switch self { case .walking: "Walk"; case .driving: "Drive"; case .transit: "Transit" }
    }
    var mapKitType: MKDirectionsTransportType {
        switch self { case .walking: .walking; case .driving: .automobile; case .transit: .transit }
    }
}

struct MapTravelPreview: Sendable, Hashable {
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let coordinates: [GeographicCoordinate]
    let mode: MapTravelMode
}
