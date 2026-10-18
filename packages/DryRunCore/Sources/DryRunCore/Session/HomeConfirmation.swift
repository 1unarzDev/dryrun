import Foundation

/// Guided confirmation pass after a scan (or manual edits): label rooms, confirm doors/connections, identify exterior
/// exits, inspect unknown openings, confirm stairs, choose a meeting point, and mark shelter/measurement needs.
/// Nothing becomes verified except through an explicit `ConfirmationAnswer`.
public enum ConfirmationStepKind: String, Codable, Sendable, Hashable {
    case confirmFloor, labelSpace, confirmPortal, confirmConnector, meetingPoint, shelterSpot
}

public struct ConfirmationStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(elementID)" }
    public var kind: ConfirmationStepKind
    public var elementID: String
    /// Short English prompt for the first build (moves to locale packs with the UI-chrome pass).
    public var prompt: String
}

public enum ConfirmationAnswer: Codable, Sendable, Hashable {
    case higherRefuge(spaceID: String, hasWayOutAndIsNotClosedAttic: Bool)
    case floorGrade(floorID: String, grade: ExteriorGrade)
    case labelSpace(spaceID: String, label: String, kind: SpaceKind)
    /// Assign the first unresolved side of a proposed interior opening to a selected room.
    /// This intentionally does not verify the opening or its operability; those remain separate answers.
    case assignPortalInterior(portalID: String, spaceID: String)
    /// The opening connects the spaces as proposed and the household confirmed it.
    case confirmPortal(portalID: String, operable: Bool, stepFree: Bool?, clearWidthMeters: Double?)
    /// Evidence-preserving variant for review UIs that allow operability to remain unknown.
    case confirmPortalEvidence(portalID: String, operable: Bool?, stepFree: Bool?, clearWidthMeters: Double?)
    /// The opening leads outside at ground level (replaces an unknown side).
    case markPortalExterior(portalID: String, operable: Bool, stepFree: Bool?)
    /// Measured variant used by the review UI. Kept separate so the original three-argument answer remains
    /// source-compatible for callers that did not collect a width.
    case markPortalExteriorMeasured(portalID: String, operable: Bool, stepFree: Bool?, clearWidthMeters: Double?)
    /// Evidence-preserving exterior variant for review UIs that allow unknown operability/accessibility.
    case markPortalExteriorEvidence(portalID: String, operable: Bool?, stepFree: Bool?, clearWidthMeters: Double?)
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
        for floor in home.floors.sorted(by: { $0.id < $1.id }) where floor.exteriorGrade == .unknown || (home.source == .roomPlanScan && floor.exteriorGrade == nil) {
            out.append(ConfirmationStep(kind: .confirmFloor, elementID: floor.id,
                prompt: "Where is this captured floor in relation to outside ground? Capture order does not establish ground level."))
        }
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
        case .higherRefuge(let spaceID, let suitable):
            guard let index = h.spaces.firstIndex(where: { $0.id == spaceID }) else { return home }
            h.spaces[index].higherRefugeConfirmed = .confirmed(suitable, verifiedAt: date)
        case .floorGrade(let floorID, let grade):
            guard let index = h.floors.firstIndex(where: { $0.id == floorID }) else { return home }
            h.floors[index].exteriorGrade = grade
        case .labelSpace(let id, let label, let kind):
            guard let i = h.spaces.firstIndex(where: { $0.id == id }) else { return home }
            h.spaces[i].label = label
            h.spaces[i].kind = kind
            h.spaces[i].labelConfirmed = true
        case .assignPortalInterior(let id, let spaceID):
            guard let i = portalIndex(id), let space = h.space(spaceID) else { return home }
            // Windows remain excluded from generic walking connections even when a scan puts them near a room.
            guard h.portals[i].kind != .window, h.portals[i].floorID == space.floorID else { return home }
            let destination = PortalDestination.space(spaceID)
            // Do not allow a self-loop or overwrite an already identified side.
            guard h.portals[i].sideA != destination, h.portals[i].sideB != destination else { return home }
            if h.portals[i].sideA == .unknown {
                h.portals[i].sideA = destination
            } else if h.portals[i].sideB == .unknown {
                h.portals[i].sideB = destination
            } else {
                return home
            }
        case .confirmPortal(let id, let operable, let stepFree, let width):
            let portalIndexValue = portalIndex(id)
            h = confirmPortal(portalIndex: portalIndexValue, in: h, operable: operable, stepFree: stepFree, width: width, date: date)
        case .confirmPortalEvidence(let id, let operable, let stepFree, let width):
            let evidencePortalIndex = portalIndex(id)
            h = confirmPortal(portalIndex: evidencePortalIndex, in: h, operable: operable, stepFree: stepFree, width: width, date: date)
        case .markPortalExterior(let id, let operable, let stepFree):
            guard let i = portalIndex(id) else { return home }
            h = markExterior(portalIndex: i, in: h, operable: operable, stepFree: stepFree, width: nil, date: date)
        case .markPortalExteriorMeasured(let id, let operable, let stepFree, let width):
            guard let i = portalIndex(id) else { return home }
            h = markExterior(portalIndex: i, in: h, operable: operable, stepFree: stepFree,
                             width: width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, date: date)
        case .markPortalExteriorEvidence(let id, let operable, let stepFree, let width):
            guard let i = portalIndex(id) else { return home }
            h = markExterior(portalIndex: i, in: h, operable: operable, stepFree: stepFree,
                             width: width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, date: date)
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
            // Shelter spots must be on the lowest floor.
            let lowest = h.floors.map(\.level).min()
            guard h.floors.first(where: { $0.id == h.spaces[i].floorID })?.level == lowest,
                  h.floors.first(where: { $0.id == h.spaces[i].floorID })?.exteriorGrade != .unknown else { return home }
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

