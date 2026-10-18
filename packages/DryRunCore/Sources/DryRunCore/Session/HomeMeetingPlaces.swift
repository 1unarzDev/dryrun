import Foundation

/// A geographic meeting record can supply the named outdoor destination without inventing local coordinates.
/// Egress still stops at a confirmed exterior opening; this link certifies neither the outdoor path nor the site.
public enum HomeMeetingPlaces {
    public static func synchronize(_ home: HomeModel, places: [SavedPlace]) -> HomeModel {
        var candidate = home
        let near = places.filter { $0.homeID == home.id && $0.purpose == .outsideMeetingPoint }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }.first
        if let near {
            var annotation = home.meetingPoint ?? Annotation(id: "geographic-meetup", kind: .outsideMeetingPoint, label: near.label)
            annotation.savedPlaceID = near.id
            annotation.label = near.label
            annotation.note = near.findingInstructions
            annotation.verification = .verified
            candidate.annotations.removeAll { $0.kind == .outsideMeetingPoint }
            candidate.annotations.append(annotation)
        } else {
            // Keep independent household-authored local annotations. Only remove records actually linked here.
            candidate.annotations.removeAll { $0.kind == .outsideMeetingPoint && $0.savedPlaceID != nil }
        }
        return candidate
    }
}
