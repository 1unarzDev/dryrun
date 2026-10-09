import Foundation

/// Practice-route planner over a VERIFIED portal graph with within-room geometric paths.
///
/// Order of operations (see docs/lanes/agent-b.md):
///  1. Hard exclusions (scenario blocks, unverified/rejected portals, unknown or common-area destinations,
///     windows as walking connections, non-ground exits, mobility/clearance incompatibility, invalid geometry).
///  2. Within-room paths: straight if clear of walls/obstacles by the clearance envelope, otherwise a
///     visibility-graph detour around obstacle and reflex-corner waypoints; rejected if neither works.
///  3. Dijkstra on the remaining edges with deterministic tie-breaking (cost, then node ID).
///  4. An alternative must use a different exterior exit AND avoid every interior chokepoint of the primary.
///
/// Output is a "practice route under these assumptions", never a real-time safety claim.
public struct EgressPlanner: EgressPlanning {
    public var tolerance: GeometryTolerance
    public init(tolerance: GeometryTolerance = .standard) { self.tolerance = tolerance }

    public func plan(_ request: RouteRequest, in home: HomeModel) -> RouteResult {
        let graph = Graph(home: home, request: request, tol: tolerance, extraBlockedSpaces: [], extraBlockedPortals: [], extraBlockedConnectors: [])
        let fingerprint = HomeFingerprint.of(home)
        func fail(_ reason: NoRouteReason) -> RouteResult {
            RouteResult(request: request, primary: nil, alternative: nil, alternativeStatus: .none, noRouteReason: reason,
                        exclusions: graph.exclusions, homeID: home.id, homeRevision: home.revision, homeFingerprint: fingerprint)
        }
        guard let startSpace = home.space(request.startSpaceID) else { return fail(.unknownStartSpace) }
        if request.exclusions.blockedSpaceIDs.contains(startSpace.id) { return fail(.blockedByScenario) }
        guard graph.startNode != nil else { return fail(.invalidGeometry) }

        guard let primary = graph.shortestPath() else {
            return fail(diagnose(request, home))
        }

        // Alternative: different exit, avoiding the primary's interior chokepoints.
        let chokeSpaces = Set(primary.spaceSequence.dropFirst())
        let chokePortals = Set(primary.portalSequence.filter { $0 != primary.exitPortalID })
        let chokeConnectors = Set(primary.connectorSequence)
        var alternative: RoutePath?
        var status: AlternativeStatus = .none
        var shared: [String] = []
        let strict = Graph(home: home, request: request, tol: tolerance, extraBlockedSpaces: chokeSpaces,
                           extraBlockedPortals: chokePortals.union([primary.exitPortalID]), extraBlockedConnectors: chokeConnectors)
        if let alt = strict.shortestPath() {
            alternative = alt
            status = .independent
        } else {
            let loose = Graph(home: home, request: request, tol: tolerance, extraBlockedSpaces: [],
                              extraBlockedPortals: [primary.exitPortalID], extraBlockedConnectors: [])
            if let alt = loose.shortestPath() {
                alternative = alt
                status = .sharesChokepoint
                let altElements = Set(alt.spaceSequence.dropFirst()).union(alt.portalSequence).union(alt.connectorSequence)
                shared = altElements.intersection(chokeSpaces.union(chokePortals).union(chokeConnectors)).sorted()
            }
        }
        return RouteResult(request: request, primary: primary, alternative: alternative, alternativeStatus: status,
                           sharedChokepoints: shared, noRouteReason: nil, exclusions: graph.exclusions,
                           homeID: home.id, homeRevision: home.revision, homeFingerprint: fingerprint)
    }

    /// Typed explanation by relaxing one constraint family at a time. Never fabricates a connection.
    private func diagnose(_ request: RouteRequest, _ home: HomeModel) -> NoRouteReason {
        var noScenario = request; noScenario.exclusions = .none
        var walking = request; walking.mobility = .walking
        var both = walking; both.exclusions = .none
        let reach: (RouteRequest) -> Bool = {
            Graph(home: home, request: $0, tol: tolerance, extraBlockedSpaces: [], extraBlockedPortals: [], extraBlockedConnectors: []).shortestPath() != nil
        }
        // A walker would get out under the same scenario -> the binding limit is this person's mobility.
        if reach(walking) { return .incompatibleMobility }
        if reach(noScenario) { return .blockedByScenario }
        if reach(both) { return .blockedByScenario }
        if home.portals.contains(where: { if case .commonArea = $0.sideA { return true }; if case .commonArea = $0.sideB { return true }; return false }) {
            return .missingBuildingPlan
        }
        let groundFloors = Set(home.floors.filter { Graph.isGround($0, tolerance) }.map(\.id))
        let anyVerifiedExit = home.portals.contains { $0.leadsToExterior && $0.verification == .verified && groundFloors.contains($0.floorID) && $0.kind != .window }
        return anyVerifiedExit ? .incompleteConnectivity : .noVerifiedExteriorExit
    }
}

