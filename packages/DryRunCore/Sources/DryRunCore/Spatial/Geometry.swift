import Foundation

/// Named, unit-aware tolerances (metres). Nothing is snapped or rounded; tolerances only decide
/// whether two measured things are "the same place" for a specific question.
public struct GeometryTolerance: Sendable, Hashable {
    /// Numerical noise floor for intersection math.
    public var epsilon: Double = 1e-9
    /// Max distance for a portal endpoint to count as lying on a space boundary (validator).
    public var boundaryContactMeters: Double = 0.05
    /// A path may only cross a wall inside a portal span shrunk by this margin at each end.
    public var portalSpanMarginMeters: Double = 0.05
    /// Distance from a portal centre to its approach points inside each adjoining space.
    public var portalApproachMeters: Double = 0.45
    /// Distance a scanned door/opening may sit from a room boundary and still be proposed as attached.
    public var scanPortalAttachMeters: Double = 0.35
    /// Scanned duplicate portals (same door reported by two rooms) closer than this are merged.
    public var scanDuplicatePortalMeters: Double = 0.30
    /// Floors at or below this elevation (and level 0) count as ground for exits.
    public var groundElevationMeters: Double = 1.0

    public init() {}
    public static let standard = GeometryTolerance()
}

public enum Geometry {
    public static func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
    public static func dot(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.x + a.y * b.y }

    /// Signed area (positive = counter-clockwise).
    public static func signedArea(_ poly: [Vec2]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    public static func centroid(_ poly: [Vec2]) -> Vec2 {
        let area = signedArea(poly)
        guard abs(area) > 1e-12 else {
            let n = Double(max(poly.count, 1))
            return Vec2(poly.reduce(0) { $0 + $1.x } / n, poly.reduce(0) { $0 + $1.y } / n)
        }
        var cx = 0.0, cy = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let f = a.x * b.y - b.x * a.y
            cx += (a.x + b.x) * f
            cy += (a.y + b.y) * f
        }
        return Vec2(cx / (6 * area), cy / (6 * area))
    }

    /// Even-odd point-in-polygon. Points on the boundary are reported as outside.
    public static func contains(_ poly: [Vec2], _ p: Vec2, tolerance: Double = 1e-9) -> Bool {
        guard poly.count >= 3 else { return false }
        if distanceToBoundary(poly, p) <= tolerance { return false }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func edges(_ poly: [Vec2]) -> [(Vec2, Vec2)] {
        guard poly.count >= 2 else { return [] }
        return poly.indices.map { (poly[$0], poly[($0 + 1) % poly.count]) }
    }

    public static func distancePointSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let len2 = dot(ab, ab)
        guard len2 > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, dot(p - a, ab) / len2))
        return p.distance(to: a + ab * t)
    }

    public static func distanceToBoundary(_ poly: [Vec2], _ p: Vec2) -> Double {
        edges(poly).map { distancePointSegment(p, $0.0, $0.1) }.min() ?? .infinity
    }

    /// Proper or touching intersection point of segments p1p2 and q1q2, if any (collinear overlap returns nil
    /// and is handled by `segmentsTouch`).
    public static func intersection(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2, epsilon: Double = 1e-9) -> Vec2? {
        let r = p2 - p1, s = q2 - q1
        let denom = cross(r, s)
        if abs(denom) < epsilon { return nil }
        let t = cross(q1 - p1, s) / denom
        let u = cross(q1 - p1, r) / denom
        guard t >= -epsilon, t <= 1 + epsilon, u >= -epsilon, u <= 1 + epsilon else { return nil }
        return p1 + r * t
    }

    /// True if the segments are collinear and overlap by more than `epsilon`.
    public static func collinearOverlap(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2, epsilon: Double = 1e-9) -> Bool {
        let r = p2 - p1
        guard abs(cross(r, q1 - p1)) < epsilon * max(1, r.length), abs(cross(r, q2 - p1)) < epsilon * max(1, r.length) else { return false }
        let len2 = dot(r, r)
        guard len2 > 0 else { return false }
        let t0 = dot(q1 - p1, r) / len2, t1 = dot(q2 - p1, r) / len2
        let lo = max(0, min(t0, t1)), hi = min(1, max(t0, t1))
        return (hi - lo) * r.length > epsilon
    }

    public static func distanceSegmentSegment(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2) -> Double {
        if intersection(p1, p2, q1, q2) != nil { return 0 }
        return min(distancePointSegment(p1, q1, q2), distancePointSegment(p2, q1, q2),
                   distancePointSegment(q1, p1, p2), distancePointSegment(q2, p1, p2))
    }

    /// Minimum distance from a segment to a polygon (0 if it enters/crosses it).
    public static func distanceSegmentPolygon(_ a: Vec2, _ b: Vec2, _ poly: [Vec2]) -> Double {
        if contains(poly, a) || contains(poly, b) { return 0 }
        return edges(poly).map { distanceSegmentSegment(a, b, $0.0, $0.1) }.min() ?? .infinity
    }

    /// Simple polygon: >= 3 vertices, non-zero area, no non-adjacent edge intersections.
    public static func isSimplePolygon(_ poly: [Vec2]) -> Bool {
        guard poly.count >= 3, abs(signedArea(poly)) > 1e-9 else { return false }
        let es = edges(poly)
        for i in es.indices {
            for j in es.indices where j > i + 1 && !(i == 0 && j == es.count - 1) {
                if intersection(es[i].0, es[i].1, es[j].0, es[j].1) != nil { return false }
            }
        }
        return true
    }

    public static func polylineLength(_ pts: [Vec2]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    public static func normalized(_ v: Vec2) -> Vec2 {
        let l = v.length
        return l > 0 ? Vec2(v.x / l, v.y / l) : Vec2(0, 0)
    }
}

/// 4x4 column-major rigid transform (RoomPlan `simd_float4x4` flattened). y is up in the source frame.
public struct RigidTransform3D: Codable, Sendable, Hashable {
    /// 16 values, column-major: m[col*4 + row].
    public var m: [Double]
    public init(columnMajor m: [Double]) { precondition(m.count == 16); self.m = m }
    public static let identity = RigidTransform3D(columnMajor: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1])

    /// Rotation about +y by `yaw` radians, then translation.
    public static func yaw(_ yaw: Double, translation t: Vec3) -> RigidTransform3D {
        let c = cos(yaw), s = sin(yaw)
        // Columns: x-axis, y-axis, z-axis, translation (rotation about y: x' = c x + s z, z' = -s x + c z)
        return RigidTransform3D(columnMajor: [c, 0, -s, 0,  0, 1, 0, 0,  s, 0, c, 0,  t.x, t.y, t.z, 1])
    }

    public func apply(_ p: Vec3) -> Vec3 {
        Vec3(m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
             m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
             m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14])
    }
    public var translation: Vec3 { Vec3(m[12], m[13], m[14]) }
    public var xAxis: Vec3 { Vec3(m[0], m[1], m[2]) }
    public var zAxis: Vec3 { Vec3(m[8], m[9], m[10]) }

    /// Project a source-frame point (y up, right-handed) onto the floor plane as (x, -z), which keeps
    /// the plane right-handed when viewed from above. No rounding.
    public static func projectToFloor(_ p: Vec3) -> Vec2 { Vec2(p.x, -p.z) }
}
