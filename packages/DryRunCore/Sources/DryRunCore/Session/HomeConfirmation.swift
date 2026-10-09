import Foundation

/// Guided confirmation pass after a scan (or manual edits): label rooms, confirm doors/connections, identify exterior
/// exits, inspect unknown openings, confirm stairs, choose a meeting point, and mark shelter/measurement needs.
/// Nothing becomes verified except through an explicit `ConfirmationAnswer`.
public enum ConfirmationStepKind: String, Codable, Sendable, Hashable {
    case labelSpace, confirmPortal, confirmConnector, meetingPoint, shelterSpot
}

public struct ConfirmationStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(elementID)" }
    public var kind: ConfirmationStepKind
    public var elementID: String
    /// Short English prompt for the first build (moves to locale packs with the UI-chrome pass).
    public var prompt: String
}

public enum ConfirmationAnswer: Codable, Sendable, Hashable {
    case labelSpace(spaceID: String, label: String, kind: SpaceKind)
    /// The opening connects the spaces as proposed and the household confirmed it.
    case confirmPortal(portalID: String, operable: Bool, stepFree: Bool?, clearWidthMeters: Double?)
    /// The opening leads outside at ground level (replaces an unknown side).
    case markPortalExterior(portalID: String, operable: Bool, stepFree: Bool?)
    /// Not a usable connection (blocked, locked, or not really an opening).
    case rejectPortal(portalID: String)
    /// Leave as unknown; it stays out of every route.
    case skip(elementID: String)
    case confirmConnector(connectorID: String, usable: Bool)
    case meetingPoint(label: String)
    case shelterSpot(spaceID: String, interiorNoWindows: Bool)
    case needsMeasurement(spaceID: String)
}

public enum HomeConfirmation {
    /// Ordered steps for everything not yet confirmed. Deterministic order: rooms, openings, stairs, meeting point, shelter.
    public static func steps(for home: HomeModel) -> [ConfirmationStep] {
        var out: [ConfirmationStep] = []
        for s in home.spaces.sorted(by: { $0.id < $1.id }) where !s.labelConfirmed {
            out.append(ConfirmationStep(kind: .labelSpace, elementID: s.id, prompt: "What is this room called?"))
        }
        for p in home.portals.sorted(by: { $0.id < $1.id }) where p.verification == .proposed || p.verification == .unknown {
            let prompt: String
            if p.kind == .window {
                prompt = "Is this window an opening someone in the household could really use? Windows are never counted as walking exits automatically."
            } else if p.sideA == .unknown || p.sideB == .unknown {
                prompt = "Where does this opening lead? Confirm it goes outside, or mark it as not usable."
            } else {
                prompt = "Does this door connect these rooms, and can everyone open it without a key or tool?"
            }
            out.append(ConfirmationStep(kind: .confirmPortal, elementID: p.id, prompt: prompt))
        }
        for c in home.connectors.sorted(by: { $0.id < $1.id }) where c.verification != .verified && c.verification != .rejected {
            out.append(ConfirmationStep(kind: .confirmConnector, elementID: c.id, prompt: "Do these stairs connect these floors, and are they usable?"))
        }
        if home.meetingPoint?.verification != .verified {
            out.append(ConfirmationStep(kind: .meetingPoint, elementID: "meeting",
                                        prompt: "Choose one outside meeting point everyone can reach, away from the home."))
        }
        if !home.annotations.contains(where: { $0.kind == .tornadoShelterCandidate && $0.verification == .verified }) {
            out.append(ConfirmationStep(kind: .shelterSpot, elementID: "shelter",
                                        prompt: "Which room on the lowest floor is interior and away from windows? This is a shelter spot, not a safe room."))
        }
        return out
    }

    /// Applies one explicit answer and bumps the revision so dependent routes/results/plans are invalidated.
    public static func apply(_ answer: ConfirmationAnswer, to home: HomeModel, at date: Date = Date()) -> HomeModel {
        var h = home
        func portalIndex(_ id: String) -> Int? { h.portals.firstIndex { $0.id == id } }
        switch answer {
        case .labelSpace(let id, let label, let kind):
            guard let i = h.spaces.firstIndex(where: { $0.id == id }) else { return home }
            h.spaces[i].label = label
            h.spaces[i].kind = kind
            h.spaces[i].labelConfirmed = true
        case .confirmPortal(let id, let operable, let stepFree, let width):
            guard let i = portalIndex(id), h.portals[i].sideA != .unknown, h.portals[i].sideB != .unknown else { return home }
            h.portals[i].verification = .verified
            h.portals[i].operable = .confirmed(operable, verifiedAt: date)
            if let stepFree { h.portals[i].stepFree = .confirmed(stepFree, verifiedAt: date) }
            if let width { h.portals[i].clearWidthMeters = .confirmed(width, unit: "m", verifiedAt: date) }
        case .markPortalExterior(let id, let operable, let stepFree):
            guard let i = portalIndex(id) else { return home }
            let floorLevel = h.floors.first { $0.id == h.portals[i].floorID }?.level ?? 0
            let lowest = h.floors.map(\.level).min() ?? 0
            // Upper-floor openings are never walking exits.
            guard floorLevel == lowest else { return home }
            if h.portals[i].sideA == .unknown { h.portals[i].sideA = .exterior }
            else if h.portals[i].sideB == .unknown { h.portals[i].sideB = .exterior }
            guard h.portals[i].leadsToExterior else { return home }
            h.portals[i].verification = .verified
            h.portals[i].operable = .confirmed(operable, verifiedAt: date)
            if let stepFree { h.portals[i].stepFree = .confirmed(stepFree, verifiedAt: date) }
        case .rejectPortal(let id):
            guard let i = portalIndex(id) else { return home }
            h.portals[i].verification = .rejected
        case .skip:
            return home
        case .confirmConnector(let id, let usable):
            guard let i = h.connectors.firstIndex(where: { $0.id == id }) else { return home }
            h.connectors[i].verification = usable ? .verified : .rejected
        case .meetingPoint(let label):
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return home }
            h.annotations.removeAll { $0.kind == .outsideMeetingPoint }
            h.annotations.append(Annotation(id: "an-meeting", kind: .outsideMeetingPoint, label: trimmed, verification: .verified))
        case .shelterSpot(let spaceID, let interior):
            guard let i = h.spaces.firstIndex(where: { $0.id == spaceID }) else { return home }
            h.spaces[i].interiorNoWindowsConfirmed = .confirmed(interior, verifiedAt: date)
            h.annotations.removeAll { $0.kind == .tornadoShelterCandidate }
            if interior {
                h.annotations.append(Annotation(id: "an-shelter", kind: .tornadoShelterCandidate, floorID: h.spaces[i].floorID,
                                                spaceID: spaceID, label: h.spaces[i].label, verification: .verified,
                                                note: "Household-chosen shelter spot; not an engineered safe room."))
            }
        case .needsMeasurement(let spaceID):
            guard let i = h.spaces.firstIndex(where: { $0.id == spaceID }) else { return home }
            h.spaces[i].needsMeasurement = true
        }
        if h != home { h.bumpRevision() }
        return h
    }
}
