import Foundation

/// Local-only companion to a submitted image. Never forward camera matrices, capture-frame IDs
/// or depth metadata through the cloud manifest. Native capture owns actual sensor provenance.
public struct RoomImageCaptureGeometry: Codable, Sendable, Hashable {
    public var version:String = "dryrun.image-geometry/1"
    public var imageID:String
    public var imageDigest:String
    public var homeID:String
    public var homeRevision:Int
    public var captureFrameID:String
    public var cameraFrameID:String
    public var capturedAt:Date
    public var originalWidth:Int
    public var originalHeight:Int
    /// Row-major K for the original rectified image: [fx,0,cx,0,fy,cy,0,0,1].
    public var intrinsics:[Double]
    /// Row-major rigid 4x4, optical camera (right/down/forward) to the identified capture frame.
    /// Native must convert ARKit's camera convention explicitly; this is not a home registration.
    public var cameraToCapture:[Double]
    public var depth:AlignedImageDepth?
    public init(imageID:String,imageDigest:String,homeID:String,homeRevision:Int,captureFrameID:String,cameraFrameID:String,capturedAt:Date,originalWidth:Int,originalHeight:Int,intrinsics:[Double],cameraToCapture:[Double],depth:AlignedImageDepth?=nil){
        self.imageID=imageID;self.imageDigest=imageDigest;self.homeID=homeID;self.homeRevision=homeRevision
        self.captureFrameID=captureFrameID;self.cameraFrameID=cameraFrameID;self.capturedAt=capturedAt
        self.originalWidth=originalWidth;self.originalHeight=originalHeight;self.intrinsics=intrinsics;self.cameraToCapture=cameraToCapture;self.depth=depth
    }
}
/// Metadata only. Native must verify the actual depth bytes/digest, registration and confidence
/// before sampling; this record alone is never evidence of an object's 3D position.
public struct AlignedImageDepth:Codable,Sendable,Hashable {
    public var cameraFrameID:String
    public var capturedAt:Date
    public var digest:String
    public var width:Int
    public var height:Int
    public var referenceWidth:Int
    public var referenceHeight:Int
    public var source:String
    public var alignment:String
    public init(cameraFrameID:String,capturedAt:Date,digest:String,width:Int,height:Int,referenceWidth:Int,referenceHeight:Int,source:String,alignment:String="registeredToOriginalRectifiedImage"){
        self.cameraFrameID=cameraFrameID;self.capturedAt=capturedAt;self.digest=digest;self.width=width;self.height=height
        self.referenceWidth=referenceWidth;self.referenceHeight=referenceHeight;self.source=source;self.alignment=alignment
    }
}
public enum RoomImageGeometryError:Error,Equatable {
    case invalidCalibration,invalidManifest,staleSource,invalidTransform,invalidBox,redactedEvidence,imageSpaceOnly
}
public struct ImageEvidenceRays:Sendable,Equatable {
    /// Original pixel-edge coordinates in submitted-box corner order (TL, TR, BR, BL).
    public var originalPixels:[Vec2]
    /// Optical camera rays (x right, y down, z=1); neither depths nor world positions.
    public var cameraRays:[Vec3]
    public var hasRecordedAlignedDepth:Bool
}
public enum RoomImageGeometry {
    private struct Step {var kind:String;var values:[Double];var width:Double;var height:Double}
    private static func digest(_ value:String)->Bool {value.count==64 && value.allSatisfy{"0123456789abcdef".contains($0)}}
    private static func box(_ value:[Double])->Bool {value.count==4 && value.allSatisfy{$0.isFinite && (0...1).contains($0)} && value[2]>value[0] && value[3]>value[1]}
    private static func near(_ a:Double,_ b:Double)->Bool {abs(a-b)<1e-6}
    /// Validate rigid pose and original-image calibration, not physical capture accuracy.
    public static func validate(_ record:RoomImageCaptureGeometry,manifest:RoomImageManifest,home:HomeModel)throws {
        guard record.version=="dryrun.image-geometry/1",record.imageID==manifest.id,record.imageDigest==manifest.digest,
              record.homeID==home.id,record.homeRevision==home.revision,manifest.homeRevision==home.revision,
              !record.captureFrameID.isEmpty,record.captureFrameID==home.sourceCaptureFrameID,
              !record.cameraFrameID.isEmpty,record.cameraFrameID.count<=120,
              record.capturedAt.timeIntervalSince1970.isFinite,record.capturedAt==manifest.capturedAt else {throw RoomImageGeometryError.staleSource}
        do {try manifest.validate(home:home)} catch {throw RoomImageGeometryError.invalidManifest}
        let k=record.intrinsics,m=record.cameraToCapture
        guard (1...16384).contains(record.originalWidth),(1...16384).contains(record.originalHeight),
              k.count==9,m.count==16,k.allSatisfy(\.isFinite),m.allSatisfy(\.isFinite),
              k[0]>0,k[4]>0,k[2]>=0,k[2]<=Double(record.originalWidth),k[5]>=0,k[5]<=Double(record.originalHeight),
              near(k[1],0),near(k[3],0),near(k[6],0),near(k[7],0),near(k[8],1),
              near(m[12],0),near(m[13],0),near(m[14],0),near(m[15],1) else {throw RoomImageGeometryError.invalidCalibration}
        for row in 0..<3 {
            for other in 0..<3 {
                let dot=(0..<3).reduce(0.0){$0+m[row*4+$1]*m[other*4+$1]}
                guard near(dot,row==other ? 1:0) else {throw RoomImageGeometryError.invalidCalibration}
            }
        }
        let determinant=m[0]*(m[5]*m[10]-m[6]*m[9])-m[1]*(m[4]*m[10]-m[6]*m[8])+m[2]*(m[4]*m[9]-m[5]*m[8])
        guard near(determinant,1),digest(record.imageDigest) else {throw RoomImageGeometryError.invalidCalibration}
        if let d=record.depth {
            guard d.cameraFrameID==record.cameraFrameID,d.capturedAt==record.capturedAt,digest(d.digest),
                  (1...16384).contains(d.width),(1...16384).contains(d.height),
                  d.referenceWidth==record.originalWidth,d.referenceHeight==record.originalHeight,
                  ["sceneDepth","smoothedSceneDepth"].contains(d.source),d.alignment=="registeredToOriginalRectifiedImage" else {throw RoomImageGeometryError.invalidCalibration}
        }
        _=try steps(record,manifest)
    }
    private static func steps(_ record:RoomImageCaptureGeometry,_ manifest:RoomImageManifest)throws->[Step] {
        var width=Double(record.originalWidth),height=Double(record.originalHeight),result:[Step]=[]
        for transform in manifest.transforms {
            let v=transform.values
            guard v.allSatisfy(\.isFinite) else {throw RoomImageGeometryError.invalidTransform}
            result.append(Step(kind:transform.kind,values:v,width:width,height:height))
            switch transform.kind {
            case "crop":
                guard v.count==4,v.allSatisfy({$0.rounded()==$0}),v[0]>=0,v[1]>=0,v[2]>0,v[3]>0,v[0]+v[2]<=width,v[1]+v[3]<=height else {throw RoomImageGeometryError.invalidTransform}
                width=v[2];height=v[3]
            case "resize":
                guard v.count==2,v.allSatisfy({$0.rounded()==$0 && (1...16384).contains($0)}) else {throw RoomImageGeometryError.invalidTransform}
                width=v[0];height=v[1]
            case "rotate":
                guard v.count==1,v[0].rounded()==v[0],(0...3).contains(v[0]) else {throw RoomImageGeometryError.invalidTransform}
                if Int(v[0])%2==1 {swap(&width,&height)}
            case "redact":guard box(v) else {throw RoomImageGeometryError.invalidTransform}
            default:throw RoomImageGeometryError.invalidTransform
            }
        }
        guard width==Double(manifest.width),height==Double(manifest.height) else {throw RoomImageGeometryError.invalidTransform}
        return result
    }
    private static func overlaps(_ pixels:[Vec2],_ mask:[Double],width:Double,height:Double)->Bool {
        let left=pixels.map(\.x).min()!,right=pixels.map(\.x).max()!,top=pixels.map(\.y).min()!,bottom=pixels.map(\.y).max()!
        return min(right,mask[3]*width)>max(left,mask[1]*width) && min(bottom,mask[2]*height)>max(top,mask[0]*height)
    }
    /// Invert the exact recorded transform chain instead of pretending submitted pixels use
    /// the original intrinsics. No automatic EXIF/orientation rotation, depth inference or world projection.
    public static func rays(for box:[Double],manifest:RoomImageManifest,record:RoomImageCaptureGeometry,home:HomeModel)throws->ImageEvidenceRays {
        try validate(record,manifest:manifest,home:home)
        guard manifest.calibration=="submittedFrameAligned" else {throw RoomImageGeometryError.imageSpaceOnly}
        guard self.box(box) else {throw RoomImageGeometryError.invalidBox}
        let width=Double(manifest.width),height=Double(manifest.height)
        var points=[Vec2(box[1]*width,box[0]*height),Vec2(box[3]*width,box[0]*height),Vec2(box[3]*width,box[2]*height),Vec2(box[1]*width,box[2]*height)]
        guard !manifest.redactedRegions.contains(where:{overlaps(points,$0,width:width,height:height)}) else {throw RoomImageGeometryError.redactedEvidence}
        for step in try steps(record,manifest).reversed() {
            let v=step.values
            switch step.kind {
            case "crop":points=points.map{Vec2($0.x+v[0],$0.y+v[1])}
            case "resize":points=points.map{Vec2($0.x*step.width/v[0],$0.y*step.height/v[1])}
            case "rotate":
                points=points.map {p in
                    switch Int(v[0]) {
                    case 1:return Vec2(p.y,step.height-p.x)
                    case 2:return Vec2(step.width-p.x,step.height-p.y)
                    case 3:return Vec2(step.width-p.y,p.x)
                    default:return p
                    }
                }
            case "redact":guard !overlaps(points,v,width:step.width,height:step.height) else {throw RoomImageGeometryError.redactedEvidence}
            default:throw RoomImageGeometryError.invalidTransform
            }
        }
        let k=record.intrinsics
        let rays=points.map{Vec3(($0.x-k[2])/k[0],($0.y-k[5])/k[4],1)}
        guard rays.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else {throw RoomImageGeometryError.invalidCalibration}
        return ImageEvidenceRays(originalPixels:points,cameraRays:rays,hasRecordedAlignedDepth:record.depth != nil)
    }
}

