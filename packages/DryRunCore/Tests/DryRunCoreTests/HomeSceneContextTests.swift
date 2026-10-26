import Foundation
import Testing
@testable import DryRunCore

@Suite("Minimized safety-relevant home scene") struct HomeSceneContextTests {
    @Test func recordedSafetyFactsExplainHostSuitabilityWithoutOverridingIt()throws {
        var home=SampleHomes.ranch
        home.floors[0].exteriorGrade = .ground
        home.portals[0].emergencyEscapePersonIDs=["resident-1"]
        let original=HomeSceneContext(home)
        #expect(original.schemaVersion=="dryrun.home-scene/2")
        #expect(original.homeSource==home.source)
        #expect(original.floors[0].level==home.floors[0].level)
        #expect(original.floors[0].exteriorGrade == .ground)
        #expect(original.portals[0].emergencyEscapePersonIDs==["resident-1"])
        let closet=try #require(home.spaces.firstIndex{$0.id=="sp-closet"})
        #expect(original.rooms[closet].confirmedShelter==true)
        home.spaces[closet].geometryNeedsReview=true
        let revised=HomeSceneContext(home)
        #expect(revised.rooms[closet].confirmed==true, "Room-use confirmation cannot imply reviewed geometry")
        #expect(revised.rooms[closet].geometryNeedsReview==true)
        #expect(revised.rooms[closet].interiorNoWindowsConfirmed?.confirmedValue==true, "Retain the actual answer")
        #expect(revised.rooms[closet].confirmedShelter==false, "Current host rules still reject stale geometry")
        home.floors[0].exteriorGrade=nil
        #expect(HomeSceneContext(home).floors[0].exteriorGrade == .unknown, "No guessed ground grade in cloud context")
    }
    @Test func contextRetainsEvidenceButRemovesPrivateLabelsNotesAndOriginalScan()throws {
        var home=SampleHomes.ranch
        home.label="PRIVATE-HOME-CANARY";home.floors[0].label="PRIVATE-FLOOR-CANARY"
        home.spaces[0].label="PRIVATE-ROOM-CANARY";home.spaces[0].sourceScanRoomID="PRIVATE-SCAN-CANARY"
        home.portals[0].note="PRIVATE-PORTAL-CANARY";home.annotations[0].label="PRIVATE-OBJECT-CANARY";home.annotations[0].note="PRIVATE-NOTE-CANARY"
        home.spaces[0].higherRefugeConfirmed = .confirmed(false)
        let context=HomeSceneContext(home),encoded=try DryRunJSON.encoder().encode(context)
        #expect(!String(decoding:encoded,as:UTF8.self).contains("PRIVATE-"))
        #expect(context.rooms[0].higherRefugeConfirmed?.confirmedValue==false)
        #expect(context.rooms[0].higherRefugeConfirmed?.origin == .userConfirmed)
        let restored=try DryRunJSON.decoder().decode(HomeSceneContext.self,from:encoded)
        #expect(try DryRunJSON.encoder().encode(restored)==encoded)
    }
    @Test func historicalSceneDecodesWithoutInventingNewSafetyEvidence()throws {
        let fixture=try Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/integrated-pipeline-policy.json"))
        struct Pipeline:Decodable {struct Output:Decodable {struct Context:Decodable {var scene:HomeSceneContext?};var context:Context};var outputs:[Output]}
        let context=try #require(try DryRunJSON.decoder().decode(Pipeline.self,from:fixture).outputs.first?.context.scene)
        #expect(context.schemaVersion=="dryrun.home-scene/1")
        #expect(context.homeSource==nil)
        #expect(context.floors.allSatisfy{$0.level==nil && $0.exteriorGrade==nil})
        #expect(context.rooms.allSatisfy{$0.geometryNeedsReview==nil && $0.confirmedShelter==nil})
        #expect(try DryRunJSON.decoder().decode(HomeSceneContext.self,from:DryRunJSON.encoder().encode(context)).schemaVersion==context.schemaVersion)
    }
}
