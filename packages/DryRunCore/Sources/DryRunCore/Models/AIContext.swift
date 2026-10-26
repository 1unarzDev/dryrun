import Foundation
public struct AnonymousPerson: Codable, Sendable {public var id:String;public var ageBand:String;public var needs:[String]}
public struct AnonymousPet: Codable, Sendable {public var id:String;public var kind:String;public var count:Int}
public struct AnonymousEquipment: Codable, Sendable {public var id:String;public var personID:String?;public var essential:Bool;public var powerRequired:Bool;public var documentation:String}
public struct AIEvidenceRecord: Codable, Sendable {public var id:String;public var origin:String;public var status:String;public var sourceIDs:[String];public var fieldIDs:[String];public var jurisdiction:String?;public var retrievedAt:String?;public var uncertainty:String?}
public struct HouseholdContextSnapshot: Codable, Sendable {
    public var revision:Int;public var people:[AnonymousPerson];public var pets:[AnonymousPet];public var equipment:[AnonymousEquipment]
    public var transport:String;public var limitedBudget:Bool;public var regionID:String;public var evidence:[AIEvidenceRecord]
    public init(_ h:HouseholdProfile){
        revision=h.revision;people=h.people.map{AnonymousPerson(id:$0.id,ageBand:$0.ageBand.rawValue,needs:$0.needs.map(\.rawValue).sorted())}
        pets=h.pets.map{AnonymousPet(id:$0.id,kind:$0.kind.rawValue,count:$0.count)}
        equipment=h.equipment.map{AnonymousEquipment(id:$0.id,personID:$0.personID,essential:$0.isEssential,powerRequired:$0.requiresElectricalPower,documentation:MedicalBackupReadiness.isReady($0,in:h) ? "confirmed":"unknown")}
        transport=h.transport.hasVehicle ? "car":"noCar";limitedBudget=h.supplies.limitedBudget;regionID=h.regionID
        evidence=[AIEvidenceRecord(id:"household-needs",origin:"userConfirmed",status:"confirmed",sourceIDs:[],fieldIDs:["people.needs","pets","equipment"],jurisdiction:nil,retrievedAt:nil,uncertainty:nil)]
    }
}
/// Graph/provenance remains canonical HomeModel, with private labels/notes removed before cloud use.
public struct HomeSceneContext: Codable, Sendable {
    public var schemaVersion:String;public var homeRevision:Int;public var units:String;public var coordinateConvention:String
    public var floors:[FloorContext];public var rooms:[RoomContext];public var portals:[PortalContext]
    public var walls:[WallSegment];public var connectors:[FloorConnector];public var obstacles:[ObstacleContext];public var objects:[ObjectContext]
    public var unknowns:[String]
    public struct FloorContext: Codable, Sendable {public var id:String;public var elevation:Double;public var transform:Transform2D}
    public struct RoomContext: Codable, Sendable {public var id:String;public var floorID:String;public var polygon:[Vec2];public var use:String;public var confirmed:Bool}
    public struct PortalContext: Codable, Sendable {public var id:String;public var floorID:String;public var kind:String;public var verification:String;public var a:Vec2;public var b:Vec2;public var sideA:String;public var sideB:String;public var clearWidth:EvidenceValue<Double>;public var operable:EvidenceValue<Bool>;public var stepFree:EvidenceValue<Bool>}
    public struct ObstacleContext: Codable, Sendable {public var id:String;public var floorID:String;public var polygon:[Vec2]}
    public struct ObjectContext: Codable, Sendable {public var id:String;public var kind:String;public var roomID:String?;public var verification:String}
    static func destination(_ d:PortalDestination)->String {switch d{case .space(let id):return id;case .exterior:return "exterior";case .commonArea(let id):return "common|\(id)";case .unknown:return "unknown"}}
    public init(_ home:HomeModel){
        schemaVersion="dryrun.home-scene/1";homeRevision=home.revision;units="meter";coordinateConvention="per-floor x/y right-handed; floor transforms to common"
        floors=home.floors.map{FloorContext(id:$0.id,elevation:$0.elevationMeters,transform:$0.toCommon)}
        rooms=home.spaces.map{RoomContext(id:$0.id,floorID:$0.floorID,polygon:$0.polygon,use:$0.kind.rawValue,confirmed:$0.labelConfirmed)}
        portals=home.portals.map{PortalContext(id:$0.id,floorID:$0.floorID,kind:$0.kind.rawValue,verification:$0.verification.rawValue,a:$0.a,b:$0.b,sideA:Self.destination($0.sideA),sideB:Self.destination($0.sideB),clearWidth:$0.clearWidthMeters,operable:$0.operable,stepFree:$0.stepFree)}
        walls=home.walls;connectors=home.connectors
        obstacles=home.obstacles.map{ObstacleContext(id:$0.id,floorID:$0.floorID,polygon:$0.polygon)}
        objects=home.annotations.map{ObjectContext(id:$0.id,kind:$0.kind.rawValue,roomID:$0.spaceID,verification:$0.verification.rawValue)}
        unknowns=["Window operability/exterior grade require recorded confirmation","Geometry does not establish structural shelter performance","Image observations cannot create graph edges"]
    }
}
