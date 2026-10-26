import SwiftUI
import RealityKit
import DryRunCore

// Neutral "dollhouse": floor slabs, low cut-away walls, simple markers, and route segments built from
// the SAME canonical RoutePath points as the 2D plan (one box per segment, no smoothed ribbon).
// iOS 18 RealityView. Rendered on an iPhone 16 Pro (iOS 26.6.1) with the example homes, October 18, 2026; not yet with a real scan.
// Mapping: floor plane (x, y) → RealityKit (x, elevation, -y), metres.

struct DollhouseView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let home: HomeModel
    let routes: [RoutePath]
    let floorID: String?
    let spatialState: SpatialExerciseState?
    let selectedRoute: RouteResult?
    @State private var visible = false

    init(home: HomeModel, routes: [RoutePath], floorID: String?, spatialState: SpatialExerciseState? = nil, selectedRoute: RouteResult? = nil) {
        self.home = home
        self.routes = routes
        self.floorID = floorID; self.spatialState = spatialState; self.selectedRoute = selectedRoute
    }

    /// Rebuild only when the inputs change, never per frame. Includes the home's CONTENT fingerprint (an edit without
    /// a revision bump still rebuilds) and every canonical route point (two routes with equal length/exit differ).
    private var sceneKey: String {
        let routePoints = routes.map { r in
            r.legs.map { leg in "\(leg.floorID):" + leg.points.map { "\($0.x),\($0.y)" }.joined(separator: ";") }.joined(separator: "|")
        }.joined(separator: "#")
        return "\(home.id)#\(home.revision)#\(HomeFingerprint.of(home))#\(floorID ?? "all")#\(routePoints)#\(spatialState?.stageID ?? "")#\(spatialState?.hazard.rawValue ?? "")#\(spatialState?.affectedSpaceIDs.joined(separator: ",") ?? "")#\(spatialState?.exposedSpaceIDs?.joined(separator: ",") ?? "")#\(spatialState?.destinationSpaceID ?? "")#\(spatialState?.affectedPortalIDs.joined(separator: ",") ?? "")#\(String(describing: selectedRoute?.request))"
    }

    var body: some View {
        ZStack {
            if visible {
                RealityView { content in
                    let root = DollhouseBuilder.build(home: home, routes: routes, floorID: floorID, spatialState: spatialState, selectedRoute: selectedRoute)
                    root.name = sceneKey
                    content.add(root)
                } update: { content in
                    guard let root = content.entities.first, root.name != sceneKey else { return }
                    content.remove(root)
                    let fresh = DollhouseBuilder.build(home: home, routes: routes, floorID: floorID, spatialState: spatialState, selectedRoute: selectedRoute)
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
        .accessibilityLabel(model.localizer("spatial.dollhouse-summary", ["home": home.label]))
    }
}

@MainActor
enum DollhouseBuilder {
    static let wallHeight: Float = 0.6   // cut-away height: low enough that a small room's floor and name stay visible
    static let slab: Float = 0.05
    private static var meshCache: [String: MeshResource] = [:]

    static func build(home: HomeModel, routes: [RoutePath], floorID: String?, spatialState: SpatialExerciseState? = nil, selectedRoute: RouteResult? = nil) -> Entity {
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
        for w in HomeRenderGeometry.wallSegments(home) where floors.contains(where: { $0.id == w.floorID }) {
            root.addChild(bar(from: p3(w.a, w.floorID), to: p3(w.b, w.floorID), height: wallHeight,
                              thickness: Float(max(w.thicknessMeters, 0.06)), material: wallMat))
        }
        for p in home.portals where floors.contains(where: { $0.id == p.floorID }) {

            let status = HomeScenePresentation.openingStatus(p, in: home, state: spatialState, request: selectedRoute?.request)
            let exit = status == .availableExit
            let mat = status == .unavailable ? SimpleMaterial(color: .systemRed, isMetallic: false) : p.kind == .window ? SimpleMaterial(color: spatialState?.hazard == .tornado ? .systemPurple : .systemTeal, isMetallic: false) : exit ? exitMat : (status == .confirmedConnection ? wallMat : unverifiedMat)
            if status == .unavailable {
                let c = p.center
                for sign in [-1.0, 1.0] {
                    root.addChild(bar(from: p3(c + Vec2(-0.18, -0.18 * sign), p.floorID, lift: 0.13), to: p3(c + Vec2(0.18, 0.18 * sign), p.floorID, lift: 0.13), height: 0.05, thickness: 0.06, material: mat))
                }
            }
            // A thin threshold marker in the opening (doors are gaps in the cut-away walls visually).
            root.addChild(bar(from: p3(p.a, p.floorID, lift: 0.01), to: p3(p.b, p.floorID, lift: 0.01), height: 0.03, thickness: 0.25, material: mat))
        }
        for obstacle in home.obstacles where floors.contains(where: { $0.id == obstacle.floorID }) {
            if let mesh = polygonMesh(obstacle.polygon.map { p3($0, obstacle.floorID, lift: 0.08) }) {
                root.addChild(ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .darkGray, isMetallic: false)]))
            }
        }
        for connector in home.connectors {
            guard let from = home.space(connector.fromSpaceID), let to = home.space(connector.toSpaceID),
                  floors.contains(where: { $0.id == from.floorID || $0.id == to.floorID }) else { continue }
            let a = p3(connector.fromPoint, from.floorID, lift: 0.08), b = p3(connector.toPoint, to.floorID, lift: 0.08)
            for index in 0...8 {
                let t = Float(index) / 8
                let step = ModelEntity(mesh: .generateBox(width: 0.7, height: 0.06, depth: 0.22), materials: [wallMat])
                step.position = a + (b - a) * t
                root.addChild(step)
            }
        }
        for room in home.spaces where spatialState?.affectedSpaceIDs.contains(room.id) == true && floors.contains(where: { $0.id == room.floorID }) {
            if let mesh = polygonMesh(room.polygon.map { p3($0, room.floorID, lift: 0.10) }) {
                root.addChild(ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: spatialState?.hazard == .flashFlood ? .systemBlue : .systemOrange, isMetallic: false)]))
            }
        }
        // Destination and exposure outlines preserve the hazard fill underneath.
        for room in home.spaces where floors.contains(where: { $0.id == room.floorID })
            && (spatialState?.destinationSpaceID == room.id || spatialState?.exposedSpaceIDs?.contains(room.id) == true) {
            let material = SimpleMaterial(color: .systemPurple, isMetallic: false)
            for (a, b) in zip(room.polygon, room.polygon.dropFirst() + room.polygon.prefix(1)) {
                root.addChild(bar(from: p3(a, room.floorID, lift: 0.14), to: p3(b, room.floorID, lift: 0.14), height: 0.04, thickness: 0.06, material: material))
            }
        }
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), floors.contains(where: { $0.id == room.floorID }),
           let position = HomeScenePresentation.startingRoomPosition(in: home, route: selectedRoute) {
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.18), materials: [routeMat])
            marker.position = p3(position, room.floorID, lift: 0.35)
            root.addChild(marker)
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
        // Room names lie flat on each floor, like the 2D plan, so the model can be read without tapping.
        let labelMat = UnlitMaterial(color: .init(white: 0.15, alpha: 1))
        for room in home.spaces where floors.contains(where: { $0.id == room.floorID }) {
            let blockers = home.obstacles.filter { $0.floorID == room.floorID }.map(\.polygon)
            if let spot = labelSpot(room.polygon, avoiding: blockers),
               let label = roomLabel(room.label, polygon: room.polygon, material: labelMat) {
                label.position = p3(spot, room.floorID, lift: 0.02)
                root.addChild(label)
            }
        }
        // Frame the model for the default camera. Built at true scale around the origin, a 12 m home would surround
        // the camera and be seen edge-on. Scale it to about 1.8 m across and tilt its top toward the viewer; orbit
        // controls then start from a readable three-quarter view. Display only: no coordinates are read back from this.
        let spanX = Float((pts.map(\.x).max() ?? 0) - (pts.map(\.x).min() ?? 0))
        let spanY = Float((pts.map(\.y).max() ?? 0) - (pts.map(\.y).min() ?? 0))
        let extent = max(spanX, spanY, 1)
        root.scale = SIMD3<Float>(repeating: 1.8 / extent)
        root.orientation = simd_quatf(angle: 0.95, axis: SIMD3<Float>(1, 0, 0))
        let framed = Entity()
        framed.addChild(root)
        return framed
    }

    /// The room's centroid, or the nearest nearby point that is inside the room and clear of furniture (a kitchen
    /// island at the centre would otherwise cover the name). Nil when no candidate is clear.
    static func labelSpot(_ polygon: [Vec2], avoiding blockers: [[Vec2]]) -> Vec2? {
        let c = Geometry.centroid(polygon)
        let w = (polygon.map(\.x).max() ?? 0) - (polygon.map(\.x).min() ?? 0)
        let d = (polygon.map(\.y).max() ?? 0) - (polygon.map(\.y).min() ?? 0)
        let steps: [(Double, Double)] = [(0, 0), (0, 0.25), (0, -0.25), (0.25, 0), (-0.25, 0), (0, 0.35), (0, -0.35), (0.25, 0.25), (-0.25, 0.25), (0.25, -0.25), (-0.25, -0.25)]
        return steps.map { c + Vec2($0.0 * w, $0.1 * d) }.first { p in
            Geometry.contains(polygon, p) && Geometry.distanceToBoundary(polygon, p) > 0.35
                && blockers.allSatisfy { !Geometry.contains($0, p) && Geometry.distanceToBoundary($0, p) > 0.45 }
        }
    }

    /// Flat text centred on the chosen spot, shrunk to fit the room and dropped (never drawn across a wall) when it
    /// would be unreadably small.
    static func roomLabel(_ text: String, polygon: [Vec2], material: UnlitMaterial) -> Entity? {
        guard !text.isEmpty else { return nil }
        let key = "text:" + text
        let mesh: MeshResource
        if let cached = meshCache[key] { mesh = cached }
        else {
            mesh = .generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.32, weight: .semibold),
                                 containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
            cache(mesh, key: key)
        }
        let bounds = mesh.bounds
        let width = Double(polygon.map(\.x).max()! - polygon.map(\.x).min()!)
        let depth = Double(polygon.map(\.y).max()! - polygon.map(\.y).min()!)
        let fit = Float(min(1, width * 0.8 / Double(max(bounds.extents.x, 0.001)), depth * 0.5 / Double(max(bounds.extents.y, 0.001))))
        guard fit >= 0.45 else { return nil }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = -bounds.center
        let holder = Entity()
        holder.addChild(entity)
        holder.scale = SIMD3(repeating: fit)
        holder.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))   // lie on the floor, reading toward the viewer
        return holder
    }

    /// Box spanning a segment on the floor plane.
    static func bar(from a: SIMD3<Float>, to b: SIMD3<Float>, height: Float, thickness: Float, material: SimpleMaterial) -> ModelEntity {
        let d = b - a
        let len = max(simd_length(SIMD2(d.x, d.z)), 0.001)
        let key = "box:\(len),\(height),\(thickness)"
        let mesh: MeshResource
        if let cached = meshCache[key] { mesh = cached }
        else { mesh = .generateBox(width: len, height: height, depth: thickness); cache(mesh, key: key) }
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = (a + b) / 2 + SIMD3(0, height / 2, 0)
        e.orientation = simd_quatf(angle: atan2(-d.z, d.x), axis: SIMD3(0, 1, 0))
        return e
    }

    /// Ear-clipped slab for a simple polygon. Concave scan outlines keep their notches instead of being filled by a
    /// fan from an arbitrary vertex. Unsupported outlines (self-intersections or holes) return nil and remain honest
    /// in the review UI rather than drawing a reassuring floor.
    static func polygonMesh(_ verts: [SIMD3<Float>]) -> MeshResource? {
        guard verts.count >= 3 else { return nil }
        let key = "polygon:" + verts.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: ";")
        if let cached = meshCache[key] { return cached }
        // Dollhouse maps the canonical floor's y coordinate to RealityKit's -z axis.
        let polygon = verts.map { Vec2(Double($0.x), Double(-$0.z)) }
        guard let triangles = Geometry.triangulate(polygon) else { return nil }
        var desc = MeshDescriptor(name: "slab")
        desc.positions = MeshBuffers.Positions(verts)
        // RoomPlan outlines arrive in either winding. Back faces are culled, so a clockwise outline would face the
        // ground and its floor would vanish from above: wind every triangle to face up and give it an up normal.
        let idx = triangles.flatMap { t -> [UInt32] in
            let a = verts[t[0]], b = verts[t[1]], c = verts[t[2]]
            let up = simd_cross(b - a, c - a).y >= 0
            return (up ? t : [t[0], t[2], t[1]]).map(UInt32.init)
        }
        desc.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: verts.count))
        desc.primitives = .triangles(idx)
        guard let mesh = try? MeshResource.generate(from: [desc]) else { return nil }
        cache(mesh, key: key)
        return mesh
    }
    private static func cache(_ mesh: MeshResource, key: String) {
        if meshCache.count >= 512 { meshCache.removeAll(keepingCapacity: true) }
        meshCache[key] = mesh
    }
}

