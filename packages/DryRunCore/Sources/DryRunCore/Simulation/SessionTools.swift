import Foundation

public enum SessionToolKind:String,Codable,Sendable {case inspectScene,queryRoutes,evaluateResources,inspectDependencies,evaluateCandidateAction,runCounterfactual}
public struct SessionToolRequest:Codable,Sendable {
    public var kind:SessionToolKind
    public var baseRevision:Int
    public var command:SessionCommand?
    public var commands:[SessionCommand]?
    public var profileIDs:[String]?
    public var intervention:Intervention?
    public var routeRequest:RouteRequest?
    public var retestPlan:StressRetestPlan?
    public init(kind:SessionToolKind,baseRevision:Int,command:SessionCommand?=nil,commands:[SessionCommand]?=nil,profileIDs:[String]?=nil,intervention:Intervention?=nil,routeRequest:RouteRequest?=nil,retestPlan:StressRetestPlan?=nil){self.kind=kind;self.baseRevision=baseRevision;self.command=command;self.commands=commands;self.profileIDs=profileIDs;self.intervention=intervention;self.routeRequest=routeRequest;self.retestPlan=retestPlan}
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
            guard (request.command != nil) != (request.commands != nil) else {throw SessionError.invalidCommand}
            let commands=request.commands ?? [request.command!]
            receipt=try preview(.init(id:"tool-preview-\(revision)",actor:"director",baseRevision:revision,commands:commands),library:library)
        } else {receipt=try query(library:library)}
        var result=SessionToolResponse(receipt:receipt)
        switch request.kind {
        case .inspectScene:result.scene=initial.home.map(HomeSceneContext.init)
        case .queryRoutes:
            if var routeRequest=request.routeRequest {
                guard let home=initial.home else {throw SessionError.invalidCommand}
                routeRequest.exclusions.blockedSpaceIDs=Array(Set(routeRequest.exclusions.blockedSpaceIDs+(receipt.snapshot.spatialState?.affectedSpaceIDs ?? []))).sorted()
                routeRequest.exclusions.blockedPortalIDs=Array(Set(routeRequest.exclusions.blockedPortalIDs+(receipt.snapshot.spatialState?.affectedPortalIDs ?? []))).sorted()
                result.route=ConcernRoutePlanner(portalIDs:concernSeed?.selectedPortalIDs ?? []).plan(routeRequest,in:home)
            }
        case .inspectDependencies:result.dependencies=try dependencyInspection(receipt:receipt,library:library)
        case .runCounterfactual:result.counterfactual=try PlanStressTester.execute(initial:initial,profileIDs:request.profileIDs ?? [],library:library,intervention:request.intervention,inventory:inventory,concernSeed:concernSeed,dependencyPolicy:dependencyPolicy,retestPlan:request.retestPlan)
        default:break
        }
        return result
    }
    func dependencyInspection(receipt:SessionReceipt,library:ScenarioLibrary)throws->[DependencyInspection] {
        // Bind observations to this exact committed host state, never a model-supplied receipt.
        guard receipt == (try query(library:library)) else {throw SessionError.stale}
        let h=initial.household
        var result:[DependencyInspection]=[]
        for source in h.backupPower {
            let subjects=h.equipment.filter{$0.compatibleBackupIDs.contains(source.id)}.map(\.id)
            if subjects.count>1 {result.append(.init(id:"backup|\(source.id)",kind:"sharedPower",subjectIDs:subjects,evidenceIDs:["backupPower.\(source.id)",receipt.contextDigest],status:"shared; capacity must be computed by allocator"))}
        }
        let assignedPeople=receipt.assistance==nil ? h.people.filter{$0.helperPersonID != nil}.map{($0.id,$0.helperPersonID!)} : (receipt.assistance ?? []).compactMap{state in state.helperID.map{(state.personID,$0)}}
        let assignments=Dictionary(grouping:assignedPeople,by:{$0.1})
        for (helper,people) in assignments where people.count>1 {
            result.append(.init(id:"helper|\(helper)",kind:"sharedHelper",subjectIDs:people.map{$0.0}.sorted(),evidenceIDs:["people.helperPersonID"],status:"possible simultaneous conflict; not a confirmed inability"))
        }
        for state in receipt.assistance ?? [] {
            result.append(.init(id:"helperReach|\(state.personID)",kind:"helperReach",subjectIDs:[state.personID]+(state.helperID.map{[$0]} ?? []),
                evidenceIDs:[receipt.contextDigest],status:"committed exercise reach: \(state.reachStatus.rawValue); shared simultaneous capacity: \(state.simultaneousCapacity)"))
        }
        if !h.contacts.isEmpty {result.append(.init(id:"contact|channel",kind:"contactChannel",subjectIDs:h.contacts.map(\.id),evidenceIDs:[receipt.contextDigest],status:receipt.snapshot.services[Svc.handset] == .operational && receipt.snapshot.services[Svc.cellular] == .operational ? "recorded handset and cellular operational in exercise" : "channel unavailable or unknown in exercise"))}
        for route in receipt.routes where !route.sharedChokepoints.isEmpty {
            guard let personID=route.request.personID else {continue}
            result.append(.init(id:"route|\(personID)",kind:"sharedRoute",subjectIDs:[personID],evidenceIDs:route.sharedChokepoints,status:"routes share geometry; alternative is not independent"))
        }
        if h.transport.destinations.count>1 {result.append(.init(id:"meetup|transport",kind:"commonTransport",subjectIDs:h.transport.destinations.map(\.id),evidenceIDs:["transport",receipt.contextDigest],status:"destinations depend on recorded transport; inspect exercise availability"))}
        if dependencyPolicy == .recordedAccess {
            // Only recorded, potentially nonempty stock. Unknown quantities remain conditional.
            let stock=(receipt.inventory?.items ?? []).filter{$0.remaining != 0}
            let stored=stock.filter{$0.carrierPersonID == nil && $0.locationID.flatMap{initial.home?.space($0)} != nil}
            let groups=Dictionary(grouping:stored,by:{$0.locationID!})
            for room in groups.keys.sorted() {
                let items=groups[room]!.sorted{$0.id<$1.id}
                let categories=Set(items.map(\.category))
                let sole=categories.filter{category in stock.filter{$0.category==category}.allSatisfy{$0.carrierPersonID == nil && $0.locationID==room}}.sorted()
                let access=items.allSatisfy{$0.accessible==true} ? "available" : items.allSatisfy{$0.accessible==false} ? "unavailable" : "mixed or unknown"
                result.append(.init(id:"storage|\(room)",kind:"recordedSupplyStorage",subjectIDs:items.map(\.id),evidenceIDs:[receipt.contextDigest,room],
                    status:"Recorded inventory only; access \(access). \(sole.isEmpty ? "Subset of stock." : "Sole recorded location for \(sole.count) stock categories.") Unknown quantities conditional; access loss cause unproven."))
            }
            for carrier in Set(stock.compactMap(\.carrierPersonID)).sorted() {
                result.append(.init(id:"carrier|\(carrier)",kind:"recordedSupplyCarrier",subjectIDs:stock.filter{$0.carrierPersonID==carrier}.map(\.id).sorted(),evidenceIDs:[receipt.contextDigest,carrier],status:"Recorded inventory only; supplies currently carried by one exercise occupant; simultaneous carrying capacity unknown."))
            }
            for destination in h.transport.destinations.sorted(by:{$0.id<$1.id}) {
                let conditions=destination.conditionsConfirmed.confirmedValue
                result.append(.init(id:"destination|\(destination.id)",kind:"destinationConditions",subjectIDs:[destination.id],evidenceIDs:[receipt.contextDigest],status:conditions==true ? "Recorded conditions confirmed; activation and needed capabilities require current source verification. No real-time availability inferred." : conditions==false ? "Recorded conditions not met; exercise review prompt, not a claim about present availability." : "Recorded destination conditions unverified; needed capability and activation remain unknown."))
            }
        }
        return result.sorted{$0.id<$1.id}
    }
}
