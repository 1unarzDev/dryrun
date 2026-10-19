import Foundation
/// Relevant normalized inputs only. Native origin/search fingerprint remains separate and local.
public struct ResourceStrategyKey: Codable, Hashable, Sendable {
    public var gapCategories:[String];public var transport:String;public var limitedBudget:Bool;public var regionID:String
    public var schemaVersion:String?
    public var normalizedInputDigest:String?
    public var relatedTaskIDs:[String]?
    public init(gapCategories:[String],transport:String,limitedBudget:Bool,regionID:String){self.gapCategories=Array(Set(gapCategories)).sorted();self.transport=transport;self.limitedBudget=limitedBudget;self.regionID=regionID}
}
public struct ResourceStrategyRefresh: Sendable {
    public struct Ticket: Sendable, Equatable {public var generation:Int;public var key:ResourceStrategyKey}
    private var generation=0
    private var pending:ResourceStrategyKey?
    private var queued:(key:ResourceStrategyKey,due:Date)?
    public private(set) var acceptedKey:ResourceStrategyKey?
    public private(set) var acceptedPlans:[ResourceSearchPlan]=[]
    public private(set) var cloudOptIn=false
    public init(){}
    public mutating func setCloudOptIn(_ enabled:Bool){cloudOptIn=enabled;if !enabled{generation += 1;pending=nil;queued=nil}}
    public mutating func begin(_ key:ResourceStrategyKey)->Ticket? {
        guard cloudOptIn else{return nil}
        queued=nil
        if key==acceptedKey {
            if pending != nil {generation += 1;pending=nil}
            return nil
        }
        guard key != pending else{return nil}
        generation += 1;pending=key;return Ticket(generation:generation,key:key)
    }
    public mutating func accept(_ plans:[ResourceSearchPlan],ticket:Ticket)throws {
        guard cloudOptIn,ticket.generation==generation,ticket.key==pending else{throw SessionError.stale}
        let categories=["grocery","foodAssistance","pharmacy","equipmentSupplier","hardware","hospital","emergencyManagement","warmingCooling","shelter","clothing"]
        guard ticket.key.schemaVersion==nil || ticket.key.schemaVersion=="dryrun.resource-strategy-key/1" else {throw SessionError.invalidCommand}
        guard plans.count<=3,Set(plans.map(\.id)).count==plans.count,plans.allSatisfy({plan in
            !plan.id.isEmpty && !plan.taskID.isEmpty && (ticket.key.relatedTaskIDs?.contains(plan.taskID) ?? true)
                && categories.contains(plan.category) && ["walking","transit","driving","assistance"].contains(plan.travelMode)
                && (ticket.key.transport != "noCar" || plan.travelMode != "driving")
                && !plan.purpose.isEmpty && !plan.requiredEvidence.isEmpty && plan.requiredEvidence.count<=8
                && plan.mandatoryCapabilities.count<=8 && plan.unknowns.count<=8
                && plan.cloudReturnPolicy=="local_only" && (0...2).contains(plan.expansionLimit)
                && plan.maximumDistanceKm.isFinite && plan.maximumDistanceKm>0 && plan.maximumDistanceKm<=100
        }) else{throw SessionError.invalidCommand}
        acceptedKey=ticket.key;acceptedPlans=plans;pending=nil
    }
    /// Native schedules one cancellable wake-up at the returned date; no wall-clock sleeping here.
    /// A changed edit invalidates in-flight results immediately, before the debounce window ends.
    @discardableResult public mutating func enqueue(_ key:ResourceStrategyKey,at date:Date,debounceSeconds:Double=0.35)throws->Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite,debounceSeconds.isFinite,(0...5).contains(debounceSeconds) else {throw SessionError.invalidCommand}
        guard cloudOptIn else{return nil}
        if key==acceptedKey {
            if pending != nil || queued != nil {generation += 1;pending=nil;queued=nil}
            return nil
        }
        if pending==key {queued=nil;return nil}
        if let queued,queued.key==key {return queued.due}
        generation += 1;pending=nil
        let due=date.addingTimeInterval(debounceSeconds);queued=(key,due)
        return due
    }
    public mutating func beginReady(at date:Date)->Ticket? {
        guard cloudOptIn,let queued,queued.due<=date else{return nil}
        return begin(queued.key)
    }
    public mutating func failed(ticket:Ticket){if ticket.generation==generation{pending=nil}} // Retain useful accepted results.
}