/// Key for the 3D colours, listing only what this scene actually draws. Same wording as the 2D plan and printed key.
struct DollhouseKey: View {
    @Environment(AppModel.self) private var model
    let home: HomeModel
    var spatialState: SpatialExerciseState? = nil
    var selectedRoute: RouteResult? = nil
    var hasRoutes = false

    /// Mirrors DollhouseBuilder's material choice per opening and marker, so the key never lists a colour that is
    /// not on screen or misses one that is.
    private var items: [(key: String, color: Color, shape: String)] {
        let l = model.localizer
        var drawn: Set<String> = []
        for p in home.portals {
            let status = HomeScenePresentation.openingStatus(p, in: home, state: spatialState, request: selectedRoute?.request)
            if status == .unavailable { drawn.insert("blocked") }
            else if p.kind == .window { drawn.insert("window") }
            else if status == .availableExit { drawn.insert("exit") }
            else if status != .confirmedConnection { drawn.insert("unconfirmed") }
        }
        var out: [(String, Color, String)] = []
        if drawn.contains("exit") { out.append((l("pdf.legend.exit"), .green, "rectangle.fill")) }
        if drawn.contains("window") { out.append((l("pdf.legend.window"), spatialState?.hazard == .tornado ? .purple : .teal, "rectangle.fill")) }
        if drawn.contains("unconfirmed") { out.append((l("pdf.legend.unconfirmed"), .orange, "rectangle.fill")) }
        if drawn.contains("blocked") { out.append((l("pdf.legend.blocked"), .red, "xmark")) }
        if hasRoutes { out.append((l("pdf.legend.primary"), .blue, "line.diagonal")) }
        if !(spatialState?.affectedSpaceIDs.isEmpty ?? true) {
            out.append((l("pdf.legend.affected"), spatialState?.hazard == .flashFlood ? .blue : .orange, "square.fill"))
        }
        if spatialState?.destinationSpaceID != nil || !(spatialState?.exposedSpaceIDs?.isEmpty ?? true) {
            out.append((l(spatialState?.destinationSpaceID != nil ? "pdf.legend.shelter" : "pdf.legend.exposed"), .purple, "square"))
        }
        if selectedRoute != nil, HomeScenePresentation.startingRoom(in: home, route: selectedRoute) != nil { out.append((l("pdf.legend.start"), .blue, "circle.fill")) }
        let floorIDs = Set(home.floors.map(\.id))
        let kinds = Set(home.annotations.filter { $0.position != nil && $0.floorID.map(floorIDs.contains) == true }.map(\.kind))
        let safety = [AnnotationKind.smokeAlarm, .coAlarm, .fireExtinguisher].filter(kinds.contains)
        if !safety.isEmpty { out.append((safety.map { l("pdf.legend.\($0.rawValue)") }.joined(separator: ", "), .red, "circle.fill")) }
        if kinds.contains(.outsideMeetingPoint) { out.append((l("pdf.legend.meetup"), .green, "circle.fill")) }
        let others = kinds.subtracting(safety + [.outsideMeetingPoint]).sorted { $0.rawValue < $1.rawValue }
            .compactMap { DiagramLegendKey.key($0) }.map { l($0) }
        if !others.isEmpty { out.append((Array(Set(others)).sorted().joined(separator: ", "), Color(white: 0.35), "circle.fill")) }
        if !home.obstacles.isEmpty { out.append((l("pdf.legend.furniture"), Color(white: 0.35), "square.fill")) }
        return out
    }

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.key) { row($0, l).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
    private func row(_ item: (key: String, color: Color, shape: String), _ l: Localizer) -> some View {
        Label { Text(item.key).foregroundStyle(.secondary) } icon: { Image(systemName: item.shape).foregroundStyle(item.color) }
    }
}

/// Printed-key wording for the neutral grey 3D markers; nil for kinds that have no key entry.
enum DiagramLegendKey {
    static func key(_ kind: AnnotationKind) -> String? {
        switch kind {
        case .utilityShutoffWater, .utilityShutoffGas, .utilityShutoffElectric: "pdf.legend.shutoff"
        case .supplies: "pdf.legend.supplies"
        case .medicalEquipment: "pdf.legend.medicalEquipment"
        default: nil
        }
    }
}
