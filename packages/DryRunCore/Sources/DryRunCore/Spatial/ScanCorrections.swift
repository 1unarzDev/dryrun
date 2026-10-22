import Foundation

/// The geometry RoomPlan captured, frozen at import (see `HomeModel.scanSnapshot`).
public struct ScanSnapshot: Codable, Sendable, Hashable {
    public var floors: [Floor]
    public var spaces: [Space]
    public var walls: [WallSegment]
    public var portals: [Portal]
    public var obstacles: [Obstacle]
    public var connectors: [FloorConnector]
    public init(_ home: HomeModel) {
        floors = home.floors; spaces = home.spaces; walls = home.walls
        portals = home.portals; obstacles = home.obstacles; connectors = home.connectors
    }
}

/// Fast, reversible corrections to a scanned home: one opening at a time, or the whole home back to the scan.
/// Every change is a draft edit; the durable revision still advances once per save (HomeEditTransaction).
public enum ScanCorrections {
    public enum OpeningType: String, Codable, Sendable, CaseIterable { case door, window, openDoorway, notAnOpening }
    public enum CorrectionError: Error, Equatable, Sendable { case missingOpening, noScan, notInScan, invalidRoom }

    public static func type(of portal: Portal) -> OpeningType {
        switch portal.kind {
        case .window: .window
        case .opening: .openDoorway
        case .door, .slidingDoor, .garageDoor: .door
        }
    }

    /// The family's answer to "what is this?". A changed kind loses kind-specific facts (operability, escape
    /// suitability) because they described something else; the opening keeps its identity, endpoints and sides.
    /// "Not an opening" removes it from routes; Restore brings the scanned one back.
    public static func setType(_ id: String, to type: OpeningType, in home: inout HomeModel) throws {
        guard let index = home.portals.firstIndex(where: { $0.id == id }) else { throw CorrectionError.missingOpening }
        if type == .notAnOpening { home.portals.remove(at: index); return }
        let kind: PortalKind
        switch type {
        case .window: kind = .window
        case .openDoorway: kind = .opening
        case .door: kind = Self.type(of: home.portals[index]) == .door ? home.portals[index].kind : .door
        case .notAnOpening: return
        }
        if home.portals[index].kind != kind {
            home.portals[index].kind = kind
            home.portals[index].operable = kind == .opening ? .confirmed(true) : .unknown
            home.portals[index].emergencyEscapeConfirmed = nil
            home.portals[index].emergencyEscapePersonIDs = nil
        }
        home.portals[index].verification = .verified
    }

    /// "Leads to": the side away from `roomID` becomes `destination` (a room or outside). Confirms the connection.
    public static func setLeadsTo(_ id: String, from roomID: String, to destination: PortalDestination, in home: inout HomeModel) throws {
        guard let index = home.portals.firstIndex(where: { $0.id == id }) else { throw CorrectionError.missingOpening }
        if case .space(let target) = destination, target == roomID || home.space(target) == nil { throw CorrectionError.invalidRoom }
        var portal = home.portals[index]
        if portal.sideA == .space(roomID) { portal.sideB = destination }
        else if portal.sideB == .space(roomID) { portal.sideA = destination }
        else { portal.sideA = .space(roomID); portal.sideB = destination }
        portal.verification = .verified
        home.portals[index] = portal
    }

    /// Reversible "Not usable" (blocked, painted shut…): off restores what was known before, never invents "usable".
    public static func setNotUsable(_ id: String, _ notUsable: Bool, in home: inout HomeModel) throws {
        guard let index = home.portals.firstIndex(where: { $0.id == id }) else { throw CorrectionError.missingOpening }
        if notUsable { home.portals[index].operable = .confirmed(false); return }
        let scanned = home.scanSnapshot?.portals.first { $0.id == id }?.operable
        home.portals[index].operable = scanned.flatMap { $0.confirmedValue == false ? nil : $0 } ?? (home.portals[index].kind == .opening ? .confirmed(true) : .unknown)
    }

    public static func isNotUsable(_ portal: Portal) -> Bool { portal.operable.confirmedValue == false }

