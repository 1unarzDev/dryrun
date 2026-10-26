import Foundation

/// The last canonical stage of a selected exercise, including its exclusions and explicit no-route state.
public struct PlanExerciseSnapshot: Codable, Sendable, Hashable {
    public var scenarioID: String
    public var state: SpatialExerciseState
    public init(scenarioID: String, state: SpatialExerciseState) { self.scenarioID = scenarioID; self.state = state }
}

/// Both native preview and print use these exact floor/path panels. A baseline never borrows an exercise route.
public struct PlanHomePanel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var floorID: String
    public var scenarioID: String?
    public var route: RouteResult?
    public var spatialState: SpatialExerciseState?
    public var paths: [RoutePath] { [route?.primary, route?.alternative].compactMap { $0 } }

    public func title(in snapshot: PlanVisualSnapshot) -> String {
        let floor = snapshot.home?.floors.first { $0.id == floorID }?.label ?? floorID
        guard let scenarioID else { return floor }
        let scenario = snapshot.scenarioLabels?[scenarioID] ?? scenarioID
        let person = route?.request.personID.flatMap { snapshot.personLabels?[$0] }
        return [scenario, person, floor].compactMap { $0 }.joined(separator: " · ")
    }

    public func details(in snapshot: PlanVisualSnapshot, localizer l: Localizer) -> [String] {
        guard scenarioID != nil else { return [] }
        // Legacy documents resolve through the same versioned content packs as new documents.
        // Missing/corrupt packs must leave useful words rather than internal localization keys.
        var usedEnglishFallback = false
        func text(_ key: String, _ fallback: String, _ values: [String: String] = [:]) -> String {
            let resolved = l.text(key, values)
            guard resolved.isMissing else { return resolved.text }
            usedEnglishFallback = true
            return Localizer.fill(fallback, values)
        }
        var details = [text("common.practiceLabel", "Practice scenario")]
        if let state = spatialState {
            details.append(state.assumptionKey.map { text($0, state.assumption) } ?? state.assumption)
        }
        if let room = snapshot.home.flatMap({ HomeScenePresentation.startingRoom(in: $0, route: route) }) {
            details.append(text("spatial.recorded-start-room", "Recorded starting room: {room}. The marker represents the room, not a live position.", ["room": room.label]))
        } else if route != nil {
            details.append(text("spatial.start-room-unknown", "Starting room not recorded. No position is assumed."))
        }
        if let route, route.primary == nil {
            let start = snapshot.home?.space(route.request.startSpaceID)?.label ?? text("plan.route.unknownRoom", "an unrecorded room")
            let reason = route.noRouteReason ?? .incompleteConnectivity
            let fallback: String
            switch reason {
            case .noVerifiedExteriorExit: fallback = "no verified exterior exit"
            case .incompleteConnectivity: fallback = "room connections are not confirmed"
            case .incompatibleMobility: fallback = "the route needs steps or a narrower opening than this person can use"
            case .blockedByScenario: fallback = "blocked in this exercise"
            case .missingBuildingPlan: fallback = "the building route outside your home is not known"
            case .invalidGeometry: fallback = "the home layout has a geometry problem"
            case .unknownStartSpace: fallback = "the starting room is not in the home model"
            }
            details.append(text("plan.route.none", "No verified practice route from {start}: {reason}.", ["start": start, "reason": text("plan.route.reason.\(reason.rawValue)", fallback)]))
        }
        if route?.primary != nil { details.append(text("plan.route.legend.primary", "Solid line: primary practice route.")) }
        if route?.alternative != nil { details.append(text("plan.route.legend.alternative", "Dashed line: alternative practice route.")) }
        if route?.alternativeStatus == .independent { details.append(text("common.route.independent", "Independent second way out available.")) }
        if route?.alternativeStatus == .sharesChokepoint { details.append(text("common.route.shared", "Second way out shares a chokepoint; not independent.")) }
        details.append(text("plan.route.caveat", "Practice route under these assumptions only. It is not a real-time safest route; check your actual doors and windows."))
        if usedEnglishFallback && l.locale != "en" { details.append("English fallback: some diagram details are unavailable in the selected language.") }
        return details
    }
}

public extension PlanVisualSnapshot {
    /// A route does not hide hazard or destination floors outside its path. Qualified panels retain
    /// the recorded starting room and all current scene floors, including an explicit failed path.
    var homePanels: [PlanHomePanel] {
        guard let home else { return [] }
        var panels = home.floors.map { PlanHomePanel(id: "baseline|\($0.id)", floorID: $0.id) }
        for (index, route) in routes.enumerated() {
            let scenario = routeScenarioIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            let state = exerciseStates?.first { $0.scenarioID == scenario }?.state
            var floors = Set([route.primary, route.alternative].compactMap { $0 }.flatMap { $0.legs.map(\.floorID) })
            if let floor = home.space(route.request.startSpaceID)?.floorID { floors.insert(floor) }
            if let destination = route.request.destinationSpaceID.flatMap({ home.space($0)?.floorID }) { floors.insert(destination) }
            if let state {
                let sceneRooms = Set(state.affectedSpaceIDs + (state.exposedSpaceIDs ?? []) + [state.originSpaceID, state.destinationSpaceID].compactMap { $0 })
                floors.formUnion(home.spaces.filter { sceneRooms.contains($0.id) }.map(\.floorID))
                floors.formUnion(home.portals.filter { state.affectedPortalIDs.contains($0.id) }.map(\.floorID))
            }
            if floors.isEmpty { floors.formUnion(home.floors.map(\.id)) }
            for floor in home.floors where floors.contains(floor.id) {
                panels.append(PlanHomePanel(id: "route|\(index)|\(floor.id)", floorID: floor.id, scenarioID: scenario,
                                           route: route, spatialState: state))
            }
        }
        for exercise in exerciseStates ?? [] where exercise.state.routes.isEmpty {
            for floor in home.floors {
                panels.append(PlanHomePanel(id: "scene|\(exercise.scenarioID)|\(floor.id)", floorID: floor.id,
                                           scenarioID: exercise.scenarioID, spatialState: exercise.state))
            }
        }
        return panels
    }
}
