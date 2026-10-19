import Foundation

/// Shared drawing semantics, not an independent route planner. An available threshold is never a promise
/// that a complete route exists; route lines still come exclusively from EgressPlanner.
public enum HomeScenePresentation {
    public enum OpeningStatus: Sendable, Hashable { case availableExit, confirmedConnection, window, unconfirmed, unavailable }

    public static func openingStatus(_ portal: Portal, in home: HomeModel, state: SpatialExerciseState? = nil,
                                     request: RouteRequest? = nil) -> OpeningStatus {
        let sides = [portal.sideA, portal.sideB]
        let roomIDs = sides.compactMap { if case .space(let id) = $0 { return id }; return nil }
        let blockedRooms = Set((state?.affectedSpaceIDs ?? []) + (request?.exclusions.blockedSpaceIDs ?? []))
        let blockedPortals = Set((state?.affectedPortalIDs ?? []) + (request?.exclusions.blockedPortalIDs ?? []))
        if blockedPortals.contains(portal.id) || roomIDs.contains(where: blockedRooms.contains)
            || portal.verification == .rejected || portal.operable.value == false { return .unavailable }
        guard portal.verification == .verified,
              !sides.contains(.unknown), !sides.contains(where: { if case .commonArea = $0 { return true }; return false }),
              !roomIDs.isEmpty,
              roomIDs.allSatisfy({ home.space($0)?.geometryNeedsReview != true && home.space($0) != nil }),
              PortalAttachment.check(portal, in: home).attached,
              portal.kind == .opening || portal.operable.confirmedValue == true else { return .unconfirmed }
        if let mobility = request?.mobility {
            if mobility.requiresStepFree && portal.stepFree.confirmedValue != true { return .unavailable }
            if let width = portal.clearWidthMeters.value, width < mobility.minimumClearWidthMeters { return .unavailable }
            if mobility.requiresStepFree && portal.clearWidthMeters.confirmedValue == nil { return .unconfirmed }
        }
        // Windows remain inventory symbols, including separately reviewed emergency escape options.
        if portal.kind == .window { return .window }
        if portal.leadsToExterior {
            guard let floor = home.floors.first(where: { $0.id == portal.floorID }),
                  Graph.isGround(floor, .standard), !(home.source == .roomPlanScan && floor.exteriorGrade == nil) else { return .unavailable }
            return .availableExit
        }
        return .confirmedConnection
    }

    /// The exercise records a room, not a measured/live person position. Render an illustrative room marker.
    public static func startingRoom(in home: HomeModel, route: RouteResult?) -> Space? {
        route.flatMap { home.space($0.request.startSpaceID) }
    }

    public static func startingRoomPosition(in home: HomeModel, route: RouteResult?) -> Vec2? {
        guard let room = startingRoom(in: home, route: route), room.polygon.count >= 3,
              room.polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        return RoomPaths.anchor(in: room, home: home, clearance: 0)
    }

    public static func floorID(for elementID: String, in home: HomeModel, connectorDestination: Bool = false) -> String? {
        if home.floors.contains(where: { $0.id == elementID }) { return elementID }
        return home.space(elementID)?.floorID ?? home.portal(elementID)?.floorID
            ?? home.annotations.first(where: { $0.id == elementID })?.floorID
            ?? home.obstacles.first(where: { $0.id == elementID })?.floorID
            ?? home.connectors.first(where: { $0.id == elementID }).flatMap {
                home.space(connectorDestination ? $0.toSpaceID : $0.fromSpaceID)?.floorID
            }
    }

    public static func sceneFloorID(in home: HomeModel, selected: String?, route: RouteResult?, destinationID: String?) -> String? {
        if let selected, home.floors.contains(where: { $0.id == selected }) { return selected }
        return startingRoom(in: home, route: route)?.floorID
            ?? route?.primary?.legs.first?.floorID
            ?? destinationID.flatMap { floorID(for: $0, in: home) }
            ?? home.floors.first?.id
    }

    /// Names in pickers and route text must disambiguate identical rooms across floors.
    /// This labels recorded geometry only; no room use or grade is inferred from the name.
    public static func roomLabel(_ roomID: String, in home: HomeModel) -> String {
        guard let room = home.space(roomID) else { return roomID }
        guard home.floors.count > 1 else { return room.label }
        let floor = home.floors.first { $0.id == room.floorID }
        return "\(room.label) · \(floor?.label ?? room.floorID)"
    }

    public static func alternativeKey(_ route: RouteResult) -> String {
        switch route.alternativeStatus {
        case .independent: "common.route.independent"
        case .sharesChokepoint: "common.route.shared"
        case .none: "common.route.none"
        }
    }

    public static func alternativeSymbol(_ route: RouteResult) -> String {
        switch route.alternativeStatus {
        case .independent: "arrow.triangle.branch"
        case .sharesChokepoint: "arrow.triangle.merge"
        case .none: "exclamationmark.triangle"
        }
    }

    /// Empty means intentionally unknown. Invalid nonempty edits retain the last recorded fact until corrected.
    public static func editedWidth(_ text: String, previous: EvidenceValue<Double>) -> EvidenceValue<Double> {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return .unknown }
        guard let value = Double(cleaned.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return previous }
        return .confirmed(value, unit: "m")
    }
}