public extension IntegratedAIState {
    /// Metadata for at most 32 selected local frames, saved in the existing encrypted AI sidecar.
    /// Native separately owns selected image/depth bytes, upload consent and their deletion.
    mutating func recordImageGeometry(_ record:RoomImageCaptureGeometry,manifest:RoomImageManifest,home:HomeModel,
        persist:(IntegratedAIState)throws->Void)throws {
        try RoomImageGeometry.validate(record,manifest:manifest,home:home)
        var candidate=self
        var records=candidate.imageGeometryRecords ?? []
        guard Set(records.map(\.imageID)).count==records.count else {throw RoomImageGeometryError.invalidCalibration}
        records.removeAll{$0.imageID==record.imageID};records.append(record)
        guard records.count<=32 else {throw SessionError.budget}
        candidate.imageGeometryRecords=records
        try persist(candidate);self=candidate
    }
    /// Deleting the companion does not delete pixels. Native must also remove image/depth bytes
    /// and any in-flight upload, and keep a concern only as explicitly retained review history.
    mutating func removeImageGeometry(imageID:String,persist:(IntegratedAIState)throws->Void)throws {
        var candidate=self
        candidate.imageGeometryRecords?.removeAll{$0.imageID==imageID}
        try persist(candidate);self=candidate
    }
}