    private static func confirmPortal(portalIndex: Int?, in home: HomeModel, operable: Bool?, stepFree: Bool?,
                                      width: Double?, date: Date) -> HomeModel {
        var h = home
        guard let i = portalIndex, h.portals[i].sideA != .unknown, h.portals[i].sideB != .unknown else { return home }
        h.portals[i].verification = .verified
        h.portals[i].operable = operable.map { .confirmed($0, verifiedAt: date) } ?? .unknown
        h.portals[i].stepFree = stepFree.map { .confirmed($0, verifiedAt: date) } ?? .unknown
        if let width, width.isFinite, width > 0 { h.portals[i].clearWidthMeters = .confirmed(width, unit: "m", verifiedAt: date) }
        return h
    }

    private static func markExterior(portalIndex i: Int, in home: HomeModel, operable: Bool?, stepFree: Bool?,
                                     width: Double?, date: Date) -> HomeModel {
        var h = home
        // Windows never become walking exits through the generic door answer.
        guard h.portals[i].kind != .window else { return home }
        // One shared definition of "ground" with the planner; upper floors and basements are not walking exits here.
        guard let floor = h.floors.first(where: { $0.id == h.portals[i].floorID }), Graph.isGround(floor, .standard), !(h.source == .roomPlanScan && floor.exteriorGrade == nil) else { return home }
        // An exterior answer must still identify the room the household exits from. A completely unresolved
        // opening cannot become a route merely because the user selected "outside".
        func isSpace(_ destination: PortalDestination) -> Bool {
            if case .space(_) = destination { return true }
            return false
        }
        if h.portals[i].sideA == .unknown, isSpace(h.portals[i].sideB) {
            h.portals[i].sideA = .exterior
        } else if h.portals[i].sideB == .unknown, isSpace(h.portals[i].sideA) {
            h.portals[i].sideB = .exterior
        } else {
            return home
        }
        guard h.portals[i].leadsToExterior else { return home }
        h.portals[i].verification = .verified
        h.portals[i].operable = operable.map { .confirmed($0, verifiedAt: date) } ?? .unknown
        h.portals[i].stepFree = stepFree.map { .confirmed($0, verifiedAt: date) } ?? .unknown
        if let width { h.portals[i].clearWidthMeters = .confirmed(width, unit: "m", verifiedAt: date) }
        return h
    }
}
