import Foundation

public enum SessionToolKind:String,Codable,Sendable {case inspectScene,queryRoutes,evaluateResources,inspectDependencies,evaluateCandidateAction,runCounterfactual}
public struct SessionToolRequest:Codable,Sendable {
    public var kind:SessionToolKind
    public var baseRevision:Int
    public var command:SessionCommand?
    public var profileIDs:[String]?
    public var intervention:Intervention?
    public var routeRequest:RouteRequest?
    public init(kind:SessionToolKind,baseRevision:Int,command:SessionCommand?=nil,profileIDs:[String]?=nil,intervention:Intervention?=nil,routeRequest:RouteRequest?=nil){self.kind=kind;self.baseRevision=baseRevision;self.command=command;self.profileIDs=profileIDs;self.intervention=intervention;self.routeRequest=routeRequest}
}
public struct SessionToolResponse:Codable,Sendable {
    public var receipt:SessionReceipt
    public var scene:HomeSceneContext?
    public var dependencies:[DependencyInspection]?
    public var counterfactual:StressTestFinding?
    public var route:RouteResult?
}
public struct DependencyInspection:Codable,Sendable {
    public var id:String; public var kind:String;public var subjectIDs:[String];public var evidenceIDs:[String];public var status:String
}
public extension SimulationSession {
    /// All operations are read-only. Native controls choose what minimized fields can leave the device.
    func executeTool(_ request:SessionToolRequest,library:ScenarioLibrary)throws->SessionToolResponse {
        guard request.baseRevision==revision else {throw SessionError.stale}
        let receipt:SessionReceipt
        if request.kind == .evaluateCandidateAction {
            guard let command=request.command else {throw SessionError.invalidCommand}
            receipt=try preview(.init(id:"tool-preview-\(revision)",actor:"director",baseRevision:revision,commands:[command]),library:library)
        } else {receipt=try query(library:library)}
        var result=SessionToolResponse(receipt:receipt)
        switch request.kind {
        case .inspectScene:result.scene=initial.home.map(HomeSceneContext.init)
        case .queryRoutes:
            if var routeRequest=request.routeRequest {
                guard let home=initial.home else {throw SessionError.invalidCommand}
                routeRequest.exclusions.blockedSpaceIDs=Array(Set(routeRequest.exclusions.blockedSpaceIDs+(receipt.snapshot.spatialState?.affectedSpaceIDs ?? []))).sorted()
                routeRequest.exclusions.blockedPortalIDs=Array(Set(routeRequest.exclusions.blockedPortalIDs+(receipt.snapshot.spatialState?.affectedPortalIDs ?? []))).sorted()
                result.route=EgressPlanner().plan(routeRequest,in:home)
            }
        case .inspectDependencies:result.dependencies=dependencyInspection(receipt:receipt)
        case .runCounterfactual:result.counterfactual=try PlanStressTester.execute(initial:initial,profileIDs:request.profileIDs ?? [],library:library,intervention:request.intervention)
        default:break
        }
        return result
    }
    func dependencyInspection(receipt:SessionReceipt)->[DependencyInspection] {
        let h=initial.household
        var result:[DependencyInspection]=[]
        for source in h.backupPower {
            let subjects=h.equipment.filter{$0.compatibleBackupIDs.contains(source.id)}.map(\.id)
            if subjects.count>1 {result.append(.init(id:"backup|\(source.id)",kind:"sharedPower",subjectIDs:subjects,evidenceIDs:["backupPower.\(source.id)",receipt.contextDigest],status:"shared; capacity must be computed by allocator"))}
        }
        let assignments=Dictionary(grouping:h.people.filter{$0.helperPersonID != nil},by:{$0.helperPersonID!})
        for (helper,people) in assignments where people.count>1 {
            result.append(.init(id:"helper|\(helper)",kind:"sharedHelper",subjectIDs:people.map(\.id),evidenceIDs:["people.helperPersonID"],status:"possible simultaneous conflict; not a confirmed inability"))
        }
        if !h.contacts.isEmpty {result.append(.init(id:"contact|channel",kind:"contactChannel",subjectIDs:h.contacts.map(\.id),evidenceIDs:[receipt.contextDigest],status:receipt.snapshot.services[Svc.handset] == .operational && receipt.snapshot.services[Svc.cellular] == .operational ? "recorded handset and cellular operational in exercise" : "channel unavailable or unknown in exercise"))}
        for route in receipt.routes where !route.sharedChokepoints.isEmpty {
            guard let personID=route.request.personID else {continue}
            result.append(.init(id:"route|\(personID)",kind:"sharedRoute",subjectIDs:[personID],evidenceIDs:route.sharedChokepoints,status:"routes share geometry; alternative is not independent"))
        }
        if h.transport.destinations.count>1 {result.append(.init(id:"meetup|transport",kind:"commonTransport",subjectIDs:h.transport.destinations.map(\.id),evidenceIDs:["transport",receipt.contextDigest],status:"destinations depend on recorded transport; inspect exercise availability"))}
        return result.sorted{$0.id<$1.id}
    }
}
