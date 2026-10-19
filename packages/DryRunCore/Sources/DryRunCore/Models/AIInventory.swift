import Foundation

public enum InventoryUnit: String, Codable, Sendable, Hashable { case liter, usGallon, count, wattHour, day }
public struct InventoryItem: Codable, Sendable, Hashable {
    public var id: String
    public var physicalID: String
    public var category: String
    public var quantity: EvidenceValue<Double>
    public var unit: InventoryUnit
    public var usableQuantity: EvidenceValue<Double>
    public var accessible: EvidenceValue<Bool>
    public var locationID: String?
    public var expiresAt: Date?
    public var subjectIDs: [String]
    public var evidenceIDs: [String]
    public var lastConfirmedAt: Date?
    public init(id: String, physicalID: String, category: String, quantity: EvidenceValue<Double>, unit: InventoryUnit,
                usableQuantity: EvidenceValue<Double> = .unknown, accessible: EvidenceValue<Bool> = .unknown,
                locationID: String? = nil, expiresAt: Date? = nil, subjectIDs: [String] = [], evidenceIDs: [String] = [], lastConfirmedAt: Date? = nil) {
        self.id=id; self.physicalID=physicalID; self.category=category; self.quantity=quantity; self.unit=unit
        self.usableQuantity=usableQuantity; self.accessible=accessible; self.locationID=locationID; self.expiresAt=expiresAt
        self.subjectIDs=subjectIDs; self.evidenceIDs=evidenceIDs; self.lastConfirmedAt=lastConfirmedAt
    }
}
public struct InventoryLedger: Codable, Sendable {
    public private(set) var revision: Int = 0
    public private(set) var items: [InventoryItem] = []
    public init() {}
    public mutating func confirm(_ proposals: [InventoryItem], baseRevision: Int, at date: Date) throws {
        guard baseRevision == revision else { throw SessionError.stale }
        var candidate=items
        for var p in proposals {
            guard !p.id.isEmpty,!p.physicalID.isEmpty,
                  p.quantity.status != .confirmed || p.quantity.origin == .userConfirmed,
                  p.usableQuantity.status != .confirmed || p.usableQuantity.origin == .userConfirmed,
                  p.accessible.status != .confirmed || p.accessible.origin == .userConfirmed,
                  p.quantity.confirmedValue.map({$0.isFinite && $0>=0}) ?? true,
                  p.usableQuantity.confirmedValue.map({usable in usable.isFinite && usable>=0 && (p.quantity.confirmedValue.map{q in usable<=q} ?? true)}) ?? true else { throw SessionError.invalidCommand }
            if let old=candidate.first(where: {$0.id==p.id || $0.physicalID==p.physicalID}), old.id != p.id { throw SessionError.duplicate }
            p.lastConfirmedAt=date; candidate.removeAll{$0.id==p.id};candidate.append(p)
        }
        guard candidate.count<=500,Set(candidate.map(\.id)).count==candidate.count,Set(candidate.map(\.physicalID)).count==candidate.count else {throw SessionError.duplicate}
        items=candidate;revision += 1
    }
    /// S26 CDC storage planning baseline; pet/infant/device-specific additions remain recorded requirements.
    public func waterGap(people: Int, days: Int = 3, at date: Date) throws -> SupplyGap {
        guard people>0, people<=100, days>=3, days<=30,items.count<=500,
              Set(items.map(\.id)).count==items.count,Set(items.map(\.physicalID)).count==items.count else { throw SessionError.invalidCommand }
        let required=Double(people*days)*3.785411784
        var known=0.0, unknown = !items.contains{$0.category=="water"}
        for i in items where i.category=="water" {
            if let expiry=i.expiresAt, expiry<=date { continue }
            guard i.unit == .liter || i.unit == .usGallon else { throw SessionError.invalidCommand }
            if i.accessible.confirmedValue == false { continue }
            guard i.accessible.confirmedValue==true, let q=i.usableQuantity.confirmedValue else { unknown=true;continue }
            guard q.isFinite,q>=0,i.usableQuantity.origin == .userConfirmed,i.accessible.origin == .userConfirmed,
                  i.quantity.confirmedValue.map({$0.isFinite && $0>=q}) ?? true else {throw SessionError.invalidCommand}
            known += q * (i.unit == .usGallon ? 3.785411784 : 1)
        }
        return SupplyGap(category:"water",required:required,confirmedUsable:known,deficit:known>=required ? 0 : unknown ? nil : max(0,required-known),unit:"liter",unknown:unknown,sourceIDs:["S26"])
    }
    /// Explicit adapter for legacy totals; call once during migration, never add both representations.
    public static func migrating(_ supplies: Supplies, at date: Date) throws -> InventoryLedger {
        var ledger=InventoryLedger()
        if let water=supplies.storedWaterGallons.confirmedValue {
            try ledger.confirm([InventoryItem(id:"legacy-water",physicalID:"legacy-water-total",category:"water",quantity:.confirmed(water),unit:.usGallon,usableQuantity:.confirmed(water),accessible:.unknown,evidenceIDs:["supplies.storedWaterGallons"])],baseRevision:0,at:date)
        }
        return ledger
    }
}
public struct SupplyGap: Codable, Sendable {
    public var category:String; public var required:Double; public var confirmedUsable:Double; public var deficit:Double?
    public var unit:String; public var unknown:Bool; public var sourceIDs:[String]
}