// MARK: - Graph construction

struct Graph {
    struct Node {
        var id: String
        var floorID: String
        var spaceID: String?
        var point: Vec2
        var exitPortalID: String?
    }
    struct Edge {
        var to: Int
        var cost: Double
        var points: [Vec2]
        var floorID: String
        /// Set when crossing a portal into `intoSpace`.
        var portalID: String?
        var intoSpace: String?
        var connectorID: String?
        var toFloorID: String?
    }

    let home: HomeModel
    let request: RouteRequest
    let tol: GeometryTolerance
    let clearance: Double
    var nodes: [Node] = []
    var adjacency: [[Edge]] = []
    var exclusions: [RouteExclusion] = []
    var startNode: Int?
    var verificationNeeded: [String: [String]] = [:]  // portal ID -> notes

    static func isGround(_ f: Floor, _ tol: GeometryTolerance) -> Bool { f.level == 0 && f.elevationMeters <= tol.groundElevationMeters }

    init(home: HomeModel, request: RouteRequest, tol: GeometryTolerance,
         extraBlockedSpaces: Set<String>, extraBlockedPortals: Set<String>, extraBlockedConnectors: Set<String>) {
        self.home = home
        self.request = request
        self.tol = tol
        self.clearance = min(request.mobility.minimumClearWidthMeters / 2, tol.portalApproachMeters - 0.05)

        let blockedSpaces = Set(request.exclusions.blockedSpaceIDs).union(extraBlockedSpaces)
        let blockedPortals = Set(request.exclusions.blockedPortalIDs).union(extraBlockedPortals)
        let blockedConnectors = Set(request.exclusions.blockedConnectorIDs).union(extraBlockedConnectors)
        let floors = Dictionary(uniqueKeysWithValues: home.floors.map { ($0.id, $0) })
        let spaces = Dictionary(uniqueKeysWithValues: home.spaces.map { ($0.id, $0) })

        for id in request.exclusions.blockedSpaceIDs.sorted() { exclusions.append(RouteExclusion(elementID: id, reason: "blockedByScenario")) }

        func usable(_ spaceID: String) -> Space? {
            guard let s = spaces[spaceID], !blockedSpaces.contains(spaceID), Geometry.isSimplePolygon(s.polygon) else { return nil }
            return s
        }

        // Start node.
        if let s = usable(request.startSpaceID), let anchor = RoomPaths.anchor(in: s, home: home, clearance: clearance) {
            startNode = addNode(Node(id: "start", floorID: s.floorID, spaceID: s.id, point: anchor))
        }

        // Nodes in each space, to be connected pairwise afterwards.
        var spaceNodes: [String: [Int]] = [:]
        if let st = startNode, let sid = nodes[st].spaceID { spaceNodes[sid, default: []].append(st) }

        for portal in home.portals.sorted(by: { $0.id < $1.id }) {
            if let reason = portalExclusion(portal, floors: floors, blocked: blockedPortals) {
                if !extraBlockedPortals.contains(portal.id) || request.exclusions.blockedPortalIDs.contains(portal.id) {
                    exclusions.append(RouteExclusion(elementID: portal.id, reason: reason))
                }
                continue
            }
            // One shared attachment rule (shared edge, or a plausible wall between outlines). Near-touching
            // outlines never become adjacent; doors centred in thick scanned walls do.
            let attachment = PortalAttachment.check(portal, in: home, tolerance: tol)
            guard attachment.attached else {
                exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: \(attachment.reason ?? "not on its room boundary")"))
                continue
            }
            let n = Geometry.normalized(Vec2(-(portal.b.y - portal.a.y), portal.b.x - portal.a.x))
            let c = portal.center
            let wallHalf = (PortalAttachment.underlyingWall(portal, in: home, tolerance: tol)?.thicknessMeters ?? 0) / 2

            /// Approach point inside the space, offset past the wall band so the clearance envelope holds.
            func sideNode(_ dest: PortalDestination) -> (spaceID: String, point: Vec2, inward: Vec2)? {
                guard case .space(let sid) = dest, let s = usable(sid), s.floorID == portal.floorID else { return nil }
                let d = (attachment.centerOffset[sid] ?? 0) + tol.portalApproachMeters
                for dir in [n, n * -1] where Geometry.contains(s.polygon, c + dir * d) { return (sid, c + dir * d, dir) }
                return nil
            }

            switch (portal.sideA, portal.sideB) {
            case (.space, .space):
                guard let a = sideNode(portal.sideA), let b = sideNode(portal.sideB), a.inward != b.inward else {
                    let blockedSide = [portal.sideA, portal.sideB].contains { if case .space(let s) = $0 { return blockedSpaces.contains(s) }; return false }
                    if !blockedSide { exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: portal does not sit between its two spaces")) }
                    continue
                }
                guard crossingIsClear(portal, a.point, b.point) else {
                    exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: crossing intersects another wall")); continue
                }
                let ia = addNode(Node(id: "p:\(portal.id):\(a.spaceID)", floorID: portal.floorID, spaceID: a.spaceID, point: a.point))
                let ib = addNode(Node(id: "p:\(portal.id):\(b.spaceID)", floorID: portal.floorID, spaceID: b.spaceID, point: b.point))
                let pts = [a.point, c, b.point]
                let len = Geometry.polylineLength(pts)
                adjacency[ia].append(Edge(to: ib, cost: len, points: pts, floorID: portal.floorID, portalID: portal.id, intoSpace: b.spaceID))
                adjacency[ib].append(Edge(to: ia, cost: len, points: pts.reversed(), floorID: portal.floorID, portalID: portal.id, intoSpace: a.spaceID))
                spaceNodes[a.spaceID, default: []].append(ia)
                spaceNodes[b.spaceID, default: []].append(ib)
            case (.space, .exterior), (.exterior, .space):
                let inside = (portal.sideA == .exterior) ? portal.sideB : portal.sideA
                guard let a = sideNode(inside) else {
                    if case .space(let s) = inside, blockedSpaces.contains(s) { continue }
                    exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: exit is not on its space boundary")); continue
                }
                let outside = c - a.inward * (tol.portalApproachMeters + wallHalf)
                if home.spaces.contains(where: { $0.floorID == portal.floorID && Geometry.contains($0.polygon, outside) }) {
                    exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: 'exterior' side lies inside another space")); continue
                }
                guard crossingIsClear(portal, a.point, outside) else {
                    exclusions.append(RouteExclusion(elementID: portal.id, reason: "invalidGeometry: crossing intersects another wall")); continue
                }
                let ia = addNode(Node(id: "p:\(portal.id):\(a.spaceID)", floorID: portal.floorID, spaceID: a.spaceID, point: a.point))
                let ix = addNode(Node(id: "x:\(portal.id)", floorID: portal.floorID, spaceID: nil, point: outside, exitPortalID: portal.id))
                let pts = [a.point, c, outside]
                adjacency[ia].append(Edge(to: ix, cost: Geometry.polylineLength(pts), points: pts, floorID: portal.floorID, portalID: portal.id))
                spaceNodes[a.spaceID, default: []].append(ia)
            default:
                continue // portalExclusion already rejected unknown/common-area destinations
            }
        }

        for cn in home.connectors.sorted(by: { $0.id < $1.id }) {
            let reason: String?
            if blockedConnectors.contains(cn.id) { reason = request.exclusions.blockedConnectorIDs.contains(cn.id) ? "blockedByScenario" : nil }
            else if cn.verification != .verified { reason = "connectorNotVerified" }
            else if cn.kind == .elevator { reason = "elevatorNotUsedForEgress" }
            else if cn.kind == .stairs && request.mobility.requiresStepFree { reason = "incompatibleMobility: stairs" }
            else { reason = nil }
            if blockedConnectors.contains(cn.id) || reason != nil {
                if let reason { exclusions.append(RouteExclusion(elementID: cn.id, reason: reason)) }
                continue
            }
            guard let fs = usable(cn.fromSpaceID), let ts = usable(cn.toSpaceID),
                  Geometry.contains(fs.polygon, cn.fromPoint), Geometry.contains(ts.polygon, cn.toPoint) else {
                if !(blockedSpaces.contains(cn.fromSpaceID) || blockedSpaces.contains(cn.toSpaceID)) {
                    exclusions.append(RouteExclusion(elementID: cn.id, reason: "invalidGeometry: connector endpoints not inside their spaces"))
                }
                continue
            }
            let ia = addNode(Node(id: "c:\(cn.id):\(fs.id)", floorID: fs.floorID, spaceID: fs.id, point: cn.fromPoint))
            let ib = addNode(Node(id: "c:\(cn.id):\(ts.id)", floorID: ts.floorID, spaceID: ts.id, point: cn.toPoint))
            let rise = abs((floors[fs.floorID]?.elevationMeters ?? 0) - (floors[ts.floorID]?.elevationMeters ?? 0))
            // Stairs travel modelled as 2x the rise plus horizontal offset; a planning weight, not a timing claim.
            let cost = 2 * rise + cn.fromPoint.distance(to: cn.toPoint) + 1
            adjacency[ia].append(Edge(to: ib, cost: cost, points: [cn.toPoint], floorID: fs.floorID, connectorID: cn.id, toFloorID: ts.floorID))
            adjacency[ib].append(Edge(to: ia, cost: cost, points: [cn.fromPoint], floorID: ts.floorID, connectorID: cn.id, toFloorID: fs.floorID))
            spaceNodes[fs.id, default: []].append(ia)
            spaceNodes[ts.id, default: []].append(ib)
        }

        // Within-room edges.
        for sid in spaceNodes.keys.sorted() {
            guard let s = spaces[sid] else { continue }
            let ids = spaceNodes[sid]!
            for i in ids.indices {
                for j in ids.indices where j > i {
                    let a = ids[i], b = ids[j]
                    guard let pts = RoomPaths.path(from: nodes[a].point, to: nodes[b].point, in: s, home: home, clearance: clearance) else { continue }
                    let len = Geometry.polylineLength(pts)
                    adjacency[a].append(Edge(to: b, cost: len, points: pts, floorID: s.floorID))
                    adjacency[b].append(Edge(to: a, cost: len, points: pts.reversed(), floorID: s.floorID))
                }
            }
        }
    }

    private mutating func addNode(_ n: Node) -> Int {
        if let existing = nodes.firstIndex(where: { $0.id == n.id }) { return existing }
        nodes.append(n)
        adjacency.append([])
        return nodes.count - 1
    }

    /// The crossing polyline may meet walls only inside this portal's span (shrunk by the margin).
    private func crossingIsClear(_ portal: Portal, _ from: Vec2, _ to: Vec2) -> Bool {
        let dir = Geometry.normalized(portal.b - portal.a)
        let spanA = portal.a + dir * tol.portalSpanMarginMeters, spanB = portal.b - dir * tol.portalSpanMarginMeters
        let c = portal.center
        for (p, q) in [(from, c), (c, to)] {
            for w in home.walls where w.floorID == portal.floorID {
                if Geometry.collinearOverlap(p, q, w.a, w.b) { return false }
                if let x = Geometry.intersection(p, q, w.a, w.b), Geometry.distancePointSegment(x, spanA, spanB) > 1e-6 { return false }
            }
            for o in home.obstacles where o.floorID == portal.floorID {
                if Geometry.distanceSegmentPolygon(p, q, o.polygon) < 1e-6 { return false }
            }
        }
        return true
    }

    private mutating func portalExclusion(_ p: Portal, floors: [String: Floor], blocked: Set<String>) -> String? {
        if blocked.contains(p.id) { return "blockedByScenario" }
        switch p.verification {
        case .verified: break
        case .rejected: return "rejectedByHousehold"
        case .proposed, .unknown: return "portalNotVerified"
        }
        let sides = [p.sideA, p.sideB]
        if sides.contains(.unknown) { return "unknownDestination" }
        if sides.contains(where: { if case .commonArea = $0 { return true }; return false }) {
            return "commonAreaOutsideModel: building corridor/stairs are not modelled or verified"
        }
        if sides.allSatisfy({ $0 == .exterior }) { return "invalidGeometry: both sides exterior" }
        let isExit = p.leadsToExterior
        if p.kind == .window {
            guard isExit else { return "windowNotAWalkingConnection" }
        }
        if isExit {
            guard let f = floors[p.floorID], Graph.isGround(f, tol) else { return "notGroundLevelExit" }
        }
        if p.kind == .window {
            if request.mobility.requiresStepFree { return "incompatibleMobility: window exit" }
            if p.operable.confirmedValue != true { return "windowOperabilityUnconfirmed" }
        }
        if p.kind != .opening {
            if p.operable.value == false { return "inoperable" }            // even an unconfirmed "no" rules it out
            if p.operable.confirmedValue == nil { return "operabilityUnconfirmed" } // scan-observed never satisfies it
        }
        if request.mobility.requiresStepFree {
            if p.stepFree.value == false { return "incompatibleMobility: threshold step" }
            if p.stepFree.confirmedValue == nil { return "incompatibleMobility: step-free threshold unconfirmed" }
        }
        if let w = p.clearWidthMeters.value, w + 1e-9 < request.mobility.minimumClearWidthMeters {
            // Even an unconfirmed (scanned) narrow width is enough to rule an opening out.
            return "incompatibleMobility: clear width \(w) m below \(request.mobility.minimumClearWidthMeters) m"
        }
        if p.clearWidthMeters.confirmedValue != nil {
            // Confirmed and wide enough.
        } else if request.mobility.requiresStepFree {
            return p.clearWidthMeters.isKnown ? "incompatibleMobility: scanned clear width not confirmed" : "incompatibleMobility: clear width unknown (needs measurement)"
        } else {
            verificationNeeded[p.id, default: []].append("\(p.id).clearWidth")
        }
        if p.kind == .window { verificationNeeded[p.id, default: []].append("\(p.id).windowEscapeEveryPerson") }
        return nil
    }

    // MARK: Dijkstra (deterministic: cost, then node ID)

    func shortestPath() -> RoutePath? {
        guard let s = startNode else { return nil }
        var dist = [Double](repeating: .infinity, count: nodes.count)
        var prev = [(node: Int, edge: Int)?](repeating: nil, count: nodes.count)
        var done = [Bool](repeating: false, count: nodes.count)
        dist[s] = 0
        while true {
            var u = -1
            for i in nodes.indices where !done[i] && dist[i].isFinite {
                if u < 0 || dist[i] < dist[u] - 1e-9 || (abs(dist[i] - dist[u]) <= 1e-9 && nodes[i].id < nodes[u].id) { u = i }
            }
            if u < 0 { break }
            done[u] = true
            for (ei, e) in adjacency[u].enumerated() {
                let nd = dist[u] + e.cost
                if nd < dist[e.to] - 1e-9 { dist[e.to] = nd; prev[e.to] = (u, ei) }
            }
        }
        let exits = nodes.indices.filter { nodes[$0].exitPortalID != nil && dist[$0].isFinite }
        guard let best = exits.min(by: { dist[$0] < dist[$1] - 1e-9 || (abs(dist[$0] - dist[$1]) <= 1e-9 && nodes[$0].id < nodes[$1].id) }) else { return nil }

        var chain: [Edge] = []
        var cur = best
        while let p = prev[cur] { chain.append(adjacency[p.node][p.edge]); cur = p.node }
        chain.reverse()

        var legs: [RoutePath.Leg] = [RoutePath.Leg(floorID: nodes[s].floorID, points: [nodes[s].point])]
        var spaceSeq = [nodes[s].spaceID!]
        var portalSeq: [String] = [], connSeq: [String] = [], needs: [String] = []
        for e in chain {
            if let cid = e.connectorID, let tf = e.toFloorID {
                connSeq.append(cid)
                legs.append(RoutePath.Leg(floorID: tf, points: e.points))
                if let sp = nodes[e.to].spaceID, spaceSeq.last != sp { spaceSeq.append(sp) }
                continue
            }
            for pt in e.points where legs[legs.count - 1].points.last.map({ $0.distance(to: pt) > 1e-9 }) ?? true {
                legs[legs.count - 1].points.append(pt)
            }
            if let pid = e.portalID {
                portalSeq.append(pid)
                needs.append(contentsOf: verificationNeeded[pid] ?? [])
                if let into = e.intoSpace { spaceSeq.append(into) }
            }
        }
        let length = legs.reduce(0) { $0 + Geometry.polylineLength($1.points) }
        return RoutePath(legs: legs, spaceSequence: spaceSeq, portalSequence: portalSeq, connectorSequence: connSeq,
                         exitPortalID: nodes[best].exitPortalID!, lengthMeters: length, verificationNeeded: needs)
    }
}

// MARK: - Within-room geometry

public enum RoomPaths {
    /// Barriers relevant to a space: its own polygon edges plus explicit walls on the floor.
    static func barriers(_ space: Space, _ home: HomeModel) -> [(Vec2, Vec2)] {
        Geometry.edges(space.polygon) + home.walls.filter { $0.floorID == space.floorID }.map { ($0.a, $0.b) }
    }

