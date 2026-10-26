import Foundation
import Testing
@testable import DryRunCore

@Suite("Local image transform and calibration provenance") struct RoomImageGeometryTests {
    struct Fixture:Decodable {
        var manifest:RoomImageManifest;var geometry:RoomImageCaptureGeometry;var box:[Double]
        var expectedOriginalPixels:[[Double]];var expectedCameraRays:[[Double]]
    }
    func fixture()throws->Fixture {try DryRunJSON.decoder().decode(Fixture.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/image-geometry-v1.json")))}
    func home()->HomeModel {var home=SampleHomes.ranch;home.sourceCaptureFrameID="synthetic-capture-frame";return home}
    func rays(_ f:Fixture)throws->ImageEvidenceRays {try RoomImageGeometry.rays(for:f.box,manifest:f.manifest,record:f.geometry,home:home())}
    @Test func cropResizeRotationUsesOriginalIntrinsicsAndNeverMutatesHome()throws {
        let f=try fixture(),original=home(),saved=try DryRunJSON.encoder().encode(original)
        let result=try rays(f)
        #expect(result.originalPixels==f.expectedOriginalPixels.map{Vec2($0[0],$0[1])})
        for (ray,expected) in zip(result.cameraRays,f.expectedCameraRays) {
            #expect(abs(ray.x-expected[0])<1e-10);#expect(abs(ray.y-expected[1])<1e-10);#expect(ray.z==1)
        }
        #expect(!result.hasRecordedAlignedDepth)
        #expect(try DryRunJSON.encoder().encode(original)==saved)
        let restored=try DryRunJSON.decoder().decode(RoomImageCaptureGeometry.self,from:DryRunJSON.encoder().encode(f.geometry))
        #expect(restored==f.geometry)
        #expect(f.manifest.orientation=="right", "Metadata never adds another implicit rotation")
    }
    @Test func everyQuarterTurnPreservesAnalyticallySpecifiedOriginalCorners()throws {
        let expected=[[[200.0,150],[600,150],[600,450],[200,450]],[[200,450],[200,150],[600,150],[600,450]],[[600,450],[200,450],[200,150],[600,150]],[[600,150],[600,450],[200,450],[200,150]]]
        for quarter in 0..<4 {
            var f=try fixture();f.box=[0.25,0.25,0.75,0.75]
            f.manifest.transforms=[.init(kind:"rotate",values:[Double(quarter)])]
            f.manifest.width=quarter%2==0 ? 800:600;f.manifest.height=quarter%2==0 ? 600:800
            #expect(try rays(f).originalPixels==expected[quarter].map{Vec2($0[0],$0[1])})
        }
    }
    @Test func staleImageHomeFrameAndTimeCannotEstablishCalibration()throws {
        let base=try fixture()
        for change in 0..<6 {
            var f=base
            switch change {
            case 0:f.geometry.imageDigest=String(repeating:"b",count:64)
            case 1:f.geometry.imageID="another-image"
            case 2:f.geometry.homeID="another-home"
            case 3:f.geometry.homeRevision+=1
            case 4:f.geometry.captureFrameID="another-capture-frame"
            default:f.geometry.capturedAt=f.geometry.capturedAt.addingTimeInterval(1)
            }
            #expect(throws:RoomImageGeometryError.staleSource){try rays(f)}
        }
        var unregistered=home();unregistered.sourceCaptureFrameID=nil
        #expect(throws:RoomImageGeometryError.staleSource){try RoomImageGeometry.rays(for:base.box,manifest:base.manifest,record:base.geometry,home:unregistered)}
    }
    @Test func invalidCalibrationAndUnalignedDepthRemainUnavailable()throws {
        for change in 0..<5 {
            var f=try fixture()
            switch change {
            case 0:f.geometry.intrinsics[0]=0
            case 1:f.geometry.intrinsics[8]=0
            case 2:f.geometry.cameraToCapture[0] = -1 // Reflection is not a rigid camera rotation.
            case 3:f.geometry.cameraToCapture[5]=2
            default:f.geometry.intrinsics[0]=Double.leastNonzeroMagnitude
            }
            #expect(throws:RoomImageGeometryError.invalidCalibration){try rays(f)}
        }
        var f=try fixture()
        f.geometry.depth=AlignedImageDepth(cameraFrameID:f.geometry.cameraFrameID,capturedAt:f.geometry.capturedAt,digest:String(repeating:"b",count:64),width:200,height:150,referenceWidth:800,referenceHeight:600,source:"sceneDepth")
        #expect(try rays(f).hasRecordedAlignedDepth, "Metadata only: no depth sampling or world projection is claimed")
        for change in 0..<4 {
            var invalid=f
            switch change {
            case 0:invalid.geometry.depth!.cameraFrameID="different-frame"
            case 1:invalid.geometry.depth!.capturedAt=f.geometry.capturedAt.addingTimeInterval(1)
            case 2:invalid.geometry.depth!.referenceWidth=100
            default:invalid.geometry.depth!.alignment="unregistered"
            }
            #expect(throws:RoomImageGeometryError.invalidCalibration){try rays(invalid)}
        }
    }
    @Test func redactionsAndInconsistentTransformsKeepEvidenceInSubmittedImage()throws {
        var f=try fixture();f.manifest.calibration="none"
        #expect(throws:RoomImageGeometryError.imageSpaceOnly){try rays(f)}
        f=try fixture();f.manifest.redactedRegions=[[0.3,0.4,0.5,0.6]]
        #expect(throws:RoomImageGeometryError.redactedEvidence){try rays(f)}
        f=try fixture();f.manifest.transforms.insert(.init(kind:"redact",values:[0.25,0.25,0.75,0.75]),at:1)
        #expect(throws:RoomImageGeometryError.redactedEvidence){try rays(f)}
        for transform in [RoomImageManifest.ImageTransform(kind:"crop",values:[-1,0,400,200]),.init(kind:"resize",values:[200]),.init(kind:"rotate",values:[90]),.init(kind:"crop",values:[0,0,801,600])] {
            f=try fixture();f.manifest.transforms=[transform]
            #expect(throws:RoomImageGeometryError.invalidTransform){try rays(f)}
        }
        f=try fixture();f.manifest.width+=1
        #expect(throws:RoomImageGeometryError.invalidTransform){try rays(f)}
        f=try fixture();f.box=[0,0,1,2]
        #expect(throws:RoomImageGeometryError.invalidBox){try rays(f)}
    }
    @Test func selectedFrameMetadataIsBoundedAndTransactionalAcrossRestoreAndDelete()throws {
        var local=IntegratedAIState();let f=try fixture(),before=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.persistence){try local.recordImageGeometry(f.geometry,manifest:f.manifest,home:home(),persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(local)==before)
        for index in 0..<32 {
            var record=f.geometry,manifest=f.manifest
            record.imageID="selected-\(index)";manifest.id=record.imageID
            try local.recordImageGeometry(record,manifest:manifest,home:home(),persist:{_ in})
        }
        let full=try DryRunJSON.encoder().encode(local)
        #expect(throws:SessionError.budget){try local.recordImageGeometry(f.geometry,manifest:f.manifest,home:home(),persist:{_ in})}
        #expect(try DryRunJSON.encoder().encode(local)==full)
        local=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:full)
        #expect(local.imageGeometryRecords?.count==32)
        #expect(throws:SessionError.persistence){try local.removeImageGeometry(imageID:"selected-0",persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(local)==full)
        try local.removeImageGeometry(imageID:"selected-0",persist:{_ in})
        #expect(local.imageGeometryRecords?.count==31)
        try local.recordImageGeometry(f.geometry,manifest:f.manifest,home:home(),persist:{_ in})
        #expect(local.imageGeometryRecords?.count==32)
        // Existing frames can be refreshed without exhausting the selected-frame budget.
        try local.recordImageGeometry(f.geometry,manifest:f.manifest,home:home(),persist:{_ in})
        #expect(local.imageGeometryRecords?.count==32)
        struct Historical:Decodable {var begun:IntegratedAIState}
        let old=try DryRunJSON.decoder().decode(Historical.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/practice-capture.json")))
        #expect(old.begun.imageGeometryRecords==nil)
    }

}