/// A quantity requirement comes from reviewed guidance or the household's recorded instructions.
/// No model may invent a per-person medication, infant, pet or device allowance.
public struct RecordedSupplyRequirement: Codable, Sendable {
    public var id:String
    public var category:String
    public var quantity:Double
    public var unit:InventoryUnit
    public var subjectIDs:[String]
    public var sourceIDs:[String]
    public init(id:String,category:String,quantity:Double,unit:InventoryUnit,subjectIDs:[String]=[],sourceIDs:[String]) {
        self.id=id;self.category=category;self.quantity=quantity;self.unit=unit;self.subjectIDs=subjectIDs;self.sourceIDs=sourceIDs
    }
}
public extension InventoryLedger {
    /// Explicit household-coverage days only. Package counts and person-restricted quantities
    /// cannot be converted into a whole household's food-days by inference.
    func householdFoodGap(personIDs:[String],at date:Date)throws->SupplyGap {
        guard !personIDs.isEmpty,personIDs.count<=100,personIDs.allSatisfy({!$0.isEmpty}),Set(personIDs).count==personIDs.count,items.count<=500,Set(items.map(\.id)).count==items.count,Set(items.map(\.physicalID)).count==items.count else {throw SessionError.invalidCommand}
        var days=self
        days.items=items.filter{$0.category=="food" && $0.unit == .day}
        var result=try days.gap(for:RecordedSupplyRequirement(id:"household-food-days",category:"food",quantity:3,unit:.day,subjectIDs:personIDs,sourceIDs:["S64"]),at:date)
        let unsupported=items.contains {item in
            item.category=="food" && item.unit != .day && item.expiresAt.map{$0<=date} != true && item.accessible.confirmedValue != false
                && (item.subjectIDs.isEmpty || Set(personIDs).isSubset(of:Set(item.subjectIDs)))
        }
        if unsupported {result.unknown=true;if result.confirmedUsable<result.required {result.deficit=nil}}
        return result
    }
    /// Shared household quantities are counted once. Subject-restricted supplies cannot cover another person.
    /// Requirements must already be consolidated by physical purpose; incompatible units fail explicitly.
    func gap(for requirement:RecordedSupplyRequirement,at date:Date)throws->SupplyGap {
        guard !requirement.id.isEmpty,!requirement.category.isEmpty,requirement.quantity.isFinite,
              requirement.quantity>=0,!requirement.sourceIDs.isEmpty,
              Set(items.map(\.id)).count==items.count,Set(items.map(\.physicalID)).count==items.count else {throw SessionError.invalidCommand}
        let relevant=items.filter{$0.category==requirement.category && ($0.subjectIDs.isEmpty || Set(requirement.subjectIDs).isSubset(of:Set($0.subjectIDs)))}
        var usable=0.0,unknown=relevant.isEmpty
        for item in relevant {
            if item.expiresAt.map({$0<=date})==true || item.accessible.confirmedValue==false {continue}
            guard item.accessible.confirmedValue==true,let amount=item.usableQuantity.confirmedValue else {unknown=true;continue}
            guard amount.isFinite,amount>=0,item.usableQuantity.origin == .userConfirmed,item.accessible.origin == .userConfirmed,
                  item.quantity.confirmedValue.map({$0.isFinite && $0>=amount}) ?? true else {throw SessionError.invalidCommand}
            let converted:Double
            if item.unit==requirement.unit {converted=amount}
            else if item.unit == .usGallon && requirement.unit == .liter {converted=amount*3.785411784}
            else if item.unit == .liter && requirement.unit == .usGallon {converted=amount/3.785411784}
            else {throw SessionError.invalidCommand}
            usable+=converted
            guard usable.isFinite else {throw SessionError.invalidCommand}
        }
        return SupplyGap(category:requirement.category,required:requirement.quantity,confirmedUsable:usable,
                         deficit:usable>=requirement.quantity ? 0 : unknown ? nil : requirement.quantity-usable,
                         unit:requirement.unit.rawValue,unknown:unknown,sourceIDs:requirement.sourceIDs)
    }
}