    static func obstacles(_ space: Space, _ home: HomeModel) -> [[Vec2]] {
        home.obstacles.filter { $0.floorID == space.floorID }.map(\.polygon)
    }

    static func pointOK(_ p: Vec2, _ space: Space, _ bars: [(Vec2, Vec2)], _ obs: [[Vec2]], _ clearance: Double) -> Bool {
        guard Geometry.contains(space.polygon, p) else { return false }
        for (a, b) in bars where Geometry.distancePointSegment(p, a, b) < clearance - 1e-9 { return false }
        for o in obs where Geometry.contains(o, p) || Geometry.distanceToBoundary(o, p) < clearance - 1e-9 { return false }
        return true
    }

    /// A segment inside a room is valid if it crosses no wall/boundary, keeps the clearance envelope from
    /// obstacles, and stays inside the room polygon.
    public static func segmentOK(_ p: Vec2, _ q: Vec2, in space: Space, home: HomeModel, clearance: Double) -> Bool {
        segmentOK(p, q, space, barriers(space, home), obstacles(space, home), clearance)
    }

    static func segmentOK(_ p: Vec2, _ q: Vec2, _ space: Space, _ bars: [(Vec2, Vec2)], _ obs: [[Vec2]], _ clearance: Double) -> Bool {
        guard Geometry.contains(space.polygon, p), Geometry.contains(space.polygon, q) else { return false }
        for (a, b) in bars {
            if Geometry.intersection(p, q, a, b) != nil || Geometry.collinearOverlap(p, q, a, b) { return false }
            // Clearance envelope from walls and corners along the whole segment.
            if Geometry.distanceSegmentSegment(p, q, a, b) < clearance - 1e-9 { return false }
        }
        let mid = Vec2((p.x + q.x) / 2, (p.y + q.y) / 2)
        guard Geometry.contains(space.polygon, mid) else { return false }
        for o in obs where Geometry.distanceSegmentPolygon(p, q, o) < clearance - 1e-9 { return false }
        return true
    }

