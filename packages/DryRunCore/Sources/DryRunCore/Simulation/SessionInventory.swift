import Foundation

/// Immutable confirmed source. Exercise transfers/consumption never update this ledger.
public struct SessionInventorySeed: Codable, Sendable {
    public var ledger: InventoryLedger
    public var asOf: Date
    public init(ledger: InventoryLedger, asOf: Date) { self.ledger=ledger; self.asOf=asOf }
}
public struct ExerciseSupply: Codable, Sendable, Equatable {
    public var id:String
    public var physicalID:String
    public var category:String
    public var unit:InventoryUnit
    public var remaining:Double?
    public var consumed:Double
    public var locationID:String?
    public var carrierPersonID:String?
    /// nil is unknown, false includes expiry and modeled loss of access.
    public var accessible:Bool?
}
public struct ExerciseInventory: Codable, Sendable, Equatable {
    public var sourceRevision:Int
    public var items:[ExerciseSupply]
}

struct SessionSupplyLedger {
    let seed:SessionInventorySeed
    let sources:[String:InventoryItem]
    var state:ExerciseInventory
    var projectedGallons:Double?
    init(_ seed:SessionInventorySeed) throws {
        guard seed.asOf.timeIntervalSince1970.isFinite,seed.ledger.items.allSatisfy({$0.expiresAt?.timeIntervalSince1970.isFinite ?? true}) else {throw SessionError.invalidCommand}
        // Revalidate decoded records rather than trusting their Codable representation.
        var checked=InventoryLedger()
        try checked.confirm(seed.ledger.items,baseRevision:0,at:seed.asOf)
        self.seed=seed
        sources=Dictionary(uniqueKeysWithValues:checked.items.map{($0.id,$0)})
        state=ExerciseInventory(sourceRevision:seed.ledger.revision,items:checked.items.sorted{$0.id<$1.id}.map{
            ExerciseSupply(id:$0.id,physicalID:$0.physicalID,category:$0.category,unit:$0.unit,
                remaining:$0.quantity.confirmedValue==0 ? 0:$0.usableQuantity.confirmedValue,consumed:0,locationID:$0.locationID,carrierPersonID:nil,accessible:nil)
        })
    }
    /// Settle the existing RunState draw, then recompute access from the same committed hazard/occupants.
    mutating func synchronize(_ run:inout RunState) throws {
        if let before=projectedGallons,let after=run.storedWater {
            guard after<=before+1e-9 else {throw SessionError.invalidCommand} // no implicit replenishment
            var liters=max(0,before-after)*3.785411784
            for index in state.items.indices where state.items[index].category=="water" && state.items[index].accessible==true {
                guard let remaining=state.items[index].remaining,let source=sources[state.items[index].id],InventoryLedger.coversHousehold(source,personIDs:run.household.people.map(\.id)) else {continue}
                let factor=state.items[index].unit == .usGallon ? 3.785411784 : 1
                let used=min(remaining,liters/factor)
                state.items[index].remaining=max(0,remaining-used)
                state.items[index].consumed += used
                liters=max(0,liters-used*factor)
            }
            guard liters<1e-7 else {throw SessionError.invalidCommand}
        }
        var reachableLocations:[String:Bool]=[:]
        var gallons=0.0,unknown = !state.items.contains{$0.category=="water"},scopeUnsupported=false
        for index in state.items.indices {
            let source=sources[state.items[index].id]!
            var access=source.accessible.confirmedValue
            if source.expiresAt.map({floor($0.timeIntervalSince(seed.asOf)/60)<=Double(run.minute)})==true {access=false}
            if access==true {
                if let carrier=state.items[index].carrierPersonID,let person=run.household.people.first(where:{$0.id==carrier}) {
                    state.items[index].locationID=run.startSpace(for:person)
                }
                if let location=state.items[index].locationID {
                    if run.spatialState?.affectedSpaceIDs.contains(location)==true {access=false}
                    else if let home=run.home,home.space(location) != nil {
                        let reachable=reachableLocations[location] ?? run.household.people.contains{person in
                            run.planner.plan(RouteRequest(personID:person.id,startSpaceID:run.startSpace(for:person),mobility:run.mobility(for:person),exclusions:ScenarioExclusions(blockedSpaceIDs:run.spatialState?.affectedSpaceIDs ?? [],blockedPortalIDs:run.spatialState?.affectedPortalIDs ?? []),purpose:.helperReach,destinationSpaceID:location),in:home).primary != nil
                        }
                        reachableLocations[location]=reachable
                        if !reachable {access=false}
                    } else {access=nil}
                }
            }
            state.items[index].accessible=access
            if source.category=="water" {
                guard source.unit == .liter || source.unit == .usGallon else {throw SessionError.invalidCommand}
                if access==false || state.items[index].remaining==0 {continue}
                if !InventoryLedger.coversHousehold(source,personIDs:run.household.people.map(\.id)) {unknown=true;scopeUnsupported=true;continue}
                if access != true || state.items[index].remaining == nil {unknown=true;continue}
                gallons += state.items[index].remaining! * (source.unit == .usGallon ? 1 : 1/3.785411784)
                guard gallons.isFinite else {throw SessionError.invalidCommand}
            }
        }
        // Unknown stock cannot be turned into a confident forecast or an invented draw amount.
        if scopeUnsupported {run.unknowns.insert("inventory.water.subjectScope")}
        else {run.unknowns.remove("inventory.water.subjectScope")}
        projectedGallons=unknown ? nil : gallons
        run.storedWater=projectedGallons
        if unknown {run.unknowns.insert("inventory.water.available")}
        else {run.unknowns.remove("inventory.water.available")}
    }
    func nextExpiryMinute(after minute:Int)->Int? {
        seed.ledger.items.compactMap { item -> Int? in
            guard let expiry=item.expiresAt else {return nil}
            let delta=floor(expiry.timeIntervalSince(seed.asOf)/60)
            guard delta>Double(minute),delta<=4320 else {return nil}
            return Int(delta)
        }.min()
    }
    mutating func apply(_ command:SessionCommand,run:RunState) throws {
        guard let id=command.target,let index=state.items.firstIndex(where:{$0.id==id}) else {throw SessionError.invalidCommand}
        switch command.kind {
        case "takeSupply":
            guard state.items[index].accessible==true,state.items[index].carrierPersonID==nil,
                  let person=run.household.people.first(where:{$0.id==command.value}),
                  let location=state.items[index].locationID,location==run.startSpace(for:person) else {throw SessionError.invalidCommand}
            state.items[index].carrierPersonID=person.id
        case "transferSupply":
            guard state.items[index].accessible==true,let carrier=state.items[index].carrierPersonID,
                  let person=run.household.people.first(where:{$0.id==carrier}),
                  let destination=command.value,destination==run.startSpace(for:person),run.home?.space(destination) != nil else {throw SessionError.invalidCommand}
            state.items[index].carrierPersonID=nil;state.items[index].locationID=destination
        default:throw SessionError.invalidCommand
        }
    }
}
