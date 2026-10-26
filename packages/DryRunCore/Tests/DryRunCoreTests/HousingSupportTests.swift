import Foundation
import Testing
@testable import DryRunCore

@Suite("Housing, site hazards and shared model representations") struct HousingSupportTests {
    let at=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    @Test func apartmentComplexHasActualExteriorAndStairDependencies() {
        let h=SampleHomes.apartmentComplex
        #expect(!HomeValidator.validate(h).contains{$0.severity == .blocking})
        let request=RouteRequest(startSpaceID:"sp-bed1")
        let route=EgressPlanner().plan(request,in:h)
        #expect(route.primary != nil,"\(String(describing:route.noRouteReason)): \(route.exclusions)")
        #expect(route.primary?.exitPortalID == "pt-building-exit")
        #expect(route.primary?.connectorSequence.count == 2)
        #expect(route.alternative == nil,"Shared unit entry and stairs are single points of failure")
        var blocked=request;blocked.exclusions.blockedConnectorIDs=["cn-common-upper-stairs"]
        #expect(EgressPlanner().plan(blocked,in:h).primary == nil)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID:"sp-bed1",mobility:.wheelchair),in:h).primary == nil)
        #expect(EgressPlanner().plan(request,in:SampleHomes.apartment).primary == nil)
        var missing=h;missing.connectors.removeLast()
        #expect(EgressPlanner().plan(request,in:missing).primary == nil)
        var elevator=h;elevator.connectors[0].kind = .elevator
        #expect(EgressPlanner().plan(request,in:elevator).primary == nil)
    }
    @Test func manufacturedClosetNeverBecomesTornadoShelterAndThresholdsMatter() {
        let h=SampleHomes.manufactured
        #expect(!ShelterSuitability.isConfirmed(roomID:"sp-closet",in:h))
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID:"sp-bed1"),in:h).primary != nil)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID:"sp-bed1",mobility:.wheelchair),in:h).primary == nil)
        var household=SampleHouseholds.oak;household.housing.homeType = .manufacturedHome
        #expect(HomeSceneContext(SampleHomes.ranch,household:household).rooms.allSatisfy{$0.confirmedShelter == false})
        #expect(HouseholdContextSnapshot(household,at:at).housing?.homeType == .manufacturedHome)
        #expect(HouseholdContextSnapshot(household,at:at).housing?.heatingNeedsElectricity == household.housing.heatingNeedsElectricity)
    }
    @Test func manufacturedHousingOverridesLegacyShelterMarkersInScoreAndContext() throws {
        var h=SampleHouseholds.oak;h.housing.homeType = .manufacturedHome
        let assessments=try HouseholdAssessment.assess(household:h,home:SampleHomes.ranch,inventory:nil,at:at)
        #expect(assessments.first{$0.criterionID=="shelter"}?.predicates["suitable"]==false)
        #expect(assessments.first{$0.criterionID=="shelter"}?.predicates["reachable"]==nil)
        // /7 removes unsupported generic-reconnection credit for an offline contact
        // copy; the manufactured-home suitability predicates remain unchanged.
        #expect(assessments.allSatisfy{$0.assessmentVersion==HouseholdAssessment.version})
        #expect(assessments.first{$0.criterionID=="contact"}?.predicates["offlineAccess"]==nil)
    }
    @Test func capturedWindowsRemainProposalsButExcludeWindowlessShelter() throws {
        var home=try ScanImport.importCapture(GeometryTests.capture,homeID:"scan-window-fixture").home
        let window=try #require(home.portals.first{$0.kind == .window})
        #expect(window.verification == .proposed);#expect(window.operable.confirmedValue==nil)
        let roomID=try #require([window.sideA,window.sideB].compactMap{if case .space(let id)=$0{return id};return nil}.first)
        let index=try #require(home.spaces.firstIndex{$0.id==roomID})
        home.floors[0].exteriorGrade = .ground;home.spaces[index].geometryNeedsReview=false
        home.spaces[index].interiorNoWindowsConfirmed = .confirmed(true)
        #expect(!ShelterSuitability.canConfirm(roomID:roomID,in:home))
        #expect(HomeSceneContext(home).portals.contains{$0.id==window.id && $0.kind=="window"})
    }
    @Test func dwellingEditsUpdateHomeContextAndStagedSiteEditsLeaveRevisionToTransactionOwner() throws {
        let before=SampleHouseholds.oak;var updated=before;updated.housing.homeType = .manufacturedHome
        let home=try #require(HouseholdEditing.homeAfterRemovingResidents(previous:before,updated:updated,home:SampleHomes.ranch))
        #expect(home.revision==SampleHomes.ranch.revision+1);#expect(home.dwellingType == .manufacturedHome)
        #expect(!ShelterSuitability.isConfirmed(roomID:"sp-closet",in:home))
        #expect(home.spaces==SampleHomes.ranch.spaces);#expect(home.portals==SampleHomes.ranch.portals)
        SiteHazardEditing.stage(profile(),in:&updated)
        #expect(updated.revision==before.revision)
        #expect(updated.siteHazards?.locationBinding==SiteHazardBinding.of(updated))
        #expect(HouseholdContextSnapshot(updated,at:at).site?.elevationRecorded==true)
    }
    @Test func sameGeometryProducesTwoAndThreeDimensionalArtifacts() throws {
        let dir=SimFixtures.repoRoot.appendingPathComponent("fixtures/homes/representations")
        let write=ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1"
        if write {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}
        for h in SampleHomes.all {
            let obj=HomeModelExport.obj(h)
            for room in h.spaces {#expect(obj.contains("o \(room.id)\n"))}
            for portal in h.portals {#expect(obj.contains("o \(portal.id)_\(portal.kind.rawValue)"))}
            for floor in h.floors {
                let svg=try #require(AIPlanDiagram.svg(home:h,floorID:floor.id))
                for a in h.annotations where a.floorID==floor.id && a.position != nil {#expect(svg.contains(a.id));#expect(obj.contains(a.id))}
                let path=dir.appendingPathComponent("\(h.id)-\(floor.id).svg")
                if write {try Data(svg.utf8).write(to:path)}
                #expect(try String(contentsOf:path,encoding:.utf8)==svg)
            }
            let path=dir.appendingPathComponent("\(h.id).obj")
            if write {try Data(obj.utf8).write(to:path)}
            #expect(try String(contentsOf:path,encoding:.utf8)==obj)
        }
        let f=Floor(id:"rotated",level:1,label:"Upper",elevationMeters:2.8,toCommon:Transform2D(rotationRadians:.pi/2,translation:Vec2(10,20)))
        let p=HomeModelExport.point3D(Vec2(2,3),floor:f)
        #expect(abs(p.x-7)<1e-10);#expect(p.y==2.8);#expect(abs(p.z+22)<1e-10)
    }
    func profile()->SiteHazardProfile {
        let source=SiteHazardSource(id:"official-site-fixture",authority:.official,publisher:"Synthetic official adapter",url:"https://example.invalid/hazard",jurisdictionID:"48143",retrievedAt:at.addingTimeInterval(-3600),validUntil:at.addingTimeInterval(3600),reviewed:true)
        return SiteHazardProfile(jurisdictionID:"48143",sources:[source],elevation:SiteElevation(meters:100,uncertaintyMeters:0.2,verticalDatum:"NAVD88",surface:.finishedFloor,sourceID:source.id),floodLevel:SiteFloodLevel(meters:98,uncertaintyMeters:0.2,verticalDatum:"NAVD88",sourceID:source.id),wildfire:SiteWildfireEvidence(rating:"high",scale:.community,sourceID:source.id),hurricane:HurricaneEvacuationPlan(zone:"PRIVATE-ZONE",routeIDs:["PRIVATE-ROUTE"],sourceID:source.id,instructions:"PRIVATE-DIRECTIONS"))
    }
    @Test func locationEvidenceUsesCompatibleDatumUncertaintyFreshnessAndScale() {
        var p=profile()
        var c=SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at)
        #expect(c.elevationRecorded);#expect(c.floodComparison=="aboveDesignLevel")
        #expect(c.wildfireRating=="high");#expect(c.wildfireScale=="community")
        #expect(c.hurricanePlan=="recordedOfficialPlanningRoute")
        p.elevation?.surface = .terrain
        #expect(SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at).floodComparison=="unknown")
        p.elevation?.surface = .finishedFloor;p.floodLevel?.verticalDatum="unknown"
        #expect(SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at).floodComparison=="unknown")
        p.floodLevel?.verticalDatum="NAVD88";p.elevation?.uncertaintyMeters=3
        #expect(SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at).floodComparison=="overlappingUncertainty")
        p.elevation?.verticalDatum="unknown";p.floodLevel?.verticalDatum="unknown"
        #expect(SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at).floodComparison=="unknown")
        p.sources[0].authority = .household
        c=SiteHazardContext(p,jurisdictionID:p.jurisdictionID,at:at)
        #expect(!c.elevationRecorded);#expect(c.sourceIDs.isEmpty)
        #expect(SiteHazardContext(profile(),jurisdictionID:"other",at:at).sourceIDs.isEmpty)
        #expect(SiteHazardContext(profile(),jurisdictionID:"48143",at:at.addingTimeInterval(7200)).sourceIDs.isEmpty)
        p=profile();p.sources.append(p.sources[0]);#expect(SiteHazardContext(p,jurisdictionID:"48143",at:at).sourceIDs.isEmpty)
    }
    @Test func siteEditPersistsLocallyAndOnlyMinimizedEvidenceGoesToGemini() throws {
        let original=SampleHouseholds.oak
        let h=SiteHazardEditing.replace(profile(),in:original,at:at)
        #expect(h.revision==original.revision+1)
        let data=try DryRunJSON.encoder().encode(h)
        #expect(try DryRunJSON.decoder().decode(HouseholdProfile.self,from:data)==h)
        let context=HouseholdContextSnapshot(h,at:at)
        let cloud=String(decoding:try DryRunJSON.encoder().encode(context),as:UTF8.self)
        #expect(!cloud.contains("PRIVATE-"));#expect(!cloud.contains("example.invalid"));#expect(!cloud.contains("NAVD88"))
        #expect(context.evidence.contains{$0.id=="official-site-fixture" && $0.origin=="officialSource"})
        #expect(original.siteHazards==nil)
        var moved=h;moved.privateLocation=PrivateLocation(addressLine:"Different synthetic home")
        #expect(HouseholdContextSnapshot(moved,at:at).site?.sourceIDs.isEmpty==true)
        moved=h;moved.homeID="different-home"
        #expect(HouseholdContextSnapshot(moved,at:at).site?.sourceIDs.isEmpty==true)
        #expect(SiteHazardEditing.replace(nil,in:h,at:at).siteHazards==nil)
    }
    @Test func markerEditsAreValidatedLocatedAndDoNotConfirmEquipmentReadiness() throws {
        let home=SampleHomes.ranch
        let marked=try HomeSafetyMarkers.place(id:"my-breaker",kind:.utilityShutoffElectric,roomID:"sp-living",position:Vec2(6,1),label:"PRIVATE-PANEL",note:"PRIVATE-NOTE",verified:true,in:home)
        #expect(marked.revision==home.revision+1)
        let cloud=HomeSceneContext(marked)
        let marker=try #require(cloud.objects.first{$0.id=="my-breaker"})
        #expect(marker.position==Vec2(6,1));#expect(marker.floorID=="fl-ground");#expect(marker.verification=="verified")
        #expect(!String(decoding:try DryRunJSON.encoder().encode(cloud),as:UTF8.self).contains("PRIVATE-"))
        #expect(throws:SessionError.self){try HomeSafetyMarkers.place(id:"bad",kind:.fireExtinguisher,roomID:"sp-living",position:Vec2(50,50),verified:true,in:home)}
        let restored=try DryRunJSON.decoder().decode(HomeModel.self,from:DryRunJSON.encoder().encode(marked))
        #expect(restored==marked)
        #expect(home.annotations.count+1==marked.annotations.count)
        #expect(cloud.objects.contains{$0.kind=="fireExtinguisher"})
        #expect(cloud.objects.contains{$0.kind=="tornadoShelterCandidate"})
    }
}
