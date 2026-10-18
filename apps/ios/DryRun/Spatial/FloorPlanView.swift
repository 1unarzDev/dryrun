import SwiftUI
import DryRunCore

// 2D floor plan drawn from the canonical HomeModel. Route lines use exactly the RoutePath points
// (no smoothing), so the drawing can never shortcut through a wall that the planner avoided.
// AUTHORED, NOT COMPILED in this environment.

struct FloorPlanView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let home: HomeModel
    let routes: [RoutePath]
    let highlightedFloorID: String?
    var highlightedElementID: String?
    var spatialState: SpatialExerciseState?
    var selectedRoute: RouteResult?
    var onSelect: ((String) -> Void)?
    @State private var selectedFloorID: String?

    init(home: HomeModel, routes: [RoutePath], highlightedFloorID: String?, highlightedElementID: String? = nil, spatialState: SpatialExerciseState? = nil, selectedRoute: RouteResult? = nil, onSelect: ((String) -> Void)? = nil) {
        self.home = home
        self.routes = routes
        self.highlightedFloorID = highlightedFloorID
        self.highlightedElementID = highlightedElementID; self.spatialState = spatialState; self.selectedRoute = selectedRoute; self.onSelect = onSelect
    }

    private var floorID: String? { highlightedFloorID ?? selectedFloorID ?? home.floors.first?.id }

    var body: some View {
        VStack(spacing: 6) {
            if home.floors.count > 1 && highlightedFloorID == nil {
                Picker(s("Floor"), selection: Binding(get: { floorID ?? "" }, set: { selectedFloorID = $0 })) {
                    ForEach(home.floors) { f in
                        Text(routeFloors.contains(f.id) ? model.localizer("spatial.floor-route", ["floor": f.label]) : f.label).tag(f.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            GeometryReader { geometry in
                Canvas { context, size in draw(in: &context, size: size) }
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        if let id = hitTest(point, size: geometry.size) { onSelect?(id) }
                    }
            }
            .background(PlanColors.background)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(s("The room list gives the same information as text."))
            legend
        }
        .onChange(of: highlightedFloorID) { _, _ in selectedFloorID = nil }
    }

    private var routeFloors: Set<String> { Set(routes.flatMap { $0.legs.map(\.floorID) }) }

    private var legend: some View {
        HStack(spacing: 12) {
            Label(s("Verified exit"), systemImage: "door.left.hand.open").foregroundStyle(PlanColors.exit)
            Label(s("Unconfirmed"), systemImage: "questionmark.diamond").foregroundStyle(PlanColors.unverified)
            if !routes.isEmpty { Label(s("Practice route"), systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(PlanColors.route) }
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
        .padding(.bottom, 4)
    }

    private var accessibilitySummary: String {
        guard let fid = floorID, let floor = home.floors.first(where: { $0.id == fid }) else { return model.localizer("spatial.floor-plan") }
        let rooms = home.spaces.filter { $0.floorID == fid }.map(\.label).joined(separator: ", ")
        let exits = home.portals.filter { $0.floorID == fid && HomeScenePresentation.openingStatus($0, in: home, state: spatialState, request: selectedRoute?.request) == .availableExit }.count
        let summary = model.localizer("spatial.floor-summary", ["floor": floor.label, "rooms": rooms, "count": String(exits)])
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), room.floorID == fid {
            return summary + " " + model.localizer("spatial.recorded-start-room", ["room": room.label])
        }
        return summary
    }

    // MARK: Drawing

    private struct Fit {
        let scale: Double, minX: Double, maxY: Double, offset: CGPoint
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: offset.x + (v.x - minX) * scale, y: offset.y + (maxY - v.y) * scale) }
    }

    /// Fits and centres the rooms only. Outdoor markers (meeting point, hydrant) can be far from the house; including
    /// them shrank the plan into a corner, so they are drawn pinned to the canvas edge instead (see `draw`).
    private func fit(_ size: CGSize, _ fid: String) -> Fit? {
        var pts = home.spaces.filter { $0.floorID == fid }.flatMap(\.polygon)
        if pts.isEmpty { pts = home.annotations.filter { $0.floorID == fid }.compactMap(\.position) }
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return nil }
        let pad = 22.0
        let w = max(maxX - minX, 0.5), h = max(maxY - minY, 0.5)
        let scale = max(min((Double(size.width) - 2 * pad) / w, (Double(size.height) - 2 * pad) / h), 1)
        let offset = CGPoint(x: (Double(size.width) - w * scale) / 2, y: (Double(size.height) - h * scale) / 2)
        return Fit(scale: scale, minX: minX, maxY: maxY, offset: offset)
    }

    private func path(_ poly: [Vec2], _ f: Fit, closed: Bool) -> Path {
        var p = Path()
        guard let first = poly.first else { return p }
        p.move(to: f.pt(first))
        for v in poly.dropFirst() { p.addLine(to: f.pt(v)) }
        if closed { p.closeSubpath() }
        return p
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        guard let fid = floorID, let f = fit(size, fid) else { return }
        let spaces = home.spaces.filter { $0.floorID == fid }

        for s in spaces {
            ctx.fill(path(s.polygon, f, closed: true), with: .color(s.kind == .hallway ? PlanColors.hall : PlanColors.room))
        }
        for room in spaces where spatialState?.affectedSpaceIDs.contains(room.id) == true {
            ctx.fill(path(room.polygon, f, closed: true), with: .color(spatialState?.hazard == .flashFlood ? .blue.opacity(0.22) : .orange.opacity(0.25)))
            ctx.draw(Text(spatialState?.hazard == .flashFlood ? "≈" : "!").font(.title.bold()), at: f.pt(Geometry.centroid(room.polygon)))
        }
        for room in spaces where spatialState?.exposedSpaceIDs?.contains(room.id) == true {
            ctx.stroke(path(room.polygon, f, closed: true), with: .color(.purple.opacity(0.6)), style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
        }
        for o in home.obstacles where o.floorID == fid {
            ctx.fill(path(o.polygon, f, closed: true), with: .color(PlanColors.obstacle))
        }
        for w in ManualLayout.derivedWalls(home) where w.floorID == fid {
            ctx.stroke(path([w.a, w.b], f, closed: false), with: .color(PlanColors.wall), lineWidth: 3)
        }
        for p in home.portals where p.floorID == fid {
            // Erase the wall at the opening, then draw it with a style that does not rely on colour alone.
            let line = path([p.a, p.b], f, closed: false)
            ctx.stroke(line, with: .color(PlanColors.background), lineWidth: 5)
            let status = HomeScenePresentation.openingStatus(p, in: home, state: spatialState, request: selectedRoute?.request)
            let verifiedExit = status == .availableExit
            let style: StrokeStyle = status == .unconfirmed ? StrokeStyle(lineWidth: 2, dash: [3, 3]) : StrokeStyle(lineWidth: 3)
            let color: Color = status == .unavailable ? PlanColors.alarm : p.kind == .window ? PlanColors.window : verifiedExit ? PlanColors.exit : status == .confirmedConnection ? PlanColors.door : PlanColors.unverified
            ctx.stroke(line, with: .color(color), style: style)
            if p.kind == .window && spatialState?.hazard == .tornado {
                // Static cue also serves Reduce Motion. It illustrates exposure, not predicted structural damage.
                ctx.draw(Text("×").font(.system(size: 18, weight: .bold)).foregroundStyle(.purple), at: f.pt(p.center))
            }
            if status == .unavailable {
                ctx.draw(Text("×").font(.system(size: 18, weight: .bold)).foregroundStyle(PlanColors.alarm), at: f.pt(p.center))
            } else if verifiedExit {
                ctx.draw(Text(s("EXIT")).font(.system(size: 9, weight: .bold)).foregroundStyle(PlanColors.exit), at: f.pt(p.center), anchor: .center)
            } else if status == .unconfirmed {
                ctx.draw(Text(s("?")).font(.system(size: 11, weight: .bold)).foregroundStyle(PlanColors.unverified), at: f.pt(p.center), anchor: .center)
            }
        }
        for connector in home.connectors {
            let room = home.space(connector.fromSpaceID)
            let other = home.space(connector.toSpaceID)
            if room?.floorID == fid { ctx.draw(Text(Image(systemName: "stairs")).font(.caption), at: f.pt(connector.fromPoint)) }
            if other?.floorID == fid { ctx.draw(Text(Image(systemName: "stairs")).font(.caption), at: f.pt(connector.toPoint)) }
        }
        if let id = highlightedElementID {
            if let room = home.space(id), room.floorID == fid { ctx.stroke(path(room.polygon, f, closed: true), with: .color(.purple), lineWidth: 5) }
            if let opening = home.portal(id), opening.floorID == fid {
                ctx.stroke(path([opening.a, opening.b], f, closed: false), with: .color(.purple), lineWidth: 9)
            }
            if let connector = home.connectors.first(where: { $0.id == id }) {
                let points = [(home.space(connector.fromSpaceID)?.floorID, connector.fromPoint), (home.space(connector.toSpaceID)?.floorID, connector.toPoint)]
                for (floor, point) in points where floor == fid {
                    ctx.stroke(Path(ellipseIn: CGRect(origin: f.pt(point), size: .zero).insetBy(dx: -12, dy: -12)), with: .color(.purple), lineWidth: 5)
                }
            }
            if let obstacle = home.obstacles.first(where: { $0.id == id && $0.floorID == fid }) { ctx.stroke(path(obstacle.polygon, f, closed: true), with: .color(.purple), lineWidth: 5) }
        }
        var markers: [CGPoint] = []
        for a in home.annotations where a.floorID == fid {
            guard let pos = a.position else { continue }
            let p = f.pt(pos)
            let pinned = pinnedPoint(p, size: size)
            if a.id == highlightedElementID {
                ctx.stroke(Path(ellipseIn: CGRect(origin: pinned, size: .zero).insetBy(dx: -13, dy: -13)), with: .color(.purple), lineWidth: 4)
            }
            markers.append(pinned)
            ctx.draw(Text(Image(systemName: Self.symbol(a.kind))).font(.system(size: 13)).foregroundStyle(Self.color(a.kind)), at: pinned, anchor: .center)
        }
        for s in spaces {
            // A label that does not fit its room is shrunk, then dropped rather than drawn across a neighbour; the
            // room list and the VoiceOver summary name every room.
            let xs = s.polygon.map { f.pt($0).x }, ys = s.polygon.map { f.pt($0).y }
            let room = CGSize(width: (xs.max() ?? 0) - (xs.min() ?? 0) - 4, height: (ys.max() ?? 0) - (ys.min() ?? 0) - 2)
            for font in [Font.caption2, .system(size: 8)] {
                let text = ctx.resolve(Text(s.label).font(font).foregroundStyle(PlanColors.label))
                let need = text.measure(in: CGSize(width: room.width, height: .infinity))
                if need.width <= room.width && need.height <= room.height {
                    // Safety markers often sit at the room centre: move the name above one rather than cover it.
                    var c = f.pt(Geometry.centroid(s.polygon))
                    if markers.contains(where: { abs($0.x - c.x) < need.width / 2 + 8 && abs($0.y - c.y) < 12 }) {
                        c.y = max(c.y - need.height / 2 - 9, (ys.min() ?? c.y) + need.height / 2 + 1)
                    }
                    let rect = CGRect(x: c.x - need.width / 2, y: c.y - need.height / 2, width: need.width, height: need.height)
                    ctx.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: 0), cornerRadius: 3),
                             with: .color((s.kind == .hallway ? PlanColors.hall : PlanColors.room).opacity(0.85)))
                    ctx.draw(text, in: rect)
                    break
                }
            }
        }
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), room.floorID == fid,
           let position = HomeScenePresentation.startingRoomPosition(in: home, route: selectedRoute) {
            ctx.draw(Text(Image(systemName: "person.crop.circle.fill")).font(.title2).foregroundStyle(PlanColors.route), at: f.pt(position))
        }
        for (i, r) in routes.enumerated() {
            for leg in r.legs where leg.floorID == fid && leg.points.count >= 2 {
                let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: i == 0 ? [] : [8, 5])
                ctx.stroke(path(leg.points, f, closed: false), with: .color(PlanColors.route), style: style)
                if let start = leg.points.first {
                    ctx.fill(Path(ellipseIn: CGRect(origin: f.pt(start), size: .zero).insetBy(dx: -5, dy: -5)), with: .color(PlanColors.route))
                }
            }
        }
    }

    private func pinnedPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func hitTest(_ point: CGPoint, size: CGSize) -> String? {
        guard let fid = floorID, let fit = fit(size, fid) else { return nil }
        let local = Vec2((point.x - fit.offset.x) / fit.scale + fit.minX, fit.maxY - (point.y - fit.offset.y) / fit.scale)
        let tolerance = 18 / fit.scale
        if let annotation = home.annotations.first(where: { annotation in
            guard annotation.floorID == fid, let position = annotation.position else { return false }
            let marker = pinnedPoint(fit.pt(position), size: size)
            return hypot(marker.x - point.x, marker.y - point.y) <= 18
        }) { return annotation.id }
        if let portal = home.portals.filter({ $0.floorID == fid }).min(by: {
            Geometry.distancePointSegment(local, $0.a, $0.b) < Geometry.distancePointSegment(local, $1.a, $1.b)
        }), Geometry.distancePointSegment(local, portal.a, portal.b) <= tolerance { return portal.id }
        if let connector = home.connectors.first(where: { connector in
            (home.space(connector.fromSpaceID)?.floorID == fid && connector.fromPoint.distance(to: local) <= tolerance)
            || (home.space(connector.toSpaceID)?.floorID == fid && connector.toPoint.distance(to: local) <= tolerance)
        }) { return connector.id }
        if let obstacle = home.obstacles.first(where: { $0.floorID == fid && Geometry.contains($0.polygon, local) }) { return obstacle.id }
        return home.spaces.first(where: { $0.floorID == fid && Geometry.contains($0.polygon, local) })?.id
    }

    static func symbol(_ k: AnnotationKind) -> String {
        switch k {
        case .smokeAlarm: return "smoke"
        case .coAlarm: return "sensor"
        case .fireExtinguisher: return "fire.extinguisher"
        case .exteriorHydrant: return "drop"
        case .utilityShutoffWater: return "spigot"
        case .utilityShutoffGas: return "flame"
        case .utilityShutoffElectric: return "bolt"
        case .supplies: return "shippingbox"
        case .medicalEquipment: return "cross.case"
        case .tornadoShelterCandidate: return "tornado"
        case .outsideMeetingPoint: return "figure.2"
        }
    }

    static func color(_ k: AnnotationKind) -> Color {
        switch k {
        case .smokeAlarm, .coAlarm, .fireExtinguisher: return PlanColors.alarm
        case .outsideMeetingPoint: return PlanColors.exit
        case .medicalEquipment: return PlanColors.route
        case .exteriorHydrant: return .secondary
        default: return PlanColors.label
        }
    }
}

/// Neutral, restrained palette. Status never relies on colour alone (EXIT/? labels, dashes).
enum PlanColors {
    static let background = Color(.systemBackground)
    static let room = Color(.secondarySystemBackground)
    static let hall = Color(.tertiarySystemBackground)
    static let obstacle = Color(.systemGray4)
    static let wall = Color(.label).opacity(0.8)
    static let label = Color(.label)
    static let door = Color(.systemGray)
    static let window = Color(.systemTeal).opacity(0.7)
    static let exit = Color(.systemGreen)
    static let unverified = Color(.systemOrange)
    static let route = Color(.systemBlue)
    static let alarm = Color(.systemRed)
}
