import Foundation

/// Keeps the family's coordinate-bearing meeting destinations ahead of optional resource pins.
/// Original document ordinals survive prioritization so map symbols still match the text plan.
public enum PlanMapSelection {
    /// One numbering for every view: near-home meetup first, then the backup meetup, then other places.
    /// The text list, map markers and PDF key all number places in this order.
    public static func displayOrder(_ places: [SavedPlace]) -> [SavedPlace] {
        func priority(_ p: SavedPlace) -> Int {
            switch p.purpose { case .outsideMeetingPoint: 0; case .backupMeetingPlace: 1; default: 2 }
        }
        return places.sorted { (priority($0), $0.id) < (priority($1), $1.id) }
    }
    public struct Entry: Sendable, Hashable {
        public let number: Int
        public let place: SavedPlace
    }
    public struct Panels: Sendable, Hashable {
        public let origin: GeographicCoordinate?
        public let local: [Entry]
        public let distant: [Entry]
    }
    public static func panels(homeCoordinate: GeographicCoordinate?, places: [SavedPlace], localLimit: Int = 6, distantLimit: Int = 2) -> Panels {
        let entries = places.enumerated().compactMap { index, place in place.coordinate == nil ? nil : Entry(number: index + 1, place: place) }
        func priority(_ entry: Entry) -> Int {
            switch entry.place.purpose { case .outsideMeetingPoint: 0; case .backupMeetingPlace: 1; default: 2 }
        }
        let ordered = entries.sorted { (priority($0), $0.place.id) < (priority($1), $1.place.id) }
        let origin = homeCoordinate ?? ordered.first?.place.coordinate
        guard let origin else { return Panels(origin: nil, local: [], distant: []) }
        func local(_ entry: Entry) -> Bool {
            guard let coordinate = entry.place.coordinate else { return false }
            return distance(origin, coordinate) <= 50000
        }
        // A household can retain more than one record of either meeting purpose. Do not silently
        // omit any selected meeting marker merely because optional-resource limits are reached.
        func bounded(_ entries: [Entry], limit: Int) -> [Entry] {
            let meeting = entries.filter { priority($0) < 2 }
            return meeting + entries.filter { priority($0) == 2 }.prefix(max(0, limit - meeting.count))
        }
        return Panels(origin: origin, local: bounded(ordered.filter(local), limit: localLimit),
                      distant: bounded(ordered.filter { !local($0) }, limit: distantLimit))
    }
    private static func distance(_ a: GeographicCoordinate, _ b: GeographicCoordinate) -> Double {
        let radians = Double.pi / 180
        let latitude = (b.latitude - a.latitude) * radians
        let longitude = (b.longitude - a.longitude) * radians
        let h = pow(sin(latitude / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(longitude / 2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
