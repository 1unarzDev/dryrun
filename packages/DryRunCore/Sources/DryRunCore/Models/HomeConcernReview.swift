import Foundation
public struct RoomImageManifest: Codable, Sendable, Hashable {
    public var id:String; public var homeRevision:Int; public var roomID:String?; public var digest:String
    public var capturedAt:Date; public var width:Int; public var height:Int; public var orientation:String
    public var calibration:String; public var transforms:[ImageTransform]; public var redactedRegions:[[Double]]
    public struct ImageTransform:Codable,Sendable,Hashable {public var kind:String;public var values:[Double];public init(kind:String,values:[Double]){self.kind=kind;self.values=values}}
    public init(id:String,homeRevision:Int,roomID:String?,digest:String,capturedAt:Date,width:Int,height:Int,orientation:String,calibration:String,transforms:[ImageTransform],redactedRegions:[[Double]]){self.id=id;self.homeRevision=homeRevision;self.roomID=roomID;self.digest=digest;self.capturedAt=capturedAt;self.width=width;self.height=height;self.orientation=orientation;self.calibration=calibration;self.transforms=transforms;self.redactedRegions=redactedRegions}
}
public enum ConcernDecision: String, Codable, Sendable { case confirmed, dismissed, uncertain }
public struct HomeConcernProposal: Codable, Sendable {
    public var id:String; public var homeRevision:Int; public var imageID:String; public var imageDigest:String
    /// [ymin,xmin,ymax,xmax], relative to the exact submitted image; never metres.
    public var box:[Double]; public var roomID:String?; public var category:String
    public var visibleEvidence:String; public var unknowns:[String]; public var actionID:String; public var scenarioIDs:[String]
    public init(id:String,homeRevision:Int,imageID:String,imageDigest:String,box:[Double],roomID:String?,category:String,visibleEvidence:String,unknowns:[String],actionID:String,scenarioIDs:[String]){self.id=id;self.homeRevision=homeRevision;self.imageID=imageID;self.imageDigest=imageDigest;self.box=box;self.roomID=roomID;self.category=category;self.visibleEvidence=visibleEvidence;self.unknowns=unknowns;self.actionID=actionID;self.scenarioIDs=scenarioIDs}
}
public struct ReviewedConcern: Codable, Sendable {
    public var proposal:HomeConcernProposal; public var decision:ConcernDecision; public var reviewedAt:Date
    public var sourceHomeFingerprint:String?
    public var taskID:String? {decision == .confirmed ? "concern|\(proposal.id)" : nil}
    public var canAffectConfirmedScenario:Bool {decision == .confirmed}
}
public struct ConcernLedger: Codable, Sendable {
    public private(set) var reviewed:[ReviewedConcern]=[]
    public init(){}
    public func shouldOffer(_ proposal:HomeConcernProposal)->Bool {
        !reviewed.contains { old in
            // A geometry/metadata revision is not new photographic evidence. Preserve the
            // family's review of identical submitted pixels even if a model assigns a new ID.
            // Task/scenario applicability is separately bound to the current home fingerprint.
            guard old.proposal.imageDigest==proposal.imageDigest,old.proposal.roomID==proposal.roomID,old.proposal.category==proposal.category else{return false}
            let a=old.proposal.box,b=proposal.box
            guard a.count==4,b.count==4 else{return false}
            let overlap=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
            let union=(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-overlap
            return union>0 && overlap/union>0.4
        }
    }
    public mutating func review(_ proposal:HomeConcernProposal,decision:ConcernDecision,manifest:RoomImageManifest,currentHomeRevision:Int,at date:Date,sourceHomeFingerprint:String?=nil) throws {
        guard proposal.homeRevision==currentHomeRevision,manifest.homeRevision==currentHomeRevision,
              proposal.imageID==manifest.id,proposal.imageDigest==manifest.digest,
              proposal.roomID==manifest.roomID,proposal.box.count==4,
              proposal.box.allSatisfy({$0.isFinite && $0>=0 && $0<=1}),proposal.box[2]>proposal.box[0],proposal.box[3]>proposal.box[1],
              ["possibleObstruction","tripHazard","supplyAccess"].contains(proposal.category),!proposal.unknowns.isEmpty else {throw SessionError.invalidCommand}
        if reviewed.contains(where:{$0.proposal.id==proposal.id && $0.proposal.imageDigest==proposal.imageDigest && $0.decision==decision}) {throw SessionError.duplicate}
        reviewed.removeAll{$0.proposal.id==proposal.id};reviewed.append(ReviewedConcern(proposal:proposal,decision:decision,reviewedAt:date,sourceHomeFingerprint:sourceHomeFingerprint))
    }
}
/// Native-only geographic data. Never serialize these through a generic cloud tool continuation.
public struct NativeResourceCandidate: Sendable {
    public var id:String; public var name:String; public var category:String; public var distanceKm:Double?
    public var officialResourceID:String?; public var verifiedIdentity:Bool; public var unverifiedCapabilities:[String]
    public init(id:String,name:String,category:String,distanceKm:Double?=nil,officialResourceID:String?=nil,verifiedIdentity:Bool=false,unverifiedCapabilities:[String]=[]){self.id=id;self.name=name;self.category=category;self.distanceKm=distanceKm;self.officialResourceID=officialResourceID;self.verifiedIdentity=verifiedIdentity;self.unverifiedCapabilities=unverifiedCapabilities}
}
public protocol NativeResourceSearching: Sendable {
    func search(category:String,travelMode:String,maximumDistanceKm:Double) async throws -> [NativeResourceCandidate]
}
public enum ResourceMatchExplanation {
    public static func localReason(taskTitle:String,missingPredicate:String,candidate:NativeResourceCandidate)->String {
        "This \(candidate.category) candidate may help with \(taskTitle) (\(missingPredicate)). Availability and suitability need confirmation before going."
    }
}
