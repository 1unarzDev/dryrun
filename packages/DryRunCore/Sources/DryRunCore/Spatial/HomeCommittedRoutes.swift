import Foundation

/// The way out from each resident's recorded starting room on the SAVED home, for the Home tab overlay.
/// Read-only: it never commits state, awards evidence or changes a score. It uses the same planner and mobility
/// rule as rehearsal and assessment (step-free need → wheelchair profile) with no scenario exclusions, so it shows
/// what the committed graph supports today, and recomputes whenever the saved home changes.
public enum HomeCommittedRoutes {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var personID: String
        /// nil when the person has no recorded starting room, or the room is not in this home.
        public var startSpaceID: String?
        public var result: RouteResult?
        public var id: String { personID }
        public var path: RoutePath? { result?.primary }
        /// Why no path is shown; nil when there is one.
        public var noRouteReason: NoRouteReason? {
            guard path == nil else { return nil }
            return result?.noRouteReason ?? .unknownStartSpace
        }
    }

    public static func outdoorEgress(people: [Person], home: HomeModel, planner: EgressPlanning = EgressPlanner()) -> [Entry] {
        people.map { person in
            guard let start = person.sleepingSpaceID, home.space(start) != nil else {
                return Entry(personID: person.id, startSpaceID: nil, result: nil)
            }
            let request = RouteRequest(personID: person.id, startSpaceID: start,
                                       mobility: person.requiresStepFreeRoute ? .wheelchair : .walking)
            return Entry(personID: person.id, startSpaceID: start, result: planner.plan(request, in: home))
        }
    }

    /// Distinct paths for drawing; two people starting in the same room with the same profile share one line.
    public static func paths(_ entries: [Entry]) -> [RoutePath] {
        var seen = Set<RoutePath>()
        return entries.compactMap(\.path).filter { seen.insert($0).inserted }
    }
}
