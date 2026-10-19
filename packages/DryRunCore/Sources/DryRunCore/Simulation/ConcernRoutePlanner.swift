import Foundation
/// Decorates the canonical planner with user-selected hypothetical opening exclusions.
/// Does not manufacture geometry or change the source HomeModel.
struct ConcernRoutePlanner:EgressPlanning {
    var portalIDs:[String]
    func plan(_ request:RouteRequest,in home:HomeModel)->RouteResult {
        guard !portalIDs.isEmpty else {return EgressPlanner().plan(request,in:home)}
        var scoped=request
        scoped.exclusions.blockedPortalIDs=Array(Set(request.exclusions.blockedPortalIDs+portalIDs)).sorted()
        return EgressPlanner().plan(scoped,in:home)
    }
}
