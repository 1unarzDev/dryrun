import Foundation

/// Canonical wall gaps used by native render adapters. Presentation only; routes still use portal validation.
public enum HomeRenderGeometry {
    public static func wallSegments(_ home: HomeModel) -> [WallSegment] {
        ManualLayout.derivedWalls(home).flatMap { wall -> [WallSegment] in
            let delta = wall.b - wall.a, length = delta.length
            guard length > 0 else { return [] }
            let axis = delta * (1 / length)
            var cuts: [(Double, Double)] = []
            for portal in home.portals where portal.floorID == wall.floorID {
                // Both endpoints must lie in the same wall band; an unrelated nearby doorway cannot cut this wall.
                let band = max(wall.thicknessMeters / 2 + 0.02, 0.08)
                guard Geometry.distancePointSegment(portal.a, wall.a, wall.b) <= band,
                      Geometry.distancePointSegment(portal.b, wall.a, wall.b) <= band else { continue }
                let a = Geometry.dot(portal.a - wall.a, axis), b = Geometry.dot(portal.b - wall.a, axis)
                cuts.append((max(0, min(a, b)), min(length, max(a, b))))
            }
            var cursor = 0.0, segments: [WallSegment] = []
            for (start, end) in cuts.sorted(by: { $0.0 < $1.0 }) {
                if start > cursor { segments.append(WallSegment(id: "\(wall.id)-\(segments.count)", floorID: wall.floorID,
                    a: wall.a + axis * cursor, b: wall.a + axis * start, thicknessMeters: wall.thicknessMeters)) }
                cursor = max(cursor, end)
            }
            if cursor < length { segments.append(WallSegment(id: "\(wall.id)-\(segments.count)", floorID: wall.floorID,
                a: wall.a + axis * cursor, b: wall.b, thicknessMeters: wall.thicknessMeters)) }
            return segments
        }
    }
}
