import Foundation

/// The single rule for whether a portal really sits in the boundary of the space(s) it claims to join.
/// Used by the planner, the validator, and the route audit so they cannot disagree.
///
/// - Shared edge: both outlines within `boundaryContactMeters` of the portal.
/// - Wall between outlines (scans record outlines at inner wall faces): the portal must lie INSIDE the gap
///   (between the two outlines along its normal) and the gap must be a plausible wall: at most the thickness of an
///   explicit wall under the portal (+ contact), or, with no explicit wall, within
///   [`minimumWallThicknessMeters`, `maximumWallThicknessMeters`]. Narrower unexplained gaps are near-touching
///   outlines and never connect.
/// - One-sided (exterior/common/unknown): within contact of the outline, plus half the thickness of an explicit
///   wall under the portal if there is one.
public enum PortalAttachment {
    public struct Result: Sendable, Hashable {
        public var attached: Bool
        public var reason: String?
        /// Distance from the portal centre to each attached space's outline (metres).
        public var centerOffset: [String: Double]
    }

    /// Explicit wall on the portal's floor, roughly parallel, whose band contains the portal centre.
    public static func underlyingWall(_ p: Portal, in home: HomeModel, tolerance tol: GeometryTolerance = .standard) -> WallSegment? {
        let dp = Geometry.normalized(p.b - p.a)
        return home.walls
            .filter { w in
                w.floorID == p.floorID
                    && abs(Geometry.cross(dp, Geometry.normalized(w.b - w.a))) < 0.1
                    && Geometry.distancePointSegment(p.center, w.a, w.b) <= w.thicknessMeters / 2 + tol.boundaryContactMeters
            }
            .min { ($0.thicknessMeters, $0.id) < ($1.thicknessMeters, $1.id) }
    }

    /// Two rooms on the opening's floor that it would join as an ordinary interior connection (the same two-room rule
    /// as `check`), whatever sides are currently recorded. nil means the captured geometry shows at most one room
    /// against the opening: it sits in an outside wall, or the geometry cannot tell. Rooms on both sides mean the
    /// opening cannot be an exterior exit.
    public static func interiorRoomPair(_ p: Portal, in home: HomeModel, tolerance tol: GeometryTolerance = .standard) -> (String, String)? {
        let near = home.spaces
            .filter { $0.floorID == p.floorID && Geometry.distanceToBoundary($0.polygon, p.center) <= tol.scanPortalAttachMeters }
            .map(\.id).sorted()
        guard near.count >= 2 else { return nil }
        for i in near.indices {
            for j in near.indices where j > i {
                var probe = p
                probe.sideA = .space(near[i]); probe.sideB = .space(near[j])
                if check(probe, in: home, tolerance: tol).attached { return (near[i], near[j]) }
            }
        }
        return nil
    }

    /// An exterior side recorded on an opening that the geometry places between two rooms. Never a usable exit: the
    /// planner excludes it and the plan draws it unconfirmed until the household corrects the answer.
    public static func exteriorClaimContradictsGeometry(_ p: Portal, in home: HomeModel, tolerance tol: GeometryTolerance = .standard) -> Bool {
        p.leadsToExterior && interiorRoomPair(p, in: home, tolerance: tol) != nil
    }

    public static func check(_ p: Portal, in home: HomeModel, tolerance tol: GeometryTolerance = .standard) -> Result {
        let spaceIDs = [p.sideA, p.sideB].compactMap { d -> String? in if case .space(let id) = d { return id }; return nil }
        let spaces = spaceIDs.compactMap { home.space($0) }
        guard spaces.count == spaceIDs.count, spaces.allSatisfy({ $0.floorID == p.floorID }) else {
            return Result(attached: false, reason: "space missing or on another floor", centerOffset: [:])
        }
        let wall = underlyingWall(p, in: home, tolerance: tol)
        let points = [p.a, p.b, p.center]
        var offsets: [String: Double] = [:]
        for s in spaces { offsets[s.id] = Geometry.distanceToBoundary(s.polygon, p.center) }

        switch spaces.count {
        case 2:
            let A = spaces[0], B = spaces[1]
            for pt in points {
                let dA = Geometry.distanceToBoundary(A.polygon, pt), dB = Geometry.distanceToBoundary(B.polygon, pt)
                guard let nA = Geometry.closestPointOnBoundary(A.polygon, pt), let nB = Geometry.closestPointOnBoundary(B.polygon, pt) else {
                    return Result(attached: false, reason: "invalid outline", centerOffset: offsets)
                }
                let gap = nA.distance(to: nB)
                // Shared edge: the OUTLINES touch (not merely each within contact of the portal).
                if gap <= tol.boundaryContactMeters && dA <= tol.boundaryContactMeters && dB <= tol.boundaryContactMeters { continue }
                // The portal point must lie between the two outlines, not off to one side.
                guard dA + dB <= gap + tol.boundaryContactMeters else {
                    return Result(attached: false, reason: "portal is not between the two rooms", centerOffset: offsets)
                }
                if let wall {
                    guard gap <= wall.thicknessMeters + tol.boundaryContactMeters else {
                        return Result(attached: false, reason: "rooms are farther apart than wall \(wall.id) is thick", centerOffset: offsets)
                    }
                } else {
                    guard gap >= tol.minimumWallThicknessMeters, gap <= tol.maximumWallThicknessMeters + tol.boundaryContactMeters else {
                        return Result(attached: false, reason: String(format: "%.3f m gap is not a shared edge or a plausible wall", gap), centerOffset: offsets)
                    }
                }
            }
            return Result(attached: true, reason: nil, centerOffset: offsets)
        case 1:
            let allowed = tol.boundaryContactMeters + (wall?.thicknessMeters ?? 0) / 2
            for pt in points where Geometry.distanceToBoundary(spaces[0].polygon, pt) > allowed {
                return Result(attached: false, reason: "not on the outline of \(spaces[0].id)", centerOffset: offsets)
            }
            return Result(attached: true, reason: nil, centerOffset: offsets)
        default:
            return Result(attached: false, reason: "no room side", centerOffset: offsets)
        }
    }
}
