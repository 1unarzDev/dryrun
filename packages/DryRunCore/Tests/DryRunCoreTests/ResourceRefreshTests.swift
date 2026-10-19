import Foundation
import Testing
@testable import DryRunCore

@Suite("Relevant resource refresh and debounce") struct ResourceRefreshTests {
    let date=Date(timeIntervalSince1970:1792368000)
    func task()->PreparationTaskProposal {.init(id:"water-task",actionID:"prep.water",criterionID:"water",subjectID:"household",why:"Water gap",evidenceIDs:["record"],completionPredicates:["quantity","accessible"],editor:"supplies",dependencyIDs:["supplies.water"],priority:1)}
    func key(usable:Double=2,unknown:Bool=false,task:PreparationTaskProposal?=nil,dependencies:[ResourceStrategyDependency]=[])throws->ResourceStrategyKey {
        try .normalized(gaps:[SupplyGap(category:"water",required:12,confirmedUsable:usable,deficit:unknown ? nil:max(0,12-usable),unit:"liter",unknown:unknown,sourceIDs:["S26"])],tasks:[task ?? self.task()],transport:"noCar",limitedBudget:true,regionID:"outside-source-pack",dependencies:dependencies)
    }
    func plan(taskID:String="water-task",expansion:Int=1,travel:String="walking")->ResourceSearchPlan {
        .init(id:"water-plan",taskID:taskID,dependencyIDs:["supplies.water"],hazardIDs:["water-outage"],category:"grocery",purpose:"Prepare for the confirmed water gap",mandatoryCapabilities:[],unknowns:["Stock"],travelMode:travel,maximumDistanceKm:5,expansionLimit:expansion,requiredEvidence:["Actual location"],cloudReturnPolicy:"local_only")
    }
    @Test func quantitiesUnknownsAndExplicitDependenciesInvalidateWhileWordingDoesNot()throws {
        let a=try key(),b=try key(usable:3),c=try key(unknown:true)
        #expect(a != b);#expect(a != c)
        var wording=task();wording.why="Same accepted need, in another language";wording.evidenceIDs=["record","new-explanation"]
        wording.completionPredicates.reverse();wording.dependencyIDs += wording.dependencyIDs
        #expect(try key(task:wording)==a)
        #expect(try key(dependencies:[.init(id:"transport.arrangement",state:"unknown")]) != key(dependencies:[.init(id:"transport.arrangement",state:"confirmed")]))
        var prerequisite=task();prerequisite.dependencyIDs.append("device.documentedRequirement")
        #expect(try key(task:prerequisite) != a)
        let encoded=String(decoding:try DryRunJSON.encoder().encode(a),as:UTF8.self)
        #expect(!encoded.contains("Same accepted need"));#expect(!encoded.contains("record"))
    }
    @Test func equivalentGapAndTaskOrderingDeduplicateAndLegacyKeysDecode()throws {
        let gap=SupplyGap(category:"water",required:12,confirmedUsable:2,deficit:10,unit:"liter",unknown:false,sourceIDs:["S26","S26"])
        let a=try ResourceStrategyKey.normalized(gaps:[gap,gap],tasks:[task()],transport:"noCar",limitedBudget:true,regionID:"outside-source-pack")
        #expect(try a==key())
        let old=Data(#"{"gapCategories":["water"],"transport":"walking","limitedBudget":true,"regionID":"outside-source-pack"}"#.utf8)
        let legacy=try DryRunJSON.decoder().decode(ResourceStrategyKey.self,from:old)
        #expect(legacy.normalizedInputDigest==nil);#expect(legacy.relatedTaskIDs==nil)
        var invalid=gap;invalid.required = .infinity
        #expect(throws:SessionError.invalidCommand){try ResourceStrategyKey.normalized(gaps:[invalid],tasks:[],transport:"noCar",limitedBudget:true,regionID:"outside")}
    }
    @Test func revertingToAcceptedInputsCancelsPendingResponseWithoutAnotherCall()throws {
        var refresh=ResourceStrategyRefresh();refresh.setCloudOptIn(true)
        let a=try key(),b=try key(usable:3)
        let optionalaccepted=refresh.begin(a)
        let accepted=try #require(optionalaccepted);try refresh.accept([plan()],ticket:accepted)
        let optionalstale=refresh.begin(b)
        let stale=try #require(optionalstale)
        #expect(refresh.begin(a)==nil)
        #expect(throws:SessionError.stale){try refresh.accept([plan()],ticket:stale)}
        #expect(refresh.acceptedKey==a);#expect(refresh.acceptedPlans.count==1)
    }
    @Test func debounceInvalidatesBeforeDeadlineAndKeepsUsefulResults()throws {
        var refresh=ResourceStrategyRefresh();refresh.setCloudOptIn(true)
        let a=try key(),b=try key(usable:3),c=try key(usable:4)
        let optionalfirst=refresh.begin(a)
        let first=try #require(optionalfirst);try refresh.accept([plan()],ticket:first)
        let optionalpending=refresh.begin(b)
        let pending=try #require(optionalpending)
        let optionalDue=try refresh.enqueue(c,at:date)
        let due=try #require(optionalDue)
        #expect(refresh.beginReady(at:date)==nil)
        #expect(throws:SessionError.stale){try refresh.accept([plan()],ticket:pending)}
        #expect(refresh.acceptedKey==a)
        #expect(try refresh.enqueue(c,at:date.addingTimeInterval(0.1))==due)
        let optionalready=refresh.beginReady(at:due)
        let ready=try #require(optionalready);#expect(ready.key==c)
        refresh.failed(ticket:ready);#expect(refresh.acceptedKey==a)
        let optionalretry=refresh.begin(c)
        let retry=try #require(optionalretry);refresh.setCloudOptIn(false)
        #expect(throws:SessionError.stale){try refresh.accept([plan()],ticket:retry)}
        #expect(refresh.acceptedPlans.count==1);#expect(refresh.beginReady(at:due)==nil)
    }
    @Test func searchPlanMustMatchFrozenTasksTravelAndFiniteExpansion()throws {
        var refresh=ResourceStrategyRefresh();refresh.setCloudOptIn(true)
        let frozen=try key()
        let maybeTicket=refresh.begin(frozen)
        let ticket=try #require(maybeTicket)
        for invalid in [plan(taskID:"model-made-up-task"),plan(expansion:-1),plan(expansion:3),plan(travel:"driving")] {
            #expect(throws:SessionError.invalidCommand){try refresh.accept([invalid],ticket:ticket)}
        }
        try refresh.accept([plan()],ticket:ticket)
        #expect(throws:SessionError.stale){try refresh.accept([plan()],ticket:ticket)}
    }
}
