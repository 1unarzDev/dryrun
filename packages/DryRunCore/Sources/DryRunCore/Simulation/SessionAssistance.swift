import Foundation

public enum AssistanceReachStatus:String,Codable,Sendable {case reachable,unreachable,unknown,missingHelper}
public struct ExerciseAssistance:Codable,Sendable,Equatable {
    public var personID:String
    public var helperID:String?
    public var reachStatus:AssistanceReachStatus
    public var route:RouteResult?
    public var sharedWithPersonIDs:[String]
    /// Sharing is a dependency to investigate, not proof of an inability to help sequentially.
    public var simultaneousCapacity:String
}

extension RunState {
    /// Recompute from the *committed exercise* positions and assignments. Never declare successful
    /// assistance merely because a helper ID was assigned, or invent a clinical carrying limit.
    mutating func sessionAssistance()->[ExerciseAssistance] {
        let groups=Dictionary(grouping:household.people.filter{$0.helperPersonID != nil},by:{$0.helperPersonID!})
        return household.people.sorted(by:{$0.id<$1.id}).filter {person in
            person.helperPersonID != nil || person.needs.contains(.needsHelperToEvacuate) || person.needs.contains(.usesWheelchair)
                || person.needs.contains(.cannotUseStairs) || person.needs.contains(.deafOrHardOfHearing)
                || person.ageBand == .infant || person.ageBand == .child
        }.map {person in
            let helper=household.people.first{$0.id==person.helperPersonID}
            var route:RouteResult?
            let status:AssistanceReachStatus
            if helper==nil {status = .missingHelper}
            else if let home,let helper {
                route=planner.plan(RouteRequest(personID:helper.id,startSpaceID:startSpace(for:helper),mobility:mobility(for:helper),
                    exclusions:ScenarioExclusions(blockedSpaceIDs:spatialState?.affectedSpaceIDs ?? [],blockedPortalIDs:spatialState?.affectedPortalIDs ?? []),
                    purpose:.helperReach,destinationSpaceID:startSpace(for:person)),in:home)
                if route?.primary != nil {status = .reachable}
                else if route?.noRouteReason == .blockedByScenario || route?.noRouteReason == .incompatibleMobility {status = .unreachable}
                else {status = .unknown}
            }else {status = .unknown}
            let shared=(groups[person.helperPersonID ?? ""] ?? []).map(\.id).filter{$0 != person.id}.sorted()
            // Old authored failures stay in event history; current requirements must respond to an
            // actual reassignment/move. Geometry unknown never becomes confirmed success.
            resolveSticky("req.assistance.reach.\(person.id)")
            if status == .unreachable {requireSticky("req.assistance.reach.\(person.id)",cause:events.last?.id)}
            if helper != nil {resolveSticky("req.assistance.\(person.id)")}
            return ExerciseAssistance(personID:person.id,helperID:helper?.id,reachStatus:status,route:route,
                sharedWithPersonIDs:shared,simultaneousCapacity:shared.isEmpty ? "notAssessed" : "unknown")
        }
    }
}
