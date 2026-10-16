import SwiftUI
import RealityKit
import DryRunCore

// Neutral "dollhouse": floor slabs, low cut-away walls, simple markers, and route segments built from
// the SAME canonical RoutePath points as the 2D plan (one box per segment, no smoothed ribbon).
// iOS 18 RealityView. AUTHORED, NOT COMPILED/DEVICE-TESTED in this environment.
// Mapping: floor plane (x, y) → RealityKit (x, elevation, -y), metres.

struct DollhouseView: View {
    let home: HomeModel
    let routes: [RoutePath]
    let floorID: String?
    @State private var visible = false

    init(home: HomeModel, routes: [RoutePath], floorID: String?) {
        self.home = home
        self.routes = routes
        self.floorID = floorID
    }

    /// Rebuild only when the inputs change, never per frame. Includes the home's CONTENT fingerprint (an edit without
    /// a revision bump still rebuilds) and every canonical route point (two routes with equal length/exit differ).
    private var sceneKey: String {
        let routePoints = routes.map { r in
            r.legs.map { leg in "\(leg.floorID):" + leg.points.map { "\($0.x),\($0.y)" }.joined(separator: ";") }.joined(separator: "|")
        }.joined(separator: "#")
        return "\(home.id)#\(home.revision)#\(HomeFingerprint.of(home))#\(floorID ?? "all")#\(routePoints)"
    }

    var body: some View {
        ZStack {
            if visible {
                RealityView { content in
                    let root = DollhouseBuilder.build(home: home, routes: routes, floorID: floorID)
                    root.name = sceneKey
                    content.add(root)
                } update: { content in
                    guard let root = content.entities.first, root.name != sceneKey else { return }
                    content.remove(root)
                    let fresh = DollhouseBuilder.build(home: home, routes: routes, floorID: floorID)
                    fresh.name = sceneKey
                    content.add(fresh)
                }
                .realityViewCameraControls(.orbit) // user-driven only; nothing animates on its own
            } else {
                Color(.secondarySystemBackground)
            }
        }
        // Pause 3D work offscreen: the RealityView is torn down when not visible.
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D view of \(home.label). Use the room list for the same information as text.")
    }
}

@MainActor
enum DollhouseBuilder {
    static let wallHeight: Float = 0.9   // cut-away height
    static let slab: Float = 0.05

