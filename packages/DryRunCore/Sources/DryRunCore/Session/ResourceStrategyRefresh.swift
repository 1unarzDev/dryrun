import Foundation
/// Relevant normalized inputs only. Native origin/search fingerprint remains separate and local.
public struct ResourceStrategyKey: Codable, Hashable, Sendable {
    public var gapCategories:[String];public var transport:String;public var limitedBudget:Bool;public var regionID:String
    public init(gapCategories:[String],transport:String,limitedBudget:Bool,regionID:String){self.gapCategories=Array(Set(gapCategories)).sorted();self.transport=transport;self.limitedBudget=limitedBudget;self.regionID=regionID}
}
public struct ResourceStrategyRefresh: Sendable {
    public struct Ticket: Sendable, Equatable {public var generation:Int;public var key:ResourceStrategyKey}
    private var generation=0
    private var pending:ResourceStrategyKey?
    public private(set) var acceptedKey:ResourceStrategyKey?
    public private(set) var acceptedPlans:[ResourceSearchPlan]=[]
    public private(set) var cloudOptIn=false
    public init(){}
    public mutating func setCloudOptIn(_ enabled:Bool){cloudOptIn=enabled;if !enabled{generation += 1;pending=nil}}
    public mutating func begin(_ key:ResourceStrategyKey)->Ticket? {
        guard cloudOptIn,key != acceptedKey,key != pending else{return nil}
        generation += 1;pending=key;return Ticket(generation:generation,key:key)
    }
    public mutating func accept(_ plans:[ResourceSearchPlan],ticket:Ticket)throws {
        guard cloudOptIn,ticket.generation==generation,ticket.key==pending else{throw SessionError.stale}
        guard plans.count<=3,plans.allSatisfy({$0.cloudReturnPolicy=="local_only" && $0.expansionLimit<=2 && $0.maximumDistanceKm>0 && $0.maximumDistanceKm<=100}) else{throw SessionError.invalidCommand}
        acceptedKey=ticket.key;acceptedPlans=plans;pending=nil
    }
    public mutating func failed(ticket:Ticket){if ticket.generation==generation{pending=nil}} // Retain useful accepted results.
}
