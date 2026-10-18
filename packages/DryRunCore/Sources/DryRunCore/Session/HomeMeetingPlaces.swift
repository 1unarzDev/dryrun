import Foundation

/// A geographic meeting record can supply the named outdoor destination without inventing local coordinates.
/// Egress still stops at a confirmed exterior opening; this link certifies neither the outdoor path nor the site.
public enum HomeMeetingPlaces {
    /// Retain a previously confirmed local landmark as a text-only planning place. This migration
    /// adds no geographic pin or outdoor route and is deterministic for the already-saved facts.
    public static func placesIncludingLocalMeetup(home: HomeModel?, places: [SavedPlace], recordedAt: Date?) -> [SavedPlace] {
        guard let home, !places.contains(where: { $0.homeID == home.id && $0.purpose == .outsideMeetingPoint }),
              let local = home.meetingPoint, local.verification == .verified, local.savedPlaceID == nil,
              hasNamedLandmark(local) else { return places }
        // Legacy households have no update timestamp. A fixed epoch preserves reproducible snapshots;
        // it is migration provenance, never evidence that the family reviewed the place at that time.
        let recordedAt = recordedAt ?? Date(timeIntervalSince1970: 0)
        return places + [SavedPlace(id: migratedPlaceID(home: home, annotation: local), homeID: home.id, purpose: .outsideMeetingPoint,
            label: local.label, findingInstructions: local.note, provenance: home.isFictional || home.source == .sample ? .fixture : .userSelected,
            createdAt: recordedAt, updatedAt: recordedAt)]
    }

    /// The canvas edits the linked place's name/instructions, not a disposable copy. Apply only
    /// those changed fields, retaining geographic/source/contact data and unrelated destinations.
    /// A replacement capture/geometry is not an instruction to delete a neighborhood plan.
    public static func placesAfterHomeEdit(previous: HomeModel?, updated: HomeModel, places: [SavedPlace], editedAt: Date) -> [SavedPlace] {
        var candidate = places
        if let previous, previous.id == updated.id, isContinuingLayout(previous, updated) {
            for old in previous.annotations where old.kind == .outsideMeetingPoint {
                guard let placeID = old.savedPlaceID,
                      let index = candidate.firstIndex(where: { $0.id == placeID && $0.homeID == updated.id && $0.purpose == .outsideMeetingPoint }) else { continue }
                if let edited = updated.annotations.first(where: { $0.kind == .outsideMeetingPoint && $0.savedPlaceID == placeID }) {
                    if edited.label != old.label || edited.note != old.note {
                        candidate[index].label = edited.label
                        candidate[index].findingInstructions = edited.note
                        candidate[index].updatedAt = editedAt
                    }
                } else if old.spaceID.map({ updated.space($0) == nil }) != true {
                    // Removing this linked marker explicitly removes its selected destination. A marker
                    // lost with a deleted room instead loses local positioning, not the saved address.
                    candidate.remove(at: index)
                }
            }
        }
        return placesIncludingLocalMeetup(home: updated, places: candidate, recordedAt: editedAt)
    }

    private static func hasNamedLandmark(_ annotation: Annotation) -> Bool {
        let label = annotation.label.trimmingCharacters(in: .whitespacesAndNewlines)
        // These machine-generated legacy placeholders are display types, not family-selected names.
        return !label.isEmpty && label != AnnotationKind.outsideMeetingPoint.rawValue && label != "enum.outsideMeetingPoint"
    }

    private static func migratedPlaceID(home: HomeModel, annotation: Annotation) -> String {
        "indoor-meetup|\(home.id)|\(annotation.id)"
    }

    private static func isContinuingLayout(_ previous: HomeModel, _ updated: HomeModel) -> Bool {
        guard previous.source == updated.source, previous.sourceCaptureFrameID == updated.sourceCaptureFrameID else { return false }
        // Current scans have frame IDs. For a manual/legacy layout, retain geographic plans when
        // the complete set of rooms was replaced instead of mistaking missing markers for deletion.
        return previous.spaces.isEmpty || !Set(previous.spaces.map(\.id)).isDisjoint(with: updated.spaces.map(\.id))
    }

    public static func synchronize(_ home: HomeModel, places: [SavedPlace]) -> HomeModel {
        var candidate = home
        let near = places.filter { $0.homeID == home.id && $0.purpose == .outsideMeetingPoint }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }.first
        if let near {
            var annotation = home.meetingPoint ?? Annotation(id: "geographic-meetup", kind: .outsideMeetingPoint, label: near.label)
            if annotation.savedPlaceID != near.id && near.id != migratedPlaceID(home: home, annotation: annotation) {
                // A new geographic destination is not at the old landmark's indoor metre position.
                annotation.position = nil; annotation.floorID = nil; annotation.spaceID = nil
            }
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
