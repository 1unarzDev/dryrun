import Foundation

/// One household choice the host already validated at this receipt, described by person, purpose and
/// destination so a screen can say who does what, where, without inventing anything. Built only from
/// `HazardExperience.feasibleCommands`; selecting one still requires an atomic `SimulationSession.preview`
/// at the current revision before it is committed through the engine.
public struct HazardChoice: Sendable, Hashable, Identifiable {
    public enum Purpose: String, Sendable, Hashable, CaseIterable {
        case escape, accompanyEscape, accountOutside
        case shelter, accompanyShelter
        case refuge, depart
        case warmth, shade, moveToShade
        case power, contact, water, carrySupply, placeSupply
        case recognizeGap
    }
    public var purpose: Purpose
    public var command: SessionCommand
    /// The person who acts or is helped.
    public var personID: String?
    /// The exercise helper for accompaniment, from the current assistance when available.
    public var helperID: String?
    /// The room a person goes to (shelter, refuge, shaded room), the room an exit leaves from, or where a supply is put.
    public var roomID: String?
    public var exitPortalID: String?
    /// A recorded transport destination ID (never a person or a room).
    public var destinationID: String?
    public var equipmentID: String?
    public var backupID: String?
    public var contactID: String?
    public var itemID: String?
    public var gapID: String?
    /// `tap`, `recordedStored` or an inventory item ID, and the activity, for water use.
    public var waterSource: String?
    public var activity: String?
    public var quantityLiters: Double?
    /// Stable identity and accessibility suffix: kind, target and value.
    public var id: String { ([command.kind] + [command.target, command.value].compactMap { $0 }).joined(separator: ".") }
    /// Whether this choice is a preparation or response a family takes (not a recognition-only note).
    public var isAction: Bool { purpose != .recognizeGap }
}

public enum HazardChoices {
    /// Hazard-specific order: the primary objective of each hazard comes first.
    static func rank(_ purpose: HazardChoice.Purpose, hazard: HazardKind) -> Int {
        let order: [HazardChoice.Purpose]
        switch hazard {
        case .homeFire: order = [.accompanyEscape, .escape, .accountOutside]
        case .tornado: order = [.accompanyShelter, .shelter, .contact]
        case .flashFlood: order = [.depart, .refuge, .carrySupply, .placeSupply]
        case .freezePowerLoss: order = [.warmth, .power, .depart]
        case .heatGridStrain: order = [.shade, .moveToShade, .depart, .power]
        case .waterOutage: order = [.water]
        }
        if let index = order.firstIndex(of: purpose) { return index }
        return purpose == .recognizeGap ? 100 : 50
    }

    /// The receipt's host-validated hazard commands as described choices, primary objective first,
    /// then by household member order. Commands this describer does not know are left out rather than
    /// shown as a generic action.
    public static func options(_ receipt: SessionReceipt, household: HouseholdProfile, home: HomeModel?) -> [HazardChoice] {
        guard let experience = receipt.experience, let commands = experience.feasibleCommands else { return [] }
        let personOrder = Dictionary(household.people.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<SessionCommand>()
        var out: [HazardChoice] = []
        for command in commands where seen.insert(command).inserted {
            guard let choice = describe(command, receipt: receipt, household: household, home: home) else { continue }
            out.append(choice)
        }
        return out.enumerated().sorted { a, b in
            let ra = rank(a.element.purpose, hazard: experience.hazard), rb = rank(b.element.purpose, hazard: experience.hazard)
            if ra != rb { return ra < rb }
            let pa = a.element.personID.flatMap { personOrder[$0] } ?? Int.max, pb = b.element.personID.flatMap { personOrder[$0] } ?? Int.max
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The interior room an exterior exit leaves from, when recorded.
    public static func exitRoom(_ portalID: String, in home: HomeModel?) -> String? {
        guard let portal = home?.portal(portalID) else { return nil }
        for side in [portal.sideA, portal.sideB] { if case .space(let id) = side { return id } }
        return nil
    }

    /// Describes one command (feasible now or already committed) by person, purpose and destination;
    /// nil for commands that are not hazard choices.
    public static func describe(_ command: SessionCommand, receipt: SessionReceipt, household: HouseholdProfile, home: HomeModel?) -> HazardChoice? {
        var c = HazardChoice(purpose: .recognizeGap, command: command)
        func helper(for person: String?) -> String? {
            guard let person else { return nil }
            return receipt.assistance?.first(where: { $0.personID == person })?.helperID
                ?? household.people.first(where: { $0.id == person })?.helperPersonID
        }
        switch command.kind {
        case "escape":
            c.purpose = .escape; c.personID = command.target; c.exitPortalID = command.value
            c.roomID = command.value.flatMap { exitRoom($0, in: home) }
        case "accompanyEscape":
            c.purpose = .accompanyEscape; c.personID = command.target; c.helperID = helper(for: command.target)
            c.exitPortalID = command.value; c.roomID = command.value.flatMap { exitRoom($0, in: home) }
            guard c.helperID != nil else { return nil }
        case "accountOutside":
            c.purpose = .accountOutside; c.personID = command.target
        case "reachShelter":
            c.purpose = .shelter; c.personID = command.target; c.roomID = command.value
        case "accompanyShelter":
            c.purpose = .accompanyShelter; c.personID = command.target; c.helperID = command.value
            c.roomID = receipt.experience?.shelterRoomID
        case "reachHigherRefuge":
            c.purpose = .refuge; c.personID = command.target; c.roomID = command.value
        case "leaveEarly", "heatedAlternative", "cooledAlternative":
            c.purpose = .depart; c.destinationID = command.target
        case "warmLayers":
            c.purpose = .warmth
        case "reduceSolarGain":
            c.purpose = .shade; c.roomID = command.target
        case "moveTo":
            // Offered by the host only for heat: a heat-sensitive person into an already shaded room.
            guard receipt.experience?.hazard == .heatGridStrain else { return nil }
            c.purpose = .moveToShade; c.personID = command.target; c.roomID = command.value
        case "allocatePower":
            c.purpose = .power; c.equipmentID = command.target; c.backupID = command.value
        case "contact":
            c.purpose = .contact; c.contactID = command.target
        case "useWater":
            c.purpose = .water; c.waterSource = command.target; c.activity = command.value; c.quantityLiters = command.quantityLiters
        case "takeSupply":
            c.purpose = .carrySupply; c.itemID = command.target; c.personID = command.value
        case "transferSupply":
            c.purpose = .placeSupply; c.itemID = command.target; c.roomID = command.value
            c.personID = receipt.inventory?.items.first(where: { $0.id == command.target })?.carrierPersonID
        case "identifyGap":
            c.purpose = .recognizeGap; c.gapID = command.target
        default:
            return nil
        }
        return c
    }

    /// Whether the family may explicitly keep watching: a decision is requested, no authored question is due,
    /// and the session's mechanics support the recorded `wait` decision.
    public static func waitAvailable(session: SimulationSession, receipt: SessionReceipt, library: ScenarioLibrary) -> Bool {
        HazardExperience.level(session.mechanicsVersion) >= 6 && !receipt.finished
            && receipt.directorState?.awaitingUserAction == true
            && LocalDirector.dueChoice(session: session, receipt: receipt, library: library) == nil
    }
}
