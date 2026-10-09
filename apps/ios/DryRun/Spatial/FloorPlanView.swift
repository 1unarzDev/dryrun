import SwiftUI
import DryRunCore

// 2D floor plan drawn from the canonical HomeModel. Route lines use exactly the RoutePath points
// (no smoothing), so the drawing can never shortcut through a wall that the planner avoided.
// AUTHORED, NOT COMPILED in this environment.

struct FloorPlanView: View {
    let home: HomeModel
    let routes: [RoutePath]
    let highlightedFloorID: String?
    @State private var selectedFloorID: String?

    init(home: HomeModel, routes: [RoutePath], highlightedFloorID: String?) {
        self.home = home
        self.routes = routes
        self.highlightedFloorID = highlightedFloorID
    }

    private var floorID: String? { selectedFloorID ?? highlightedFloorID ?? home.floors.first?.id }

    var body: some View {
        VStack(spacing: 6) {
            if home.floors.count > 1 && highlightedFloorID == nil || routeFloors.count > 1 {
                Picker("Floor", selection: Binding(get: { floorID ?? "" }, set: { selectedFloorID = $0 })) {
                    ForEach(home.floors) { f in
                        Text(routeFloors.contains(f.id) ? "\(f.label) (route)" : f.label).tag(f.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .background(PlanColors.background)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("The room list gives the same information as text.")
            legend
        }
        .onChange(of: highlightedFloorID) { _, _ in selectedFloorID = nil }
    }

    private var routeFloors: Set<String> { Set(routes.flatMap { $0.legs.map(\.floorID) }) }

    private var legend: some View {
        HStack(spacing: 12) {
            Label("Verified exit", systemImage: "door.left.hand.open").foregroundStyle(PlanColors.exit)
            Label("Unconfirmed", systemImage: "questionmark.diamond").foregroundStyle(PlanColors.unverified)
            if !routes.isEmpty { Label("Practice route", systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(PlanColors.route) }
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
        .padding(.bottom, 4)
    }

    private var accessibilitySummary: String {
        guard let fid = floorID, let floor = home.floors.first(where: { $0.id == fid }) else { return "Floor plan" }
        let rooms = home.spaces.filter { $0.floorID == fid }.map(\.label).joined(separator: ", ")
        let exits = home.portals.filter { $0.floorID == fid && $0.leadsToExterior && $0.verification == .verified && $0.kind != .window }.count
        return "\(floor.label) floor plan. Rooms: \(rooms). \(exits) verified exterior door\(exits == 1 ? "" : "s")."
    }

    // MARK: Drawing

    private struct Fit {
        let scale: Double, minX: Double, maxY: Double, pad: Double
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: pad + (v.x - minX) * scale, y: pad + (maxY - v.y) * scale) }
    }

    private func fit(_ size: CGSize, _ fid: String) -> Fit? {
        var pts = home.spaces.filter { $0.floorID == fid }.flatMap(\.polygon)
        pts += home.annotations.filter { $0.floorID == fid && $0.spaceID == nil }.compactMap(\.position)
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return nil }
        let pad = 18.0
        let w = max(maxX - minX, 0.5), h = max(maxY - minY, 0.5)
        let scale = min((Double(size.width) - 2 * pad) / w, (Double(size.height) - 2 * pad) / h)
        return Fit(scale: max(scale, 1), minX: minX, maxY: maxY, pad: pad)
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
            let verifiedExit = p.leadsToExterior && p.verification == .verified && p.kind != .window
            let style: StrokeStyle = p.verification == .verified ? StrokeStyle(lineWidth: 3) : StrokeStyle(lineWidth: 2, dash: [3, 3])
            let color: Color = p.kind == .window ? PlanColors.window : verifiedExit ? PlanColors.exit : p.verification == .verified ? PlanColors.door : PlanColors.unverified
            ctx.stroke(line, with: .color(color), style: style)
            if verifiedExit {
                ctx.draw(Text("EXIT").font(.system(size: 9, weight: .bold)).foregroundStyle(PlanColors.exit), at: f.pt(p.center), anchor: .center)
            } else if p.verification != .verified && p.kind != .window {
                ctx.draw(Text("?").font(.system(size: 11, weight: .bold)).foregroundStyle(PlanColors.unverified), at: f.pt(p.center), anchor: .center)
            }
        }
        for s in spaces {
            let c = Geometry.centroid(s.polygon)
            ctx.draw(Text(s.label).font(.caption2).foregroundStyle(PlanColors.label), at: f.pt(c), anchor: .center)
        }
        for a in home.annotations where a.floorID == fid {
            guard let pos = a.position else { continue }
            ctx.draw(Text(Image(systemName: Self.symbol(a.kind))).font(.system(size: 13)).foregroundStyle(Self.color(a.kind)), at: f.pt(pos), anchor: .center)
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
