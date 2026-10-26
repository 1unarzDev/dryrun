import Foundation

/// Clearly fictional, hand-authored homes. They did NOT come from RoomPlan (`source: .sample`).
/// Space IDs are shared across homes (`sp-living`, `sp-bed1`, …) so any sample household can be paired with any sample home.
public enum SampleHomes {
    static func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] {
        [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)]
    }

    static func door(_ id: String, _ floor: String, _ kind: PortalKind = .door, _ a: Vec2, _ b: Vec2,
                     _ sideA: PortalDestination, _ sideB: PortalDestination, width: EvidenceValue<Double>,
                     operable: EvidenceValue<Bool> = .confirmed(true), stepFree: EvidenceValue<Bool> = .confirmed(true),
                     verification: VerificationState = .verified, note: String? = nil) -> Portal {
        Portal(id: id, floorID: floor, kind: kind, a: a, b: b, sideA: sideA, sideB: sideB, clearWidthMeters: width,
               operable: operable, stepFree: stepFree, verification: verification, note: note)
    }

    static func m(_ v: Double) -> EvidenceValue<Double> { .confirmed(v, unit: "m") }

    /// Single-floor ranch (12 m × 10 m) with two verified exterior doors.
    ///
    ///   y=10 +---------+------+---------+
    ///        | sp-bed1 | bath | sp-bed2 |
    ///        |         +------+         |
    ///        |         |closet|         |
    ///   y=6.2+---------+------+---------+
    ///        |           sp-hall        |
    ///   y=5  +--------------+-----------+
    ///        |  sp-living   | sp-kitchen| pt-back (east)
    ///   y=0  +---pt-front---+-----------+
    ///        x=0           x=7         x=12
    public static var ranch: HomeModel {
        let f = "fl-ground"
        let sp = PortalDestination.space
        return HomeModel(
            id: "home-sample-ranch",
            label: "Sample ranch home (fictional)",
            source: .sample,
            frame: CoordinateFrame(note: "Hand-authored fictional layout; x east, y north, metres."),
            floors: [Floor(id: f, level: 0, label: "Ground floor")],
            spaces: [
                Space(id: "sp-living", floorID: f, label: "Living room", kind: .livingRoom, polygon: rect(0, 0, 7, 5)),
                Space(id: "sp-kitchen", floorID: f, label: "Kitchen", kind: .kitchen, polygon: rect(7, 0, 12, 5)),
                Space(id: "sp-hall", floorID: f, label: "Hallway", kind: .hallway, polygon: rect(0, 5, 12, 6.2)),
                Space(id: "sp-bed1", floorID: f, label: "Main bedroom", kind: .bedroom, polygon: rect(0, 6.2, 4.5, 10)),
                Space(id: "sp-closet", floorID: f, label: "Hall closet", kind: .closet, polygon: rect(4.5, 6.2, 7, 7.4),
                      interiorNoWindowsConfirmed: .confirmed(true)),
                Space(id: "sp-bath", floorID: f, label: "Bathroom", kind: .bathroom, polygon: rect(4.5, 7.4, 7, 10)),
                Space(id: "sp-bed2", floorID: f, label: "Kid's bedroom", kind: .bedroom, polygon: rect(7, 6.2, 12, 10)),
            ],
            walls: [
                WallSegment(id: "w-ext-s", floorID: f, a: Vec2(0, 0), b: Vec2(12, 0), thicknessMeters: 0.2),
                WallSegment(id: "w-ext-e", floorID: f, a: Vec2(12, 0), b: Vec2(12, 10), thicknessMeters: 0.2),
                WallSegment(id: "w-ext-n", floorID: f, a: Vec2(12, 10), b: Vec2(0, 10), thicknessMeters: 0.2),
                WallSegment(id: "w-ext-w", floorID: f, a: Vec2(0, 10), b: Vec2(0, 0), thicknessMeters: 0.2),
                WallSegment(id: "w-living-kitchen", floorID: f, a: Vec2(7, 0), b: Vec2(7, 5)),
                WallSegment(id: "w-south-hall", floorID: f, a: Vec2(0, 5), b: Vec2(12, 5)),
                WallSegment(id: "w-hall-north", floorID: f, a: Vec2(0, 6.2), b: Vec2(12, 6.2)),
                WallSegment(id: "w-bed1-east", floorID: f, a: Vec2(4.5, 6.2), b: Vec2(4.5, 10)),
                WallSegment(id: "w-closet-bath", floorID: f, a: Vec2(4.5, 7.4), b: Vec2(7, 7.4)),
                WallSegment(id: "w-bed2-west", floorID: f, a: Vec2(7, 6.2), b: Vec2(7, 10)),
            ],
            portals: [
                door("pt-front", f, .door, Vec2(3.0, 0), Vec2(3.9, 0), sp("sp-living"), .exterior, width: m(0.9),
                     note: "Front door"),
                door("pt-back", f, .door, Vec2(12, 2.0), Vec2(12, 2.9), sp("sp-kitchen"), .exterior, width: m(0.86),
                     stepFree: .confirmed(false), note: "Back door, one step down"),
                door("pt-living-kitchen", f, .opening, Vec2(7, 1.0), Vec2(7, 2.2), sp("sp-living"), sp("sp-kitchen"), width: m(1.2)),
                door("pt-living-hall", f, .door, Vec2(5.0, 5), Vec2(5.9, 5), sp("sp-living"), sp("sp-hall"), width: m(0.9)),
                door("pt-kitchen-hall", f, .door, Vec2(8.0, 5), Vec2(8.86, 5), sp("sp-kitchen"), sp("sp-hall"), width: m(0.86)),
                door("pt-bed1-hall", f, .door, Vec2(3.0, 6.2), Vec2(3.85, 6.2), sp("sp-bed1"), sp("sp-hall"), width: .unknown,
                     note: "Clear width not yet measured"),
                door("pt-bed2-hall", f, .door, Vec2(9.0, 6.2), Vec2(9.86, 6.2), sp("sp-bed2"), sp("sp-hall"), width: m(0.86)),
                door("pt-closet-hall", f, .door, Vec2(5.2, 6.2), Vec2(5.9, 6.2), sp("sp-closet"), sp("sp-hall"), width: m(0.7)),
                door("pt-bed1-bath", f, .door, Vec2(4.5, 8.0), Vec2(4.5, 8.75), sp("sp-bed1"), sp("sp-bath"), width: m(0.75)),
                door("pt-win-bed1", f, .window, Vec2(1.5, 10), Vec2(2.5, 10), sp("sp-bed1"), .exterior, width: .unknown,
                     operable: .unknown, stepFree: .confirmed(false), verification: .proposed,
                     note: "Window — not an exit unless the household confirms it opens fully and can be used"),
                door("pt-win-bed2", f, .window, Vec2(9.5, 10), Vec2(10.5, 10), sp("sp-bed2"), .exterior, width: .unknown,
                     operable: .unknown, stepFree: .confirmed(false), verification: .proposed),
                door("pt-win-living", f, .window, Vec2(0.8, 0), Vec2(2.0, 0), sp("sp-living"), .exterior, width: .unknown,
                     operable: .unknown, stepFree: .confirmed(false), verification: .proposed),
            ],
            obstacles: [
                Obstacle(id: "ob-sofa", floorID: f, label: "Sofa", polygon: rect(1.0, 3.4, 4.0, 4.3)),
                Obstacle(id: "ob-island", floorID: f, label: "Kitchen island", polygon: rect(8.8, 2.0, 10.4, 3.0)),
            ],
            annotations: [
                Annotation(id: "an-smoke-hall", kind: .smokeAlarm, floorID: f, spaceID: "sp-hall", position: Vec2(6, 5.6),
                           label: "Smoke alarm", verification: .verified),
                Annotation(id: "an-smoke-bed1", kind: .smokeAlarm, floorID: f, spaceID: "sp-bed1", position: Vec2(2.2, 8.1),
                           label: "Smoke alarm", verification: .verified),
                Annotation(id: "an-smoke-bed2", kind: .smokeAlarm, floorID: f, spaceID: "sp-bed2", position: Vec2(9.5, 8.1),
                           label: "Smoke alarm", verification: .proposed, note: "Battery test not recorded"),
                Annotation(id: "an-co-hall", kind: .coAlarm, floorID: f, spaceID: "sp-hall", position: Vec2(3, 5.6),
                           label: "CO alarm", verification: .verified),
                Annotation(id: "an-extinguisher", kind: .fireExtinguisher, floorID: f, spaceID: "sp-kitchen", position: Vec2(7.4, 4.5),
                           label: "Fire extinguisher", verification: .verified),
                Annotation(id: "an-shutoff-water", kind: .utilityShutoffWater, floorID: f, spaceID: "sp-kitchen", position: Vec2(11.6, 4.6),
                           label: "Water shutoff", verification: .verified),
                Annotation(id: "an-shutoff-elec", kind: .utilityShutoffElectric, floorID: f, spaceID: "sp-hall", position: Vec2(11.6, 5.6),
                           label: "Breaker panel", verification: .verified),
                Annotation(id: "an-supplies", kind: .supplies, floorID: f, spaceID: "sp-closet", position: Vec2(5.75, 6.8),
                           label: "Emergency supplies", verification: .verified),
                Annotation(id: "an-medical", kind: .medicalEquipment, floorID: f, spaceID: "sp-living", position: Vec2(6.4, 0.6),
                           label: "Oxygen concentrator", verification: .verified),
                Annotation(id: "an-tornado", kind: .tornadoShelterCandidate, floorID: f, spaceID: "sp-closet", position: Vec2(5.75, 6.8),
                           label: "Interior closet (shelter candidate)", verification: .verified,
                           note: "Interior room with no windows on the lowest floor. Not an engineered safe room."),
                Annotation(id: "an-hydrant", kind: .exteriorHydrant, floorID: f, spaceID: nil, position: Vec2(14.5, -4.0),
                           label: "Street hydrant", verification: .verified, note: "Landmark only; not an evacuation objective."),
                Annotation(id: "an-meeting", kind: .outsideMeetingPoint, floorID: f, spaceID: nil, position: Vec2(3.45, -8.0),
                           label: "Mailbox at the end of the driveway (fictional)", verification: .verified),
            ],
            completeness: .complete,
            isFictional: true
        )
    }

    /// Two-storey home: bedrooms upstairs, verified stairs, upstairs windows that are verified/operable but still not exits.
    public static var twoStory: HomeModel {
        let g = "fl-ground", u = "fl-upper"
        let sp = PortalDestination.space
        func box(_ fl: String, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ p: String) -> [WallSegment] {
            [WallSegment(id: "w-\(p)-s", floorID: fl, a: Vec2(x0, y0), b: Vec2(x1, y0), thicknessMeters: 0.2),
             WallSegment(id: "w-\(p)-e", floorID: fl, a: Vec2(x1, y0), b: Vec2(x1, y1), thicknessMeters: 0.2),
             WallSegment(id: "w-\(p)-n", floorID: fl, a: Vec2(x1, y1), b: Vec2(x0, y1), thicknessMeters: 0.2),
             WallSegment(id: "w-\(p)-w", floorID: fl, a: Vec2(x0, y1), b: Vec2(x0, y0), thicknessMeters: 0.2)]
        }
        return HomeModel(
            id: "home-sample-twostory",
            label: "Sample two-storey home (fictional)",
            source: .sample,
            floors: [
                Floor(id: g, level: 0, label: "Ground floor", elevationMeters: 0),
                Floor(id: u, level: 1, label: "Upstairs", elevationMeters: 2.8),
            ],
            spaces: [
                Space(id: "sp-living", floorID: g, label: "Living room", kind: .livingRoom, polygon: rect(0, 0, 6, 5.5)),
                Space(id: "sp-kitchen", floorID: g, label: "Kitchen", kind: .kitchen, polygon: rect(6, 0, 10, 5.5)),
                Space(id: "sp-hall", floorID: g, label: "Front hall and stairs", kind: .hallway, polygon: rect(0, 5.5, 10, 8)),
                Space(id: "sp-bed1", floorID: u, label: "Main bedroom", kind: .bedroom, polygon: rect(0, 0, 5, 5.5)),
                Space(id: "sp-bed2", floorID: u, label: "Second bedroom", kind: .bedroom, polygon: rect(5, 0, 10, 5.5)),
                Space(id: "sp-landing", floorID: u, label: "Upstairs landing", kind: .hallway, polygon: rect(0, 5.5, 10, 8)),
            ],
            walls: box(g, 0, 0, 10, 8, "g-ext") + box(u, 0, 0, 10, 8, "u-ext") + [
                WallSegment(id: "w-g-mid", floorID: g, a: Vec2(6, 0), b: Vec2(6, 5.5)),
                WallSegment(id: "w-g-hall", floorID: g, a: Vec2(0, 5.5), b: Vec2(10, 5.5)),
                WallSegment(id: "w-u-mid", floorID: u, a: Vec2(5, 0), b: Vec2(5, 5.5)),
                WallSegment(id: "w-u-hall", floorID: u, a: Vec2(0, 5.5), b: Vec2(10, 5.5)),
            ],
            portals: [
                door("pt-front", g, .door, Vec2(2, 0), Vec2(2.9, 0), sp("sp-living"), .exterior, width: m(0.9)),
                door("pt-back", g, .door, Vec2(10, 3), Vec2(10, 3.9), sp("sp-kitchen"), .exterior, width: m(0.86)),
                door("pt-living-kitchen", g, .opening, Vec2(6, 1), Vec2(6, 2.2), sp("sp-living"), sp("sp-kitchen"), width: m(1.2)),
                door("pt-living-hall", g, .opening, Vec2(1.5, 5.5), Vec2(2.4, 5.5), sp("sp-living"), sp("sp-hall"), width: m(0.9)),
                door("pt-kitchen-hall", g, .door, Vec2(7, 5.5), Vec2(7.9, 5.5), sp("sp-kitchen"), sp("sp-hall"), width: m(0.86)),
                door("pt-bed1-landing", u, .door, Vec2(2, 5.5), Vec2(2.85, 5.5), sp("sp-bed1"), sp("sp-landing"), width: m(0.85)),
                door("pt-bed2-landing", u, .door, Vec2(7, 5.5), Vec2(7.85, 5.5), sp("sp-bed2"), sp("sp-landing"), width: m(0.85)),
                door("pt-win-up-bed1", u, .window, Vec2(2, 0), Vec2(3, 0), sp("sp-bed1"), .exterior, width: m(0.9),
                     operable: .confirmed(true), stepFree: .confirmed(false), verification: .verified,
                     note: "Upstairs window: confirmed operable, still not a walking exit"),
                door("pt-win-up-bed2", u, .window, Vec2(7, 0), Vec2(8, 0), sp("sp-bed2"), .exterior, width: m(0.9),
                     operable: .confirmed(true), stepFree: .confirmed(false), verification: .verified),
            ],
            connectors: [
                FloorConnector(id: "cn-stairs", kind: .stairs, fromSpaceID: "sp-landing", toSpaceID: "sp-hall",
                               fromPoint: Vec2(8.8, 6.8), toPoint: Vec2(8.8, 6.8), verification: .verified),
            ],
            annotations: [
                Annotation(id: "an-smoke-landing", kind: .smokeAlarm, floorID: u, spaceID: "sp-landing", position: Vec2(5, 6.7),
                           label: "Smoke alarm", verification: .verified),
                Annotation(id: "an-smoke-hall", kind: .smokeAlarm, floorID: g, spaceID: "sp-hall", position: Vec2(5, 6.7),
                           label: "Smoke alarm", verification: .verified),
                Annotation(id: "an-meeting", kind: .outsideMeetingPoint, floorID: g, position: Vec2(2.45, -7),
                           label: "Neighbor's oak tree (fictional)", verification: .verified),
            ],
            completeness: .complete,
            isFictional: true
        )
    }

    /// Third-floor apartment. The unit door opens to a building corridor that is OUTSIDE the model;
    /// the balcony door leads outside but is not a ground exit. There is deliberately no verified route.
    public static var apartment: HomeModel {
        let f = "fl-apt"
        let sp = PortalDestination.space
        return HomeModel(
            id: "home-sample-apartment",
            label: "Sample third-floor apartment (fictional)",
            source: .sample,
            floors: [Floor(id: f, level: 2, label: "Third floor (unit only)", elevationMeters: 6.0)],
            spaces: [
                Space(id: "sp-living", floorID: f, label: "Living and dining", kind: .livingRoom, polygon: rect(0, 0, 6, 5)),
                Space(id: "sp-kitchen", floorID: f, label: "Kitchen", kind: .kitchen, polygon: rect(6, 0, 9, 5)),
                Space(id: "sp-hall", floorID: f, label: "Hallway", kind: .hallway, polygon: rect(0, 5, 9, 6.2)),
                Space(id: "sp-bed1", floorID: f, label: "Bedroom 1", kind: .bedroom, polygon: rect(0, 6.2, 4, 9.5)),
                Space(id: "sp-bed2", floorID: f, label: "Bedroom 2", kind: .bedroom, polygon: rect(4, 6.2, 7, 9.5)),
                Space(id: "sp-bath", floorID: f, label: "Bathroom", kind: .bathroom, polygon: rect(7, 6.2, 9, 9.5),
                      interiorNoWindowsConfirmed: .confirmed(true)),
            ],
            walls: [
                WallSegment(id: "w-s", floorID: f, a: Vec2(0, 0), b: Vec2(9, 0), thicknessMeters: 0.2),
                WallSegment(id: "w-e", floorID: f, a: Vec2(9, 0), b: Vec2(9, 9.5), thicknessMeters: 0.2),
                WallSegment(id: "w-n", floorID: f, a: Vec2(9, 9.5), b: Vec2(0, 9.5), thicknessMeters: 0.2),
                WallSegment(id: "w-w", floorID: f, a: Vec2(0, 9.5), b: Vec2(0, 0), thicknessMeters: 0.2),
                WallSegment(id: "w-hall-s", floorID: f, a: Vec2(0, 5), b: Vec2(9, 5)),
                WallSegment(id: "w-hall-n", floorID: f, a: Vec2(0, 6.2), b: Vec2(9, 6.2)),
                WallSegment(id: "w-bed-mid", floorID: f, a: Vec2(4, 6.2), b: Vec2(4, 9.5)),
                WallSegment(id: "w-bath", floorID: f, a: Vec2(7, 6.2), b: Vec2(7, 9.5)),
            ],
            portals: [
                door("pt-entry", f, .door, Vec2(0, 1.5), Vec2(0, 2.4), sp("sp-living"), .commonArea("cm-corridor-3f"), width: m(0.9),
                     note: "Unit door to the building corridor; corridor and stairs are outside this model"),
                door("pt-balcony", f, .slidingDoor, Vec2(2, 0), Vec2(3.5, 0), sp("sp-living"), .exterior, width: m(1.4),
                     note: "Third-floor balcony: outside, not a ground exit"),
                door("pt-living-kitchen", f, .opening, Vec2(6, 0.5), Vec2(6, 4.5), sp("sp-living"), sp("sp-kitchen"), width: m(4.0)),
                door("pt-living-hall", f, .opening, Vec2(1, 5), Vec2(2, 5), sp("sp-living"), sp("sp-hall"), width: m(1.0)),
                door("pt-bed1-hall", f, .door, Vec2(2, 6.2), Vec2(2.8, 6.2), sp("sp-bed1"), sp("sp-hall"), width: m(0.8)),
                door("pt-bed2-hall", f, .door, Vec2(5, 6.2), Vec2(5.8, 6.2), sp("sp-bed2"), sp("sp-hall"), width: m(0.8)),
                door("pt-bath-hall", f, .door, Vec2(7.6, 6.2), Vec2(8.3, 6.2), sp("sp-bath"), sp("sp-hall"), width: m(0.7)),
                door("pt-win-bed1", f, .window, Vec2(1.5, 9.5), Vec2(2.5, 9.5), sp("sp-bed1"), .exterior, width: .unknown,
                     operable: .unknown, stepFree: .confirmed(false), verification: .proposed),
            ],
            annotations: [
                Annotation(id: "an-smoke-hall", kind: .smokeAlarm, floorID: f, spaceID: "sp-hall", position: Vec2(4.5, 5.6),
                           label: "Smoke alarm", verification: .verified),
                Annotation(id: "an-tornado", kind: .tornadoShelterCandidate, floorID: f, spaceID: "sp-bath", position: Vec2(8, 7.8),
                           label: "Interior bathroom (shelter candidate)", verification: .proposed,
                           note: "Upper-floor unit: ask building management about the lowest-floor shelter area."),
                Annotation(id: "an-meeting", kind: .outsideMeetingPoint, floorID: f, position: nil,
                           label: "Bus stop across the parking lot (fictional)", verification: .verified),
            ],
            completeness: .incomplete,
            completenessNote: "Building corridor and stairwells are outside this model. Use the building's posted evacuation route and confirm it with management.",
            isFictional: true
        )
    }

    public static var all: [HomeModel] { [ranch, twoStory, apartment] }
}