    static func build(home: HomeModel, routes: [RoutePath], floorID: String?) -> Entity {
        let root = Entity()
        let floors = home.floors.filter { floorID == nil || $0.id == floorID }
        // uniquingKeysWith, not uniqueKeysWithValues: a duplicate floor ID is a reportable data problem
        // (HomeValidator), not a reason to crash the 3D view.
        let elev = Dictionary(home.floors.map { ($0.id, Float($0.elevationMeters)) }, uniquingKeysWith: { first, _ in first })
        // Each floor's coordinates are placed in the shared frame with its rigid Floor.toCommon transform,
        // so storeys, stairs, and routes line up even when floors are rotated/offset relative to each other.
        let toCommon = Dictionary(home.floors.map { ($0.id, $0.toCommon) }, uniquingKeysWith: { first, _ in first })

        // Centre the model at the origin (in the common frame).
        let pts = home.spaces.filter { s in floors.contains { $0.id == s.floorID } }
            .flatMap { s in s.polygon.map { (toCommon[s.floorID] ?? .identity).apply($0) } }
        let cx = Float(((pts.map(\.x).min() ?? 0) + (pts.map(\.x).max() ?? 0)) / 2)
        let cy = Float(((pts.map(\.y).min() ?? 0) + (pts.map(\.y).max() ?? 0)) / 2)
        func p3(_ v: Vec2, _ fid: String, lift: Float = 0) -> SIMD3<Float> {
            let w = (toCommon[fid] ?? .identity).apply(v)
            return SIMD3(Float(w.x) - cx, (elev[fid] ?? 0) + lift, -(Float(w.y) - cy))
        }

        let floorMat = SimpleMaterial(color: .init(white: 0.92, alpha: 1), isMetallic: false)
        let hallMat = SimpleMaterial(color: .init(white: 0.86, alpha: 1), isMetallic: false)
        let wallMat = SimpleMaterial(color: .init(white: 0.55, alpha: 1), isMetallic: false)
        let exitMat = SimpleMaterial(color: .systemGreen, isMetallic: false)
        let unverifiedMat = SimpleMaterial(color: .systemOrange, isMetallic: false)
        let routeMat = SimpleMaterial(color: .systemBlue, isMetallic: false)

        for s in home.spaces where floors.contains(where: { $0.id == s.floorID }) {
            if let mesh = polygonMesh(s.polygon.map { p3($0, s.floorID) }) {
                root.addChild(ModelEntity(mesh: mesh, materials: [s.kind == .hallway ? hallMat : floorMat]))
            }
        }
        for w in ManualLayout.derivedWalls(home) where floors.contains(where: { $0.id == w.floorID }) {
            root.addChild(bar(from: p3(w.a, w.floorID), to: p3(w.b, w.floorID), height: wallHeight,
                              thickness: Float(max(w.thicknessMeters, 0.06)), material: wallMat))
        }
        for p in home.portals where floors.contains(where: { $0.id == p.floorID }) {
            guard p.kind != .window || p.verification == .verified else { continue }
            let exit = p.leadsToExterior && p.verification == .verified && p.kind != .window
            let mat = exit ? exitMat : (p.verification == .verified ? wallMat : unverifiedMat)
            // A thin threshold marker in the opening (doors are gaps in the cut-away walls visually).
            root.addChild(bar(from: p3(p.a, p.floorID, lift: 0.01), to: p3(p.b, p.floorID, lift: 0.01), height: 0.03, thickness: 0.25, material: mat))
        }
        for a in home.annotations {
            guard let pos = a.position, let fid = a.floorID, floors.contains(where: { $0.id == fid }) else { continue }
            let color: UIColor = [.smokeAlarm, .coAlarm, .fireExtinguisher].contains(a.kind) ? .systemRed
                : a.kind == .outsideMeetingPoint ? .systemGreen : .darkGray
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [SimpleMaterial(color: color, isMetallic: false)])
            marker.position = p3(pos, fid, lift: a.kind == .smokeAlarm || a.kind == .coAlarm ? 1.2 : 0.2)
            root.addChild(marker)
        }
        for r in routes {
            for leg in r.legs where floors.contains(where: { $0.id == leg.floorID }) {
                for (a, b) in zip(leg.points, leg.points.dropFirst()) {
                    root.addChild(bar(from: p3(a, leg.floorID, lift: 0.06), to: p3(b, leg.floorID, lift: 0.06), height: 0.04, thickness: 0.12, material: routeMat))
                }
            }
        }
        // Frame the model for the default camera. Built at true scale around the origin, a 12 m home would surround
        // the camera and be seen edge-on. Scale it to about 1.5 m across and tilt its top toward the viewer; orbit
        // controls then start from a readable three-quarter view. Display only: no coordinates are read back from this.
        let spanX = Float((pts.map(\.x).max() ?? 0) - (pts.map(\.x).min() ?? 0))
        let spanY = Float((pts.map(\.y).max() ?? 0) - (pts.map(\.y).min() ?? 0))
        let extent = max(spanX, spanY, 1)
        root.scale = SIMD3<Float>(repeating: 1.5 / extent)
        root.orientation = simd_quatf(angle: .pi / 5, axis: SIMD3<Float>(1, 0, 0))
        let framed = Entity()
        framed.addChild(root)
        return framed
    }

    /// Box spanning a segment on the floor plane.
    static func bar(from a: SIMD3<Float>, to b: SIMD3<Float>, height: Float, thickness: Float, material: SimpleMaterial) -> ModelEntity {
        let d = b - a
        let len = max(simd_length(SIMD2(d.x, d.z)), 0.001)
        let e = ModelEntity(mesh: .generateBox(width: len, height: height, depth: thickness), materials: [material])
        e.position = (a + b) / 2 + SIMD3(0, height / 2, 0)
        e.orientation = simd_quatf(angle: atan2(-d.z, d.x), axis: SIMD3(0, 1, 0))
        return e
    }

    /// Ear-clipped slab for a simple polygon. Concave scan outlines keep their notches instead of being filled by a
    /// fan from an arbitrary vertex. Unsupported outlines (self-intersections or holes) return nil and remain honest
    /// in the review UI rather than drawing a reassuring floor.
    static func polygonMesh(_ verts: [SIMD3<Float>]) -> MeshResource? {
        guard verts.count >= 3 else { return nil }
        // Dollhouse maps the canonical floor's y coordinate to RealityKit's -z axis.
        let polygon = verts.map { Vec2(Double($0.x), Double(-$0.z)) }
        guard let triangles = Geometry.triangulate(polygon) else { return nil }
        var desc = MeshDescriptor(name: "slab")
        desc.positions = MeshBuffers.Positions(verts)
        let idx = triangles.flatMap { $0.map(UInt32.init) }
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }
}
