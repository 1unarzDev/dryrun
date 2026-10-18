import Foundation

/// Plain map panels shared by live previews, snapshot export and missing-image reporting.
public struct PlanMapExtent: Sendable, Hashable, Identifiable {
    public let id: String
    public let homeCoordinate: GeographicCoordinate?
    public let places: [PlanMapSelection.Entry]
    public func title(neighborhood: String) -> String { id == "neighborhood" ? neighborhood : places.first?.place.label ?? neighborhood }
}

public extension PlanMapSelection {
    static func extents(homeCoordinate: GeographicCoordinate?, places: [SavedPlace]) -> [PlanMapExtent] {
        let selected = panels(homeCoordinate: homeCoordinate, places: places)
        guard selected.origin != nil else { return [] }
        var extents: [PlanMapExtent] = []
        if homeCoordinate != nil || !selected.local.isEmpty {
            extents.append(PlanMapExtent(id: "neighborhood", homeCoordinate: homeCoordinate, places: selected.local))
        }
        extents += selected.distant.map { PlanMapExtent(id: "place|\($0.place.id)", homeCoordinate: nil, places: [$0]) }
        return extents
    }

    /// Missing one inset is a partial failure even when a different snapshot succeeded.
    static func missingExtents(homeCoordinate: GeographicCoordinate?, places: [SavedPlace], renderedExtentIDs: Set<String>) -> [PlanMapExtent] {
        extents(homeCoordinate: homeCoordinate, places: places).filter { !renderedExtentIDs.contains($0.id) }
    }
}

/// A route is bound only to its endpoints, so editing another saved resource does not clear it.
public struct MapPlanningRouteEndpoints: Sendable, Hashable {
    public enum Reference: Sendable, Hashable {
        case home(GeographicCoordinate)
        case savedPlace(id: String, coordinate: GeographicCoordinate)
        /// A requested GPS fix or an unsaved Apple suggestion has no private record to invalidate.
        case external
        fileprivate func matches(home: GeographicCoordinate?, places: [SavedPlace]) -> Bool {
            switch self {
            case .home(let recorded): return recorded == home
            case .savedPlace(let id, let coordinate): return places.contains { $0.id == id && $0.coordinate == coordinate }
            case .external: return true
            }
        }
    }
    public let origin: Reference
    public let destination: Reference
    public init(origin: Reference, destination: Reference) { self.origin = origin; self.destination = destination }
    public func isCurrent(homeCoordinate: GeographicCoordinate?, places: [SavedPlace]) -> Bool {
        origin.matches(home: homeCoordinate, places: places) && destination.matches(home: homeCoordinate, places: places)
    }
}
