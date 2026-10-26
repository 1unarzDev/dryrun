import Foundation

/// Current recorded facts for an interior tornado shelter candidate, shared by review and rehearsal routing.
/// This is a household planning choice, not a structural assessment or an engineered-safe-room certification.
public enum ShelterSuitability {
    /// Facts that must hold before accepting an affirmative household confirmation. A window remains exposure
    /// even when it is proposed, inoperable or rejected as an escape option.
    public static func canConfirm(roomID: String, in home: HomeModel) -> Bool {
        guard home.dwellingType != .manufacturedHome, home.spaces.filter({ $0.id == roomID }).count == 1,
              let room = home.space(roomID), room.geometryNeedsReview != true,
              Geometry.isSimplePolygon(room.polygon),
              home.floors.filter({ $0.id == room.floorID }).count == 1,
              let floor = home.floors.first(where: { $0.id == room.floorID }),
              floor.level == home.floors.map(\.level).min() else { return false }
        switch floor.exteriorGrade {
        case .ground, .belowGround, .walkout: break
        case nil:
            // Retain the documented legacy manual/sample ground interpretation. A captured story or an
            // upper floor with missing exterior grade never establishes a suitable floor.
            guard home.source != .roomPlanScan, Graph.isGround(floor, .standard) else { return false }
        case .unknown, .aboveGround: return false
        }
        return !home.portals.contains {
            $0.kind == .window && ($0.sideA == .space(roomID) || $0.sideB == .space(roomID))
        }
    }

    /// Both the explicit room answer and its selected, verified marker are required. Historical evidence alone
    /// cannot override a newly unknown floor, a lower recorded level, a window or an unreviewed correction.
    public static func isConfirmed(roomID: String, in home: HomeModel) -> Bool {
        guard canConfirm(roomID: roomID, in: home), let room = home.space(roomID),
              room.interiorNoWindowsConfirmed.confirmedValue == true else { return false }
        return home.annotations.contains {
            $0.kind == .tornadoShelterCandidate && $0.spaceID == roomID && $0.verification == .verified
                && ($0.floorID == nil || $0.floorID == room.floorID)
        }
    }

    public static func confirmedRoom(in home: HomeModel) -> Space? {
        home.spaces.sorted { $0.id < $1.id }.first { isConfirmed(roomID: $0.id, in: home) }
    }
}