    /// Representative standing point: the centroid if it is valid, else the nearest valid grid point (0.25 m).
    public static func anchor(in space: Space, home: HomeModel, clearance: Double) -> Vec2? {
        let bars = barriers(space, home), obs = obstacles(space, home)
        let c = Geometry.centroid(space.polygon)
        if pointOK(c, space, bars, obs, clearance) { return c }
        let xs = space.polygon.map(\.x), ys = space.polygon.map(\.y)
        var best: Vec2?
        var x = xs.min()!
        while x <= xs.max()! {
            var y = ys.min()!
            while y <= ys.max()! {
                let p = Vec2(x, y)
                if pointOK(p, space, bars, obs, clearance), best.map({ p.distance(to: c) < $0.distance(to: c) - 1e-12 }) ?? true { best = p }
                y += 0.25
            }
            x += 0.25
        }
        return best
    }

    /// Straight path if valid; otherwise shortest visibility-graph path through detour waypoints; nil if none.
    public static func path(from p: Vec2, to q: Vec2, in space: Space, home: HomeModel, clearance: Double) -> [Vec2]? {
        let bars = barriers(space, home), obs = obstacles(space, home)
        if segmentOK(p, q, space, bars, obs, clearance) { return [p, q] }

        // Candidate waypoints: obstacle corners pushed outward, room corners pushed inward, interior wall ends.
        let push = clearance + 0.1
        var wps: [Vec2] = []
        for o in obs {
            let c = Geometry.centroid(o)
            for v in o { wps.append(v + Geometry.normalized(v - c) * (push * 1.5)) }
        }
        let poly = Geometry.signedArea(space.polygon) >= 0 ? space.polygon : space.polygon.reversed()
        for i in poly.indices {
            let prev = poly[(i + poly.count - 1) % poly.count], v = poly[i], next = poly[(i + 1) % poly.count]
            let d1 = Geometry.normalized(v - prev), d2 = Geometry.normalized(next - v)
            let n1 = Vec2(-d1.y, d1.x), n2 = Vec2(-d2.y, d2.x) // inward (left) normals for CCW
            let bis = Geometry.normalized(n1 + n2)
            let k = max(0.3, Geometry.dot(bis, n1))
            wps.append(v + bis * (push / k))
        }
        for w in home.walls where w.floorID == space.floorID {
            for e in [w.a, w.b] {
                for d in [Vec2(1, 1), Vec2(1, -1), Vec2(-1, 1), Vec2(-1, -1)] { wps.append(e + Geometry.normalized(d) * (push * 1.5)) }
            }
        }
        let pts = [p, q] + wps.filter { pointOK($0, space, bars, obs, clearance) }
        // Dijkstra over the visibility graph; deterministic by index.
        var dist = [Double](repeating: .infinity, count: pts.count)
        var prev = [Int?](repeating: nil, count: pts.count)
        var done = [Bool](repeating: false, count: pts.count)
        dist[0] = 0
        while true {
            var u = -1
            for i in pts.indices where !done[i] && dist[i].isFinite && (u < 0 || dist[i] < dist[u]) { u = i }
            if u < 0 || u == 1 { break }
            done[u] = true
            for v in pts.indices where !done[v] && v != u {
                let nd = dist[u] + pts[u].distance(to: pts[v])
                if nd < dist[v] - 1e-12, segmentOK(pts[u], pts[v], space, bars, obs, clearance) { dist[v] = nd; prev[v] = u }
            }
        }
        guard dist[1].isFinite else { return nil }
        var out = [pts[1]]
        var cur = 1
        while let pr = prev[cur] { out.append(pts[pr]); cur = pr }
        return out.reversed()
    }
}

// MARK: - Audit (used by tests and by the UI before drawing)

public enum RouteGeometryAudit {
    /// Returns human-readable violations: any drawn segment that crosses a wall outside a portal span on a
    /// portal the route actually uses, or enters an obstacle.
    public static func violations(_ path: RoutePath, in home: HomeModel, tolerance: GeometryTolerance = .standard) -> [String] {
        var out: [String] = []
        let used = Set(path.portalSequence)
        for leg in path.legs {
            let spans = home.portals.filter { used.contains($0.id) && $0.floorID == leg.floorID }.map { p -> (Vec2, Vec2, Double) in
                let d = Geometry.normalized(p.b - p.a)
                // Band half-width: how far the portal sits from the outlines it joins (0 for a shared edge).
                let band = PortalAttachment.check(p, in: home, tolerance: tolerance).centerOffset.values.max() ?? 0
                return (p.a + d * tolerance.portalSpanMarginMeters, p.b - d * tolerance.portalSpanMarginMeters, band + 1e-6)
            }
            for (p, q) in zip(leg.points, leg.points.dropFirst()) {
                for w in home.walls where w.floorID == leg.floorID {
                    if Geometry.collinearOverlap(p, q, w.a, w.b) { out.append("segment runs along wall \(w.id)") }
                    if let x = Geometry.intersection(p, q, w.a, w.b),
                       !spans.contains(where: { Geometry.distancePointSegment(x, $0.0, $0.1) <= $0.2 }) {
                        out.append("segment crosses wall \(w.id) at (\(x.x), \(x.y))")
                    }
                }
                for s in home.spaces where s.floorID == leg.floorID {
                    for (a, b) in Geometry.edges(s.polygon) {
                        if let x = Geometry.intersection(p, q, a, b),
                           !spans.contains(where: { Geometry.distancePointSegment(x, $0.0, $0.1) <= $0.2 }) {
                            out.append("segment crosses boundary of \(s.id) at (\(x.x), \(x.y))")
                        }
                    }
                }
                for o in home.obstacles where o.floorID == leg.floorID && Geometry.distanceSegmentPolygon(p, q, o.polygon) < 1e-6 {
                    out.append("segment enters obstacle \(o.id)")
                }
            }
        }
        return out
    }
}
