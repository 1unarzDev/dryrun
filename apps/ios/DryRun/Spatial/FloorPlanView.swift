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
    var onSelectPoint: ((Vec2, String) -> Void)?
    var placementPoint: Vec2?
    @State private var selectedFloorID: String?

    init(home: HomeModel, routes: [RoutePath], highlightedFloorID: String?, highlightedElementID: String? = nil, spatialState: SpatialExerciseState? = nil, selectedRoute: RouteResult? = nil, onSelect: ((String) -> Void)? = nil, onSelectPoint: ((Vec2, String) -> Void)? = nil, placementPoint: Vec2? = nil) {
        self.home = home
        self.routes = routes
        self.highlightedFloorID = highlightedFloorID
        self.highlightedElementID = highlightedElementID; self.spatialState = spatialState; self.selectedRoute = selectedRoute; self.onSelect = onSelect
        self.onSelectPoint = onSelectPoint; self.placementPoint = placementPoint
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
                        if let onSelectPoint, let fid = floorID, let fit = fit(geometry.size, fid) {
                            let local = Vec2((point.x - fit.offset.x) / fit.scale + fit.minX, fit.maxY - (point.y - fit.offset.y) / fit.scale)
                            onSelectPoint(local, fid)
                        } else if let id = hitTest(point, size: geometry.size) { onSelect?(id) }
                    }
            }
            .frame(minHeight: 140)
            .background(PlanColors.background)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(s("The room list gives the same information as text."))
            legend
        }
        .onChange(of: highlightedFloorID) { _, _ in selectedFloorID = nil }
    }

    private var routeFloors: Set<String> { Set(routes.flatMap { $0.legs.map(\.floorID) }) }

    /// Generated from what this scene actually shows, never a fixed list.
    private var legend: some View {
        let l = model.localizer
        let statuses = home.portals.filter { $0.floorID == floorID }.map {
            HomeScenePresentation.openingStatus($0, in: home, state: spatialState, request: selectedRoute?.request)
        }
        var items: [(String, String, Color)] = []
        if statuses.contains(.availableExit) { items.append((s("Verified exit"), "door.left.hand.open", PlanColors.exit)) }
        if statuses.contains(.unconfirmed) { items.append((s("Unconfirmed"), "questionmark.diamond", PlanColors.unverified)) }
        if statuses.contains(.unavailable) { items.append((l("pdf.legend.blocked"), "xmark", PlanColors.alarm)) }
        if routeFloors.contains(floorID ?? "") { items.append((l("pdf.legend.primary"), "arrow.right", PlanColors.route)) }
        if routes.dropFirst().contains(where: { $0.legs.contains { $0.floorID == floorID } }) { items.append((l("pdf.legend.alternative"), "arrow.right.circle.dotted", PlanColors.route)) }
        if let state = spatialState {
            if state.originSpaceID.flatMap({ home.space($0)?.floorID }) == floorID && state.originSpaceID != nil && state.hazard != .flashFlood { items.append((l("ui.scene.origin"), "flame.fill", PlanColors.alarm)) }
            if state.affectedSpaceIDs.contains(where: { home.space($0)?.floorID == floorID }) { items.append((l("pdf.legend.affected"), state.hazard == .flashFlood ? "water.waves" : "smoke.fill", state.hazard == .flashFlood ? .blue : .secondary)) }
            if state.exposedSpaceIDs?.contains(where: { home.space($0)?.floorID == floorID }) == true || (state.hazard == .tornado && home.portals.contains { $0.floorID == floorID && $0.kind == .window }) { items.append((l("pdf.legend.exposed"), "exclamationmark.triangle.fill", .purple)) }
            if state.destinationSpaceID.flatMap({ home.space($0)?.floorID }) == floorID && state.destinationSpaceID != nil { items.append((l("pdf.legend.shelter"), "shield.lefthalf.filled", PlanColors.exit)) }
        }
        if HomeScenePresentation.startingRoom(in: home, route: selectedRoute)?.floorID == floorID && selectedRoute != nil { items.append((l("pdf.legend.start"), "person.circle.fill", Color(.label))) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ForEach(items, id: \.0) { Label($0.0, systemImage: $0.1).foregroundStyle($0.2) } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(items, id: \.0) { Label($0.0, systemImage: $0.1).foregroundStyle($0.2) }
            }
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        // The key keeps its space inside a fixed-height scene (the drawing gives way) and stays compact at the largest
        // text sizes; every item is also in the room list and the VoiceOver summary.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .layoutPriority(1)
    }

    private var accessibilitySummary: String {
        guard let fid = floorID, let floor = home.floors.first(where: { $0.id == fid }) else { return model.localizer("spatial.floor-plan") }
        let rooms = home.spaces.filter { $0.floorID == fid }.map(\.label).joined(separator: ", ")
        let exits = home.portals.filter { $0.floorID == fid && HomeScenePresentation.openingStatus($0, in: home, state: spatialState, request: selectedRoute?.request) == .availableExit }.count
        var summary = model.localizer("spatial.floor-summary", ["floor": floor.label, "rooms": rooms, "count": String(exits)])
        if let id = highlightedElementID {
            let selected = home.space(id)?.label ?? home.portal(id).map { DisplayNames.name($0.kind.rawValue, localizer: model.localizer) }
                ?? home.annotations.first(where: { $0.id == id })?.localizedLabel(model.localizer)
            if let selected { summary += " " + model.localizer("spatial.selected-home-item") + ": " + selected }
        }
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
        // Hazard layers. Each state has its own pattern and badge, so none relies on colour alone:
        // origin = solid fill + badge; smoke = diagonal hatch; water = horizontal waves; exposure = dotted band.
        let water = spatialState?.hazard == .flashFlood
        var badges: [(CGPoint, String)] = []
        for room in spaces where spatialState?.affectedSpaceIDs.contains(room.id) == true {
            let shape = path(room.polygon, f, closed: true)
            let isOrigin = spatialState?.originSpaceID == room.id
            if isOrigin && !water {
                ctx.fill(shape, with: .color(PlanColors.alarm.opacity(0.32)))
            } else {
                ctx.fill(shape, with: .color(water ? Color.blue.opacity(0.16) : Color.gray.opacity(0.22)))
            }
            var clipped = ctx
            clipped.clip(to: shape)
            let box = shape.boundingRect
            var lines = Path()
            if water {
                var y = box.minY + 4
                while y < box.maxY { 
                    var x = box.minX; lines.move(to: CGPoint(x: x, y: y))
                    while x < box.maxX { lines.addQuadCurve(to: CGPoint(x: x + 8, y: y), control: CGPoint(x: x + 4, y: y - 3)); x += 8 }
                    y += 7
                }
                clipped.stroke(lines, with: .color(.blue.opacity(0.55)), lineWidth: 1)
            } else {
                var x = box.minX - box.height
                while x < box.maxX { lines.move(to: CGPoint(x: x, y: box.maxY)); lines.addLine(to: CGPoint(x: x + box.height, y: box.minY)); x += 7 }
                clipped.stroke(lines, with: .color(Color(.label).opacity(isOrigin ? 0.25 : 0.4)), lineWidth: 1)
            }
            badges.append((CGPoint(x: box.maxX - 13, y: box.minY + 27), isOrigin ? (water ? "water.waves" : "flame.fill") : (water ? "water.waves" : "smoke.fill")))
        }
        for room in spaces where spatialState?.exposedSpaceIDs?.contains(room.id) == true {
            ctx.stroke(path(room.polygon, f, closed: true), with: .color(.purple.opacity(0.75)), style: StrokeStyle(lineWidth: 3, dash: [1.5, 3.5]))
        }
        if let shelter = spatialState?.destinationSpaceID.flatMap({ home.space($0) }), shelter.floorID == fid {
            let shape = path(shelter.polygon, f, closed: true)
            ctx.stroke(shape, with: .color(PlanColors.exit), lineWidth: 6)
            ctx.stroke(shape, with: .color(PlanColors.background), lineWidth: 2)
            let sb = shape.boundingRect
            badges.append((CGPoint(x: sb.maxX - 13, y: sb.minY + 27), "shield.lefthalf.filled"))
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
                // A zigzag along the glass: a static exposure cue (also the Reduce Motion scene). It never reads as
                // "blocked" and illustrates why to move away from windows, not predicted structural damage.
                let a = f.pt(p.a), b = f.pt(p.b)
                let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 1)
                let nx = -dy / len * 4, ny = dx / len * 4
                var zig = Path(); zig.move(to: a)
                let steps = max(2, Int(len / 6))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), sign: CGFloat = i % 2 == 0 ? -1 : 1
                    zig.addLine(to: CGPoint(x: a.x + dx * t + (i == steps ? 0 : nx * sign), y: a.y + dy * t + (i == steps ? 0 : ny * sign)))
                }
                ctx.stroke(zig, with: .color(.purple), lineWidth: 2)
                badges.append((CGPoint(x: f.pt(p.center).x + nx * 3, y: f.pt(p.center).y + ny * 3), "exclamationmark.triangle.fill"))
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
            let symbol: String = switch connector.kind {
            case .stairs: "stairs"
            case .ramp: "figure.roll"
            case .elevator: "arrow.up.arrow.down.square"
            }
            let excluded = selectedRoute?.exclusions.contains { $0.elementID == connector.id } == true
                || (connector.kind == .elevator && spatialState?.hazard == .homeFire)
            for (floor, point) in [(room?.floorID, connector.fromPoint), (other?.floorID, connector.toPoint)] where floor == fid {
                ctx.draw(Text(Image(systemName: symbol)).font(.caption).foregroundStyle(excluded ? PlanColors.alarm : PlanColors.label), at: f.pt(point))
                if excluded { badges.append((f.pt(point), "xmark")) }
            }
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
        if let placementPoint {
            let point = f.pt(placementPoint)
            ctx.stroke(Path(ellipseIn: CGRect(origin: point, size: .zero).insetBy(dx: -10, dy: -10)), with: .color(.purple), lineWidth: 4)
            ctx.draw(Text(Image(systemName: "plus")).foregroundStyle(.purple), at: point)
        }
        for (point, symbol) in badges {
            let disc = CGRect(origin: point, size: .zero).insetBy(dx: -11, dy: -11).offsetBy(dx: 0, dy: -14)
            ctx.fill(Path(ellipseIn: disc), with: .color(PlanColors.background))
            ctx.stroke(Path(ellipseIn: disc), with: .color(Color(.label).opacity(0.5)), lineWidth: 1)
            let tint: Color = symbol == "flame.fill" ? PlanColors.alarm : symbol == "water.waves" ? .blue : symbol == "shield.lefthalf.filled" ? PlanColors.exit : symbol.hasPrefix("exclamation") ? .purple : Color(.label)
            ctx.draw(Text(Image(systemName: symbol)).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint), at: CGPoint(x: disc.midX, y: disc.midY))
        }
        for (i, r) in routes.enumerated() {
            for leg in r.legs where leg.floorID == fid && leg.points.count >= 2 {
                let style = StrokeStyle(lineWidth: i == 0 ? 5 : 3, lineCap: .round, lineJoin: .round, dash: i == 0 ? [] : [8, 5])
                // A white casing keeps the route legible over hatching.
                ctx.stroke(path(leg.points, f, closed: false), with: .color(PlanColors.background), style: StrokeStyle(lineWidth: style.lineWidth + 3, lineCap: .round, lineJoin: .round, dash: style.dash))
                ctx.stroke(path(leg.points, f, closed: false), with: .color(PlanColors.route), style: style)
                let n = leg.points.count
                let a = f.pt(leg.points[n - 2]), b = f.pt(leg.points[n - 1])
                let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001), ux = dx / len, uy = dy / len
                let size: CGFloat = i == 0 ? 11 : 8
                var head = Path(); head.move(to: b)
                head.addLine(to: CGPoint(x: b.x - ux * size - uy * size * 0.6, y: b.y - uy * size + ux * size * 0.6))
                head.addLine(to: CGPoint(x: b.x - ux * size + uy * size * 0.6, y: b.y - uy * size - ux * size * 0.6))
                head.closeSubpath()
                ctx.fill(head, with: .color(PlanColors.route))
            }
        }
        // The person: a black-ringed marker, never route blue, so it does not merge into the line. A start inside an
        // affected room keeps a red ring (exposure is retained, never erased to make a route appear).
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), room.floorID == fid,
           let position = HomeScenePresentation.startingRoomPosition(in: home, route: selectedRoute) {
            let c = f.pt(position)
            let exposedStart = spatialState?.affectedSpaceIDs.contains(room.id) == true
            let disc = CGRect(origin: c, size: .zero).insetBy(dx: -12, dy: -12)
            ctx.fill(Path(ellipseIn: disc.insetBy(dx: -2, dy: -2)), with: .color(PlanColors.background))
            ctx.fill(Path(ellipseIn: disc), with: .color(Color(.label)))
            ctx.stroke(Path(ellipseIn: disc.insetBy(dx: -2, dy: -2)), with: .color(exposedStart ? PlanColors.alarm : Color(.label)), lineWidth: exposedStart ? 3 : 1)
            ctx.draw(Text(Image(systemName: "person.fill")).font(.system(size: 13, weight: .bold)).foregroundStyle(PlanColors.background), at: c)
        }
        // Labels last, kept clear of the person marker, so routes and badges never hide a room's name.
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), room.floorID == fid,
           let position = HomeScenePresentation.startingRoomPosition(in: home, route: selectedRoute) {
            markers.append(f.pt(position))
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
