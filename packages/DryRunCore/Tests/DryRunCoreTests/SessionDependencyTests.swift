import Foundation
import Testing
@testable import DryRunCore

@Suite("Source-bound recorded access dependencies") struct SessionDependencyTests {
    let fixture=SessionFoodTests()
    @Test func storageUsesCommittedStockAndNeverClaimsRoomCausedExpiry()throws {
        var s=try fixture.session([fixture.food(2,expiry:fixture.date.addingTimeInterval(3600))])
        let before=try s.query(library:SimFixtures.library)
        let deps=try s.dependencyInspection(receipt:before,library:SimFixtures.library)
        let storage=try #require(deps.first{$0.kind=="recordedSupplyStorage"})
        #expect(storage.subjectIDs==["food"])
        #expect(storage.evidenceIDs==[before.contextDigest,"sp-kitchen"])
        #expect(storage.status.contains("Sole recorded location"))
        let expired=try fixture.advance(&s,to:60)
        let after=try s.dependencyInspection(receipt:expired,library:SimFixtures.library)
        #expect(after.contains{$0.kind=="recordedSupplyStorage" && $0.status.contains("access unavailable") && $0.status.contains("cause unproven")})
        #expect(throws:SessionError.stale){try s.dependencyInspection(receipt:before,library:SimFixtures.library)}
        var forged=expired;forged.inventory?.items[0].accessible=true
        #expect(throws:SessionError.stale){try s.dependencyInspection(receipt:forged,library:SimFixtures.library)}
    }
    @Test func carryingReplacesStorageAndLegacySourcesKeepOldInspection()throws {
        var s=try fixture.session([fixture.food()])
        let person=s.initial.household.people[0].id
        let carried=try s.commit(.init(id:"take",actor:"user",baseRevision:0,commands:[.init(kind:"takeSupply",target:"food",value:person)]),library:SimFixtures.library)
        let deps=try s.dependencyInspection(receipt:carried,library:SimFixtures.library)
        #expect(!deps.contains{$0.kind=="recordedSupplyStorage"})
        #expect(deps.contains{$0.kind=="recordedSupplyCarrier" && $0.evidenceIDs.contains(person)})
        let encoded=try DryRunJSON.encoder().encode(s)
        var json=try #require(JSONSerialization.jsonObject(with:encoded) as? [String:Any]);json.removeValue(forKey:"dependencyPolicy")
        let legacy=try DryRunJSON.decoder().decode(SimulationSession.self,from:JSONSerialization.data(withJSONObject:json))
        #expect(legacy.dependencyPolicy==nil)
        #expect(!(try legacy.dependencyInspection(receipt:legacy.query(library:SimFixtures.library),library:SimFixtures.library)).contains{$0.kind=="recordedSupplyCarrier"})
        json["dependencyPolicy"]="invented"
        #expect(throws:(any Error).self){try DryRunJSON.decoder().decode(SimulationSession.self,from:JSONSerialization.data(withJSONObject:json))}
    }
    @Test func unknownAndEmptyStockAreNotInventedAndStressUsesActualSource()throws {
        var item=fixture.food();item.usableQuantity = .unknown
        var s=try fixture.session([item])
        let finding=try PlanStressTester.execute(initial:s.initial,profileIDs:["evt.water-outage.well-pump-failure"],library:SimFixtures.library,inventory:s.inventory)
        #expect(finding.dependencies.contains{$0.kind=="recordedSupplyStorage" && $0.status.contains("Unknown quantities conditional") && $0.evidenceIDs.contains(finding.baseline.contextDigest)})
        let receipt=try s.query(library:SimFixtures.library)
        #expect(try s.executeTool(.init(kind:.inspectDependencies,baseRevision:0),library:SimFixtures.library).receipt==receipt)
        s=try fixture.session([fixture.food(0)])
        #expect(!(try s.executeTool(.init(kind:.inspectDependencies,baseRevision:0),library:SimFixtures.library).dependencies ?? []).contains{$0.kind=="recordedSupplyStorage"})
    }
    @Test func destinationReviewDoesNotInferActivationOrLeakLabels()throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"water-outage")
        input.household.transport.destinations=[.init(id:"site",kind:.publicShelter,label:"PRIVATE ADDRESS",conditionsConfirmed:.unknown)]
        let s=SimulationSession(id:"destination",initial:input)
        let result=try s.executeTool(.init(kind:.inspectDependencies,baseRevision:0),library:SimFixtures.library)
        let destination=try #require(result.dependencies?.first{$0.kind=="destinationConditions"})
        #expect(destination.subjectIDs==["site"])
        #expect(destination.status.contains("activation remain unknown"))
        #expect(!String(decoding:try DryRunJSON.encoder().encode(destination),as:UTF8.self).contains("PRIVATE ADDRESS"))
    }
}
