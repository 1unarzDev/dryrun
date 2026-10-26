import Foundation
import RoomPlan
import simd
import DryRunCore

// Maps RoomPlan output into DryRunCore's plain ScanImport structs. All geometry decisions (projection,
// adjacency proposals, de-duplication, completeness) live in DryRunCore/Spatial/ScanImport.swift and are
// tested on Linux; this file only copies numbers. AUTHORED, NOT COMPILED in this environment.
//
// API assumptions to confirm against the installed SDK (iOS 17+ RoomPlan):
//  - CapturedRoom.walls/doors/windows/openings/floors: [CapturedRoom.Surface]; .objects: [CapturedRoom.Object]; .story: Int
//  - Surface.category: .wall, .door(isOpen:), .window, .opening, .floor; Surface.polygonCorners: [simd_float3]
//  - Floor polygonCorners are expressed in the surface's local frame (verify on device with a real scan).

enum RoomPlanMapping {
    static func transform(_ m: simd_float4x4) -> RigidTransform3D {
        let c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        return RigidTransform3D(columnMajor: c.flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
    }

    static func confidence(_ c: CapturedRoom.Confidence) -> ScanConfidence {
        switch c {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        @unknown default: return .low
        }
    }

    static func category(_ c: CapturedRoom.Surface.Category) -> ScanSurfaceCategory? {
        switch c {
        case .wall: return .wall
        case .door(let isOpen): return isOpen ? .doorOpen : .doorClosed
        case .window: return .window
        case .opening: return .opening
        case .floor: return .floor
        @unknown default: return nil
        }
    }

    static func surface(_ s: CapturedRoom.Surface) -> ScanSurface? {
        guard let cat = category(s.category) else { return nil }
        return ScanSurface(
            id: s.identifier.uuidString,
            category: cat,
            transform: transform(s.transform),
            dimensions: Vec3(Double(s.dimensions.x), Double(s.dimensions.y), Double(s.dimensions.z)),
            polygonCorners: s.polygonCorners.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) },
            confidence: confidence(s.confidence),
            parentID: s.parentIdentifier?.uuidString
        )
    }

    static func object(_ o: CapturedRoom.Object) -> ScanObject {
        ScanObject(
            id: o.identifier.uuidString,
            category: String(describing: o.category),   // e.g. "stairs", "sofa"
            transform: transform(o.transform),
            dimensions: Vec3(Double(o.dimensions.x), Double(o.dimensions.y), Double(o.dimensions.z)),
            confidence: confidence(o.confidence)
        )
    }

    static func room(_ r: CapturedRoom, index: Int) -> ScanRoom {
        let surfaces = (r.floors + r.walls + r.doors + r.windows + r.openings).compactMap(surface)
        return ScanRoom(id: "room-\(index)", story: r.story, surfaces: surfaces, objects: r.objects.map(object))
    }

    /// Rooms from one RoomCaptureSession / shared ARSession, or from StructureBuilder, share a frame.
    static func capture(rooms: [CapturedRoom], sharedFrame: Bool, completed: Bool) -> ScanCapture {
        ScanCapture(rooms: rooms.enumerated().map { room($0.element, index: $0.offset) },
                    sharedCoordinateFrame: sharedFrame, sessionCompleted: completed)
    }
}