    /// "Restore what the scan saw" for one opening (also brings back one marked "Not an opening").
    public static func restore(_ id: String, in home: inout HomeModel) throws {
        guard let snapshot = home.scanSnapshot else { throw CorrectionError.noScan }
        guard let scanned = snapshot.portals.first(where: { $0.id == id }) else { throw CorrectionError.notInScan }
        if let index = home.portals.firstIndex(where: { $0.id == id }) { home.portals[index] = scanned }
        else {
            let order = snapshot.portals.map(\.id)
            let position = home.portals.firstIndex { (order.firstIndex(of: $0.id) ?? .max) > (order.firstIndex(of: id) ?? .max) } ?? home.portals.endIndex
            home.portals.insert(scanned, at: position)
        }
    }

    /// Openings removed as "Not an opening" that Restore can bring back.
    public static func removedOpenings(_ home: HomeModel) -> [Portal] {
        guard let snapshot = home.scanSnapshot else { return [] }
        let present = Set(home.portals.map(\.id))
        return snapshot.portals.filter { !present.contains($0.id) }
    }

    /// "Revert whole home to scan": geometry back to the capture; markers stay where their rooms still exist; residents'
    /// starting rooms are the caller's to re-check. Identity, label and revision are unchanged (save advances it).
    public static func revertToScan(_ home: inout HomeModel) throws {
        guard let snapshot = home.scanSnapshot else { throw CorrectionError.noScan }
        home.floors = snapshot.floors; home.spaces = snapshot.spaces; home.walls = snapshot.walls
        home.portals = snapshot.portals; home.obstacles = snapshot.obstacles; home.connectors = snapshot.connectors
        home.originalCapturedWalls = nil
        let rooms = Set(home.spaces.map(\.id)), floors = Set(home.floors.map(\.id))
        home.annotations = home.annotations.filter { a in
            (a.spaceID.map(rooms.contains) ?? true) && (a.floorID.map(floors.contains) ?? true)
        }
    }

    /// The rooms on each side of an opening, for highlighting both sides of a "Leads to" answer on the plan.
    public static func sideRoomIDs(_ portal: Portal) -> [String] {
        [portal.sideA, portal.sideB].compactMap { if case .space(let id) = $0 { return id }; return nil }
    }

    /// Rooms "Leads to" may offer from `roomID`: same floor, with the opening's centre within scan attach distance of
    /// the room's outline (the same rule ScanImport used to propose sides), never `roomID` itself. The opening's
    /// current other side is always kept so the picker never hides the recorded answer. Captured geometry is not
    /// moved, so a room that does not touch the opening is never offered.
    public static func leadsToRooms(_ portalID: String, from roomID: String, in home: HomeModel,
                                    tolerance: GeometryTolerance = .standard) -> [String] {
        guard let portal = home.portal(portalID) else { return [] }
        let current = Set(sideRoomIDs(portal)).subtracting([roomID])
        return home.spaces.filter { space in
            space.id != roomID && space.floorID == portal.floorID
                && (current.contains(space.id) || Geometry.distanceToBoundary(space.polygon, portal.center) <= tolerance.scanPortalAttachMeters)
        }.map(\.id)
    }

    /// Openings the guided "Check your scan" pass asks about, floor by floor.
    public static func uncertainOpenings(_ home: HomeModel) -> [Portal] {
        let floorOrder = Dictionary(uniqueKeysWithValues: home.floors.map { ($0.id, $0.level) })
        return home.portals.filter { $0.verification != .verified }
            .sorted { (floorOrder[$0.floorID] ?? 0, $0.center.x, $0.center.y) < (floorOrder[$1.floorID] ?? 0, $1.center.x, $1.center.y) }
    }
}

/// Undo/redo across saves for one home: the last `limit` versions.
public struct HomeEditHistory: Codable, Sendable, Hashable {
    public var homeID: String
    public private(set) var undoStack: [HomeModel] = []
    public private(set) var redoStack: [HomeModel] = []
    public var limit = 20
    public init(homeID: String) { self.homeID = homeID }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// A new saved version replaced `previous`: it can be undone, and any redo branch is gone.
    public mutating func recordSave(replacing previous: HomeModel) {
        guard previous.id == homeID else { return }
        undoStack.append(previous)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    /// The version to save in place of `current`; nil when there is nothing to undo.
    public mutating func undo(from current: HomeModel) -> HomeModel? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public mutating func redo(from current: HomeModel) -> HomeModel? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
