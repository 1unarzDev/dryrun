import Foundation
import Testing
@testable import DryRunCore

@Suite("Controlled supply relocation retests") struct StressRetestPlanTests {
    let fixture=SessionInventoryTests()
    let profiles=["evt.home-fire.alarm","evt.home-fire.fire-origin"]
    @Test func sameIncidentExecutesConfirmedUserPreparationWithoutChangingRealFacts()throws {
        let s=try fixture.session("home-fire"),person=s.initial.household.people[0].id
        let original=try DryRunJSON.encoder().encode(s)
        let plan=StressRetestPlan(commands:[.init(kind:"takeSupply",target:"water",value:person),.init(kind:"moveTo",target:person,value:"sp-living"),.init(kind:"transferSupply",target:"water",value:"sp-living")])
        let result=try PlanStressTester.execute(initial:s.initial,profileIDs:profiles,library:SimFixtures.library,inventory:s.inventory,retestPlan:plan)
        let retest=try #require(result.controlledRetest),comparison=try #require(result.comparison)
        #expect(result.baseline.inventory?.items[0].accessible==false)
        #expect(retest.inventory?.items[0].accessible==true)
        #expect(retest.inventory?.items[0].locationID=="sp-living")
        #expect(retest.inventory?.items[0].remaining==5)
        #expect(result.retestPlan?.commands.count==3)
        #expect(comparison.commonHorizonReached)
        #expect(comparison.remainingUnknownIDs==retest.snapshot.unknowns.sorted())
        #expect(comparison.remainingRequirementIDs==retest.snapshot.unmetRequirements.sorted())
        #expect(try DryRunJSON.encoder().encode(s)==original)
        let replay=try PlanStressTester.execute(initial:s.initial,profileIDs:profiles,library:SimFixtures.library,inventory:s.inventory,retestPlan:result.retestPlan)
        #expect(try DryRunJSON.encoder().encode(replay)==DryRunJSON.encoder().encode(result))
    }
    @Test func invalidPreparationsFailInsteadOfSilentlyChangingTheComparison()throws {
        let s=try fixture.session("home-fire")
        let invalid:[[SessionCommand]]=[[],[.init(kind:"takeSupply",target:"water",value:s.initial.household.people[0].id,minute:10)],[.init(kind:"advance",minute:60)],[.init(kind:"schedule",target:profiles[0],minute:0)],[.init(kind:"takeSupply",target:"invented",value:s.initial.household.people[0].id)],[.init(kind:"transferSupply",target:"water",value:"sp-living")],Array(repeating:.init(kind:"requestDecision"),count:9)]
        var badVersion=StressRetestPlan(commands:[.init(kind:"useStoredWater",value:"essential")]);badVersion.version="invented"
        #expect(throws:SessionError.invalidCommand){try PlanStressTester.execute(initial:s.initial,profileIDs:profiles,library:SimFixtures.library,inventory:s.inventory,retestPlan:badVersion)}
        for commands in invalid {
            #expect(throws:SessionError.invalidCommand){try PlanStressTester.execute(initial:s.initial,profileIDs:profiles,library:SimFixtures.library,inventory:s.inventory,retestPlan:.init(commands:commands))}
        }
    }
    @Test func betterDurationDoesNotClaimCompleteResolutionAndLegacyMetadataRemainsAbsent()throws {
        let input=SimFixtures.input(SampleHouseholds.oak,"water-outage")
        let result=try PlanStressTester.execute(initial:input,profileIDs:["evt.water-outage.well-pump-failure"],library:SimFixtures.library,intervention:.init(actionID:"act.water.store-3day"))
        #expect(result.retestIntervention?.actionID=="act.water.store-3day")
        #expect(result.comparison?.remainingRequirementIDs.contains("req.water")==true)
        let legacy=try PlanStressTester.execute(initial:input,profileIDs:["evt.water-outage.well-pump-failure"],library:SimFixtures.library,intervention:.init(actionID:"act.water.store-3day"),dependencyPolicy:nil)
        #expect(legacy.comparison==nil);#expect(legacy.retestIntervention==nil)
    }
}
