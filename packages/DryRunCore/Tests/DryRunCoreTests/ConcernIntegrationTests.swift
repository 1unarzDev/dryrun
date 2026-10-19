import Foundation
import Testing
@testable import DryRunCore

@Suite("Home review to preparation and hypothetical exercise") struct ConcernIntegrationTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    var rubric:RubricDefinition {get throws {try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))}}
    func sample()->(RoomImageManifest,HomeConcernProposal) {
        let manifest=RoomImageManifest(id:"image",homeRevision:SimFixtures.home.revision,roomID:"sp-living",digest:String(repeating:"a",count:64),capturedAt:date,width:640,height:480,orientation:"up",calibration:"none",transforms:[],redactedRegions:[])
        return (manifest,HomeConcernProposal(id:"concern",homeRevision:manifest.homeRevision,imageID:manifest.id,imageDigest:manifest.digest,box:[0.1,0.2,0.4,0.5],roomID:manifest.roomID,category:"possibleObstruction",visibleEvidence:"Object appears near an opening",unknowns:["Full clearance and opening identity need manual review"],actionID:"prep.clearExits",scenarioIDs:["home-fire"]))
    }
    func review(_ local:inout IntegratedAIState,decision:ConcernDecision,proposal:HomeConcernProposal?=nil,manifest:RoomImageManifest?=nil)throws {
        let fixture=sample()
        try local.reviewConcern(proposal ?? fixture.1,decision:decision,manifest:manifest ?? fixture.0,home:SimFixtures.home,household:SampleHouseholds.oak,rubric:rubric,library:SimFixtures.library,at:date)
    }
    @Test func confirmedCreatesOneLinkedTaskButNoHouseholdFactsOrPoints()throws {
        var local=IntegratedAIState();try review(&local,decision:.confirmed)
        let task=try #require(local.concernTasks(currentHome:SimFixtures.home).first)
        #expect(task.actionID=="prep.clearExits");#expect(task.roomID=="sp-living")
        #expect(!task.earnsScoreByItself);#expect(task.scenarioIDs==["home-fire"])
        var duplicate=sample().1;duplicate.id="another-model-id"
        #expect(throws:SessionError.duplicate){try review(&local,decision:.confirmed,proposal:duplicate)}
        #expect(local.concernTasks(currentHome:SimFixtures.home).count==1)
        #expect(local.inventory.items.isEmpty);#expect(local.scorecards.isEmpty)
        var changed=SimFixtures.home;changed.spaces[0].polygon[0].x+=0.1
        #expect(local.concernTasks(currentHome:changed).isEmpty)
        try review(&local,decision:.dismissed)
        #expect(local.concernTasks(currentHome:SimFixtures.home).isEmpty)
        #expect(!local.concerns.shouldOffer(sample().1))
    }
    @Test func uncertainNeedsExplicitPermissionAndManualOpeningIdentity()throws {
        var local=IntegratedAIState();try review(&local,decision:.uncertain)
        #expect(local.concernTasks(currentHome:SimFixtures.home).isEmpty)
        #expect(throws:SessionError.invalidCommand){try local.concernExerciseSeed(concernID:"concern",scenarioID:"home-fire",selectedPortalIDs:["pt-front"],allowHypothetical:false,home:SimFixtures.home)}
        #expect(throws:SessionError.invalidCommand){try local.concernExerciseSeed(concernID:"concern",scenarioID:"home-fire",selectedPortalIDs:["made-up-opening"],allowHypothetical:true,home:SimFixtures.home)}
        #expect(throws:SessionError.invalidCommand){try local.concernExerciseSeed(concernID:"concern",scenarioID:"tornado",selectedPortalIDs:["pt-front"],allowHypothetical:true,home:SimFixtures.home)}
        let portal=try #require(SimFixtures.home.portals.first{$0.sideA == .space("sp-living") && $0.sideB == .exterior || $0.sideB == .space("sp-living") && $0.sideA == .exterior})
        let seed=try local.concernExerciseSeed(concernID:"concern",scenarioID:"home-fire",selectedPortalIDs:[portal.id],allowHypothetical:true,home:SimFixtures.home)
        var input=SimFixtures.input(SampleHouseholds.oak,"home-fire");input.spatialOptions = .init(startingSpaceIDs:["p-oak-1":"sp-living"])
        var baseline=try SimulationSession.initialize(id:"baseline",initial:input,library:SimFixtures.library)
        var exercise=try SimulationSession.initialize(id:"concern",initial:input,library:SimFixtures.library,concernSeed:seed)
        let commands=[SessionCommand(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)]
        let a=try baseline.commit(.init(id:"alarm",actor:"director",baseRevision:0,commands:commands),library:SimFixtures.library)
        let b=try exercise.commit(.init(id:"alarm",actor:"director",baseRevision:0,commands:commands),library:SimFixtures.library)
        #expect(a.routes != b.routes)
        #expect(b.routes.allSatisfy{!($0.primary?.portalSequence.contains(portal.id) ?? false)})
        #expect(exercise.initial==baseline.initial)
        #expect(b.snapshot.spatialState?.affectedPortalIDs.contains(portal.id)==true)
        var changed=input;changed.home!.spaces[0].polygon[0].x+=0.1
        #expect(throws:SessionError.invalidCommand){try SimulationSession.initialize(id:"stale-home",initial:changed,library:SimFixtures.library,concernSeed:seed)}
        #expect(local.concerns.reviewed[0].decision == .uncertain)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(exercise))
        #expect(try restored.query(library:SimFixtures.library)==b)
    }
    @Test func controlledConcernStressPreservesAssumptionsButCannotAlterScorePredicates()throws {
        var local=IntegratedAIState();try review(&local,decision:.uncertain)
        let portal=try #require(SimFixtures.home.portals.first{$0.sideA == .space("sp-living") && $0.sideB == .exterior || $0.sideB == .space("sp-living") && $0.sideA == .exterior})
        let seed=try local.concernExerciseSeed(concernID:"concern",scenarioID:"home-fire",selectedPortalIDs:[portal.id],allowHypothetical:true,home:SimFixtures.home)
        let input=SimFixtures.input(SampleHouseholds.oak,"home-fire")
        let finding=try PlanStressTester.execute(initial:input,profileIDs:["evt.home-fire.alarm"],library:SimFixtures.library,intervention:.init(actionID:"act.water.store-3day"),concernSeed:seed)
        #expect(finding.sourceConcernDigest != nil)
        #expect(finding.id.contains("|concern|"))
        #expect(finding.baseline.routes.allSatisfy{!($0.primary?.portalSequence.contains(portal.id) ?? false)})
        #expect(finding.controlledRetest?.routes.allSatisfy{!($0.primary?.portalSequence.contains(portal.id) ?? false)}==true)
        #expect(finding.baseline.snapshot.spatialState?.affectedPortalIDs.contains(portal.id)==true)
        let without=try HouseholdAssessment.assess(household:input.household,home:input.home,inventory:nil,at:date)
        let with=try HouseholdAssessment.assess(household:input.household,home:input.home,inventory:nil,stressFindings:[finding],at:date)
        #expect(try DryRunJSON.encoder().encode(without)==DryRunJSON.encoder().encode(with))
        // Deliberate permission mutation: even a reported shared geometry ID must not let
        // a concern-scoped trace enter the scored envelope. This is not a new geometry fixture.
        var adversarial=finding;adversarial.criterionID="escape"
        adversarial.baseline.routes[0].sharedChokepoints=[portal.id]
        let protected=try HouseholdAssessment.assess(household:input.household,home:input.home,inventory:nil,stressFindings:[adversarial],at:date)
        #expect(try DryRunJSON.encoder().encode(protected)==DryRunJSON.encoder().encode(without))
        adversarial.sourceConcernDigest=nil
        let envelopeControl=try HouseholdAssessment.assess(household:input.household,home:input.home,inventory:nil,stressFindings:[adversarial],at:date)
        #expect(try DryRunJSON.encoder().encode(envelopeControl) != DryRunJSON.encoder().encode(without))
        let session=try SimulationSession.initialize(id:"concern-tool",initial:input,library:SimFixtures.library,concernSeed:seed)
        let original=try session.query(library:SimFixtures.library)
        let tool=try session.executeTool(.init(kind:.runCounterfactual,baseRevision:0,profileIDs:["evt.home-fire.alarm"]),library:SimFixtures.library)
        #expect(tool.counterfactual?.sourceConcernDigest==finding.sourceConcernDigest)
        #expect(try session.query(library:SimFixtures.library)==original)
        #expect(input==session.initial)
    }
    @Test func staleUnknownTaskRedactionAndPersistenceFailWithoutPublishing()throws {
        var local=IntegratedAIState();let original=try DryRunJSON.encoder().encode(local)
        var bad=sample().1;bad.actionID="model-invented-action"
        #expect(throws:SessionError.invalidCommand){try review(&local,decision:.confirmed,proposal:bad)}
        var manifest=sample().0;manifest.redactedRegions=[[0,0,1,1]]
        #expect(throws:SessionError.invalidCommand){try review(&local,decision:.confirmed,manifest:manifest)}
        manifest=sample().0;manifest.roomID="not-in-home"
        #expect(throws:SessionError.invalidCommand){try review(&local,decision:.confirmed,manifest:manifest)}
        manifest=sample().0;manifest.digest="bad"
        #expect(throws:SessionError.invalidCommand){try review(&local,decision:.confirmed,manifest:manifest)}
        let fixture=sample()
        #expect(throws:SessionError.persistence){try local.reviewConcern(fixture.1,decision:.confirmed,manifest:fixture.0,home:SimFixtures.home,household:SampleHouseholds.oak,rubric:rubric,library:SimFixtures.library,at:date,persist:{_ in throw SessionError.persistence})}
        #expect(try DryRunJSON.encoder().encode(local)==original)
    }
}
