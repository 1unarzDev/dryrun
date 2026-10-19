import Foundation

public struct HomePlanningRoute: Codable, Sendable {
    public var personID: String
    public var startRoomID: String?
    public var stepFreeRequired: Bool
    public var primaryPortalIDs: [String]
    public var connectorIDs: [String]
    public var alternativePortalIDs: [String]
    public var noRouteReason: String?
    public var exclusions: [RouteExclusion]
    public var scope = "Recorded baseline geometry only; current incidents, occupants and assistance require host tools. A practice route is not real-time safety clearance."
}
public struct HousingPlanningNeed: Codable, Sendable, Identifiable {
    public var id: String
    public var relatedIDs: [String]
    public var suggestedActionID: String
    public var editor: String
    public var scoreEffect = "none; use existing rubric predicates only"
}
/// One shared assessment for Home/Plan/Prepare adapters. No model patch, new completion toggle,
/// geographic inference, numerical score or incident state is created by a planning note.
public enum HousingPlanning {
    public static func routes(household:HouseholdProfile,home:HomeModel)->[HomePlanningRoute] {
        household.people.map { person in
            let route=EgressPlanner().plan(RouteRequest(personID:person.id,startSpaceID:person.sleepingSpaceID ?? "unknown",mobility:person.requiresStepFreeRoute ? .wheelchair:.walking),in:home)
            return HomePlanningRoute(personID:person.id,startRoomID:person.sleepingSpaceID,stepFreeRequired:person.requiresStepFreeRoute,
                primaryPortalIDs:route.primary?.portalSequence ?? [],connectorIDs:route.primary?.connectorSequence ?? [],
                alternativePortalIDs:route.alternative?.portalSequence ?? [],noRouteReason:route.noRouteReason?.rawValue,exclusions:route.exclusions)
        }
    }
    public static func needs(household:HouseholdProfile,home:HomeModel?)->[HousingPlanningNeed] {
        var result:[HousingPlanningNeed]=[]
        func add(_ id:String,_ ids:[String],_ action:String,_ editor:String) {
            result.append(HousingPlanningNeed(id:id,relatedIDs:ids,suggestedActionID:action,editor:editor))
        }
        if household.housing.homeType == .manufacturedHome || home?.dwellingType == .manufacturedHome {
            add("manufacturedTornadoAdvancePlan",[],"prep.shelterPlan","meetingPlace")
        }
        guard let home else {add("layoutNotRecorded",[],"prep.layout","home");return result}
        let routes=routes(household:household,home:home)
        for r in routes {
            if r.primaryPortalIDs.isEmpty {add("egressNotEstablished|"+r.personID,[r.personID],"prep.clearExits","home")}
            else if !r.connectorIDs.isEmpty && r.alternativePortalIDs.isEmpty {add("stairsSingleDependency|"+r.personID,r.connectorIDs,"prep.fireDrill","home")}
        }
        for kind in [AnnotationKind.utilityShutoffElectric,.fireExtinguisher,.supplies] {
            if !home.annotations.contains(where:{$0.kind==kind && $0.verification == .verified && HomeSafetyMarkers.hasValidPlacement($0,in:home)}) {
                add("locationNotRecorded|"+kind.rawValue,[],kind == .fireExtinguisher ? "prep.extinguisher":"prep.layout","home")
            }
        }
        if household.housing.homeType != .manufacturedHome && ShelterSuitability.confirmedRoom(in:home)==nil {
            add("tornadoShelterNotEstablished",[],"prep.layout","home")
        }
        return result
    }
    /// Explicit resource dependencies: unrelated photos/notes cannot refresh a strategy.
    public static func strategyDependencies(household:HouseholdProfile,home:HomeModel?,at date:Date)->[ResourceStrategyDependency] {
        let site=SiteHazardContext(household.siteHazards,jurisdictionID:household.regionID,at:date,locationBinding:SiteHazardBinding.of(household))
        return [ResourceStrategyDependency(id:"housing.homeType",state:household.housing.homeType.rawValue),
                ResourceStrategyDependency(id:"housing.egress",state:home.map{routes(household:household,home:$0).contains{$0.primaryPortalIDs.isEmpty} ? "notEstablished":"recordedBaseline"} ?? "unknown"),
                ResourceStrategyDependency(id:"site.flood",state:site.floodComparison),
                ResourceStrategyDependency(id:"site.wildfire",state:(site.wildfireScale ?? "unknown")+":"+(site.wildfireRating ?? "unknown")),
                ResourceStrategyDependency(id:"site.hurricane",state:site.hurricanePlan)]
    }
}
