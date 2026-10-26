import Foundation
public struct AnonymousPerson: Codable, Sendable {public var id:String;public var ageBand:String;public var needs:[String];public var recordedConditions:String?;public var essentialMedication:String?;public var communicationInstructions:String?;public var helperPersonID:String?;public var startingRoomID:String?}
public struct AnonymousPet: Codable, Sendable {public var id:String;public var kind:String;public var count:Int}
public struct AnonymousEquipment: Codable, Sendable {public var id:String;public var personID:String?;public var essential:Bool;public var powerRequired:Bool;public var documentation:String;public var purpose:String?;public var requiresColdStorage:Bool?;public var storageInstructions:String?;public var powerWatts:EvidenceValue<Double>?;public var documentedBackupRuntimeHours:EvidenceValue<Double>?;public var compatibleBackupIDs:[String]?}
/// Recorded source specifications, not a promise of usable equipment continuity.
public struct AnonymousBackupPower:Codable,Sendable {
    public var id:String;public var kind:BackupPowerKind
    public var usableEnergyWh:EvidenceValue<Double>;public var continuousOutputW:EvidenceValue<Double>
    public var setupConfirmed:EvidenceValue<Bool>;public var islandingConfirmed:EvidenceValue<Bool>
    public var safeOutdoorPlacementConfirmed:EvidenceValue<Bool>;public var assumedEfficiency:Double
    init(_ source:BackupPowerSource){id=source.id;kind=source.kind;usableEnergyWh=source.usableEnergyWh;continuousOutputW=source.continuousOutputW;setupConfirmed=source.setupConfirmed;islandingConfirmed=source.islandingConfirmed;safeOutdoorPlacementConfirmed=source.safeOutdoorPlacementConfirmed;assumedEfficiency=source.assumedEfficiency}
}
/// Real recorded ledger only. Session resource receipts own simulated balances/access.
/// Physical labels/identifiers are deliberately excluded; stable item/room/member IDs
/// let the host resolve names and validate executable actions locally.
public struct AnonymousInventory:Codable,Sendable {
    public var scope:String = "recordedHouseholdInventory"
    public var revision:Int;public var asOf:Date;public var items:[Item]
    public struct Item:Codable,Sendable {
        public var id:String;public var category:String;public var quantity:EvidenceValue<Double>;public var unit:InventoryUnit
        public var usableQuantity:EvidenceValue<Double>;public var accessible:EvidenceValue<Bool>
        public var locationID:String?;public var expiresAt:Date?;public var subjectIDs:[String];public var evidenceIDs:[String]
        public var lastConfirmedAt:Date?;public var preparationKind:InventoryPreparationKind?
    }
    init(_ ledger:InventoryLedger,at date:Date){revision=ledger.revision;asOf=date;items=ledger.items.map{Item(id:$0.id,category:$0.category,quantity:$0.quantity,unit:$0.unit,usableQuantity:$0.usableQuantity,accessible:$0.accessible,locationID:$0.locationID,expiresAt:$0.expiresAt,subjectIDs:$0.subjectIDs,evidenceIDs:$0.evidenceIDs,lastConfirmedAt:$0.lastConfirmedAt,preparationKind:$0.preparationKind)}}
}
public struct AIEvidenceRecord: Codable, Sendable {public var id:String;public var origin:String;public var status:String;public var sourceIDs:[String];public var fieldIDs:[String];public var jurisdiction:String?;public var retrievedAt:String?;public var uncertainty:String?}
public struct AnonymousHousing: Codable, Sendable {
    public var homeType: HomeType; public var tenancy: Tenancy; public var floorCount: Int
    public var heatingFuel: HeatingFuel; public var heatingNeedsElectricity: EvidenceValue<Bool>
    public var cooling: CoolingKind; public var waterSource: WaterSourceKind
    public var wellPumpElectric: EvidenceValue<Bool>; public var sanitation: SanitationKind
    public init(_ h: Housing) { homeType=h.homeType; tenancy=h.tenancy; floorCount=h.floorCount; heatingFuel=h.heatingFuel
        heatingNeedsElectricity=h.heatingNeedsElectricity; cooling=h.cooling; waterSource=h.waterSource; wellPumpElectric=h.wellPumpElectric; sanitation=h.sanitation }
}
/// Relevant recorded quantities/presence with provenance, never inferred absence or ownership.
public struct AnonymousSupplies:Codable,Sendable {
    public var storedWaterGallons:EvidenceValue<Double>
    public var shelfStableFoodDays:EvidenceValue<Double>
    public var flashlights:EvidenceValue<Int>
    public var coolerAndIcePacks:EvidenceValue<Bool>
    public var firstAidKit:EvidenceValue<Bool>
    public var fireExtinguisher:EvidenceValue<Bool>
    public var limitedStorageSpace:Bool
    init(_ s:Supplies){storedWaterGallons=s.storedWaterGallons;shelfStableFoodDays=s.shelfStableFoodDays;flashlights=s.flashlights;coolerAndIcePacks=s.coolerAndIcePacks;firstAidKit=s.firstAidKit;fireExtinguisher=s.fireExtinguisher;limitedStorageSpace=s.limitedStorageSpace}
}
public struct HouseholdContextSnapshot: Codable, Sendable {
    public var revision:Int;public var people:[AnonymousPerson];public var pets:[AnonymousPet];public var equipment:[AnonymousEquipment]
    public var transport:String;public var limitedBudget:Bool;public var regionID:String;public var evidence:[AIEvidenceRecord]
    public var supplies:AnonymousSupplies?
    public var backupPower:[AnonymousBackupPower]?
    public var inventory:AnonymousInventory?
    public var housing: AnonymousHousing?
    public var site: SiteHazardContext?
    public init(_ h:HouseholdProfile, inventory ledger:InventoryLedger? = nil, at date:Date = Date()){
        backupPower=h.backupPower.map(AnonymousBackupPower.init)
        inventory=ledger.map{AnonymousInventory($0,at:date)}
        supplies=AnonymousSupplies(h.supplies)
        housing=AnonymousHousing(h.housing); site=SiteHazardContext(h.siteHazards,jurisdictionID:h.regionID,at:date,locationBinding:SiteHazardBinding.of(h))
        revision=h.revision;people=h.people.map{AnonymousPerson(id:$0.id,ageBand:$0.ageBand.rawValue,needs:$0.needs.map(\.rawValue).sorted(),recordedConditions:Self.recorded($0.emergencyInformation?.criticalConditions),essentialMedication:Self.recorded($0.emergencyInformation?.essentialMedication),communicationInstructions:Self.recorded($0.communicationNotes),helperPersonID:$0.helperPersonID,startingRoomID:$0.sleepingSpaceID)}
        pets=h.pets.map{AnonymousPet(id:$0.id,kind:$0.kind.rawValue,count:$0.count)}
        equipment=h.equipment.map{AnonymousEquipment(id:$0.id,personID:$0.personID,essential:$0.isEssential,powerRequired:$0.requiresElectricalPower,documentation:MedicalBackupReadiness.isReady($0,in:h) ? "confirmed":"unknown",purpose:$0.purpose.rawValue,requiresColdStorage:$0.requiresColdStorage,storageInstructions:Self.recorded($0.storageInstructions),powerWatts:$0.powerWatts,documentedBackupRuntimeHours:$0.documentedBackupRuntimeHours,compatibleBackupIDs:$0.compatibleBackupIDs)}
        transport=h.transport.hasVehicle ? "car":"noCar";limitedBudget=h.supplies.limitedBudget;regionID=h.regionID
        evidence=[AIEvidenceRecord(id:"household-needs",origin:"userConfirmed",status:"confirmed",sourceIDs:[],fieldIDs:["people.needs","pets","equipment","housing"],jurisdiction:nil,retrievedAt:nil,uncertainty:nil)]
        evidence.append(AIEvidenceRecord(id:"recorded-backup-power",origin:"userConfirmed",status:"confirmed",sourceIDs:[],fieldIDs:["backupPower"],jurisdiction:nil,retrievedAt:nil,uncertainty:"Recorded source list only; individual specification/setup fields retain their own confirmation status. No inferred compatibility or runtime."))
        if ledger != nil {evidence.append(AIEvidenceRecord(id:"recorded-inventory",origin:"userConfirmed",status:"confirmed",sourceIDs:[],fieldIDs:["inventory"],jurisdiction:nil,retrievedAt:nil,uncertainty:"Recorded ledger only; quantities, access, expiry and member restrictions retain their own evidence. This is not the simulated remaining stock or current incident access."))}
        evidence += (site?.sourceIDs ?? []).map{ sourceID in AIEvidenceRecord(id:sourceID,origin:"officialSource",status:"confirmed",sourceIDs:[sourceID],fieldIDs:["site.planningEvidence"],jurisdiction:h.regionID,retrievedAt:site?.sources?.first(where:{$0.id==sourceID}).map{ISO8601DateFormatter().string(from:$0.retrievedAt)},uncertainty:"Planning evidence only; no current hazard, route clearance or evacuation activation") }
    }
    private static func recorded(_ value:String?)->String? {
        guard let value=value?.trimmingCharacters(in:.whitespacesAndNewlines),!value.isEmpty else {return nil}
        return String(value.prefix(1200))
    }

}
/// Graph/provenance remains canonical HomeModel, with private labels/notes removed before cloud use.
public struct HomeSceneContext: Codable, Sendable {
    public var schemaVersion:String;public var homeRevision:Int;public var units:String;public var coordinateConvention:String
    public var floors:[FloorContext];public var rooms:[RoomContext];public var portals:[PortalContext]
    public var walls:[WallSegment];public var connectors:[FloorConnector];public var obstacles:[ObstacleContext];public var objects:[ObjectContext]
    public var unknowns:[String]
    public var homeSource:HomeSource?
    public var dwellingType:HomeType?
    public var planningRoutes:[HomePlanningRoute]?
    public var planningNeeds:[HousingPlanningNeed]?
    public struct FloorContext: Codable, Sendable {public var id:String;public var elevation:Double;public var transform:Transform2D;public var level:Int?;public var exteriorGrade:ExteriorGrade?}
    public struct RoomContext: Codable, Sendable {public var id:String;public var floorID:String;public var polygon:[Vec2];public var use:String;public var confirmed:Bool;public var geometryNeedsReview:Bool?;public var needsMeasurement:Bool?;public var interiorNoWindowsConfirmed:EvidenceValue<Bool>?;public var higherRefugeConfirmed:EvidenceValue<Bool>?;public var confirmedShelter:Bool?}
    public struct PortalContext: Codable, Sendable {public var id:String;public var floorID:String;public var kind:String;public var verification:String;public var a:Vec2;public var b:Vec2;public var sideA:String;public var sideB:String;public var clearWidth:EvidenceValue<Double>;public var operable:EvidenceValue<Bool>;public var stepFree:EvidenceValue<Bool>;public var emergencyEscapePersonIDs:[String]?}
    public struct ObstacleContext: Codable, Sendable {public var id:String;public var floorID:String;public var polygon:[Vec2]}
    public struct ObjectContext: Codable, Sendable {public var id:String;public var kind:String;public var roomID:String?;public var verification:String;public var floorID:String?;public var position:Vec2?}
    static func destination(_ d:PortalDestination)->String {switch d{case .space(let id):return id;case .exterior:return "exterior";case .commonArea(let id):return "common|\(id)";case .unknown:return "unknown"}}
    public init(_ home:HomeModel, household:HouseholdProfile) {
        var source=home
        if household.housing.homeType == .manufacturedHome || home.dwellingType == .manufacturedHome { source.dwellingType = .manufacturedHome }
        else { source.dwellingType = household.housing.homeType }
        self.init(source)
        planningRoutes=HousingPlanning.routes(household:household,home:source)
        planningNeeds=HousingPlanning.needs(household:household,home:source)
    }
    public init(_ home:HomeModel){
        schemaVersion="dryrun.home-scene/2";homeSource=home.source;dwellingType=home.dwellingType;homeRevision=home.revision;units="meter";coordinateConvention="per-floor x/y right-handed; floor transforms to common"
        floors=home.floors.map{FloorContext(id:$0.id,elevation:$0.elevationMeters,transform:$0.toCommon,level:$0.level,exteriorGrade:$0.exteriorGrade ?? .unknown)}
        rooms=home.spaces.map{RoomContext(id:$0.id,floorID:$0.floorID,polygon:$0.polygon,use:$0.kind.rawValue,confirmed:$0.labelConfirmed,geometryNeedsReview:$0.geometryNeedsReview ?? false,needsMeasurement:$0.needsMeasurement,interiorNoWindowsConfirmed:$0.interiorNoWindowsConfirmed,higherRefugeConfirmed:$0.higherRefugeConfirmed ?? .unknown,confirmedShelter:ShelterSuitability.isConfirmed(roomID:$0.id,in:home))}
        portals=home.portals.map{PortalContext(id:$0.id,floorID:$0.floorID,kind:$0.kind.rawValue,verification:$0.verification.rawValue,a:$0.a,b:$0.b,sideA:Self.destination($0.sideA),sideB:Self.destination($0.sideB),clearWidth:$0.clearWidthMeters,operable:$0.operable,stepFree:$0.stepFree,emergencyEscapePersonIDs:$0.emergencyEscapePersonIDs)}
        walls=home.walls;connectors=home.connectors
        obstacles=home.obstacles.map{ObstacleContext(id:$0.id,floorID:$0.floorID,polygon:$0.polygon)}
        objects=home.annotations.map{ObjectContext(id:$0.id,kind:$0.kind.rawValue,roomID:$0.spaceID,verification:$0.verification.rawValue,floorID:$0.floorID,position:$0.position)}
        unknowns=["Window operability/exterior grade require recorded confirmation","Geometry does not establish structural shelter performance","Image observations cannot create graph edges","confirmed is room-use confirmation, not geometry or route verification","confirmedShelter is a host-checked planning choice, not structural certification; geometry review and exterior grade remain explicit"]
    }
}
