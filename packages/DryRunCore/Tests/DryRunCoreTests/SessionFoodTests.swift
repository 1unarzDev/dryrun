import Foundation
import Testing
@testable import DryRunCore

@Suite("Recorded household food-days in the shared exercise reducer") struct SessionFoodTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func food(_ amount:Double=1,unit:InventoryUnit = .day,usable:Bool=true,subjects:[String]=[],expiry:Date?=nil)->InventoryItem {
        InventoryItem(id:"food",physicalID:"recorded-food",category:"food",quantity:.confirmed(amount),unit:unit,
                      usableQuantity:usable ? .confirmed(amount):.unknown,accessible:.confirmed(true),locationID:"sp-kitchen",expiresAt:expiry,subjectIDs:subjects)
    }
    func session(_ items:[InventoryItem],scenario:String="water-outage",policy:ExerciseFoodPolicy? = .recordedHouseholdDays)throws->SimulationSession {
        var ledger=InventoryLedger();try ledger.confirm(items,baseRevision:0,at:date)
        var input=SimFixtures.input(SampleHouseholds.oak,scenario)
        var options=input.effectiveSpatialOptions
        for person in input.household.people {options.startingSpaceIDs[person.id]="sp-kitchen"}
        input.spatialOptions=options
        return SimulationSession(id:"food",initial:input,inventory:.init(ledger:ledger,asOf:date,foodPolicy:policy))
    }
    @discardableResult func advance(_ s:inout SimulationSession,to:Int)throws->SessionReceipt {
        try s.commit(.init(id:"advance-\(s.revision)",actor:"director",baseRevision:s.revision,commands:[.init(kind:"advance",minute:to)]),library:SimFixtures.library)
    }
    @Test func consumesRecordedCoverageWithoutInferringNutritionAndStopsAtDepletion()throws {
        var s=try session([food()]);let source=try DryRunJSON.encoder().encode(s.inventory!)
        let half=try advance(&s,to:720)
        #expect(half.snapshot.resources["res.food.days"]?.amount==0.5)
        #expect(half.inventory?.items[0].consumed==0.5)
        #expect(half.inventory?.foodPolicyVersion=="dryrun.exercise-food/1")
        let empty=try advance(&s,to:4320)
        #expect(empty.snapshot.simMinute==1440)
        #expect(empty.snapshot.resources["res.food.days"]?.amount==0)
        #expect(empty.snapshot.unmetRequirements.contains("req.food"))
        #expect(empty.events.filter{$0.evidence.ruleID=="rule.resource.food/1"}.count==1)
        #expect(try DryRunJSON.encoder().encode(s.inventory!)==source)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try restored.query(library:SimFixtures.library)==empty)
        #expect(throws:SessionError.duplicate){try s.commit(s.commits.last!,library:SimFixtures.library)}
        let later=try advance(&s,to:4320)
        #expect(later.inventory?.items[0].remaining==0)
        #expect(later.inventory?.items[0].consumed==1)
    }
    @Test func missingAmountsPackagesAndPartialScopeStayUnknown()throws {
        for (item,unknown) in [(food(2,unit:.count),"inventory.food.unit"),(food(2,usable:false),"inventory.food.available"),(food(2,subjects:["reserved-person"]),"inventory.food.subjectScope")] {
            var s=try session([item]);let r=try advance(&s,to:720)
            #expect(r.snapshot.resources["res.food.days"]?.amount==nil)
            #expect(r.snapshot.unknowns.contains(unknown))
            #expect(!r.snapshot.unmetRequirements.contains("req.food"))
            #expect(r.inventory?.items[0].consumed==0)
        }
        var missing=try session([]);let r=try advance(&missing,to:720)
        #expect(r.snapshot.unknowns.contains("inventory.food.available"))
        #expect(r.snapshot.resources["res.food.days"]?.amount==nil)
    }
    @Test func expirySettlesActualUseWithoutConsumingExpiredStock()throws {
        var s=try session([food(2,expiry:date.addingTimeInterval(3600))])
        let r=try advance(&s,to:4320),item=try #require(r.inventory?.items[0])
        #expect(r.snapshot.simMinute==60);#expect(item.accessible==false)
        #expect(abs(item.consumed-1.0/24)<1e-9)
        #expect(abs(item.remaining!+item.consumed-2)<1e-9)
        #expect(r.snapshot.resources["res.food.days"]?.amount==0)
        #expect(r.snapshot.unmetRequirements.contains("req.food"))
    }
    @Test func simultaneousWaterAndFoodDepletionConservesBoth()throws {
        let people=Double(SampleHouseholds.oak.people.count)
        let water=InventoryItem(id:"water",physicalID:"water",category:"water",quantity:.confirmed(people/24),unit:.usGallon,usableQuantity:.confirmed(people/24),accessible:.confirmed(true))
        var s=try session([food(1.0/24),water])
        try s.commit(.init(id:"outage",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        let r=try advance(&s,to:720)
        #expect(r.snapshot.simMinute==60)
        #expect(r.snapshot.unmetRequirements.contains("req.food"));#expect(r.snapshot.unmetRequirements.contains("req.water"))
        for item in r.inventory!.items {
            #expect(item.remaining==0)
            let initial=s.inventory!.ledger.items.first{$0.id==item.id}!.usableQuantity.confirmedValue!
            #expect(abs(item.consumed-initial)<1e-9)
        }
    }
    @Test func carriedFoodRetainsAccessWhenOriginalStorageIsBlocked()throws {
        var blocked=try session([food(2)],scenario:"home-fire"),carried=blocked
        let person=carried.initial.household.people[0].id
        try carried.commit(.init(id:"carry",actor:"user",baseRevision:0,commands:[.init(kind:"takeSupply",target:"food",value:person),.init(kind:"moveTo",target:person,value:"sp-living"),.init(kind:"transferSupply",target:"food",value:"sp-living")]),library:SimFixtures.library)
        let commands:[SessionCommand]=[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1),.init(kind:"advance",minute:1)]
        let a=try blocked.commit(.init(id:"fire",actor:"director",baseRevision:blocked.revision,commands:commands),library:SimFixtures.library)
        let b=try carried.commit(.init(id:"fire",actor:"director",baseRevision:carried.revision,commands:commands),library:SimFixtures.library)
        #expect(a.inventory?.items[0].accessible==false);#expect(a.snapshot.resources["res.food.days"]?.amount==0)
        #expect(b.inventory?.items[0].accessible==true);#expect(b.snapshot.resources["res.food.days"]?.amount==2)
        #expect(abs(b.inventory!.items[0].remaining!+b.inventory!.items[0].consumed-2)<1e-9)
        #expect(blocked.inventory!.ledger.items[0].locationID=="sp-kitchen")
        #expect(carried.inventory!.ledger.items[0].locationID=="sp-kitchen")
    }
    @Test func multiplePhysicalStocksConserveCoverageAndRejectOverflow()throws {
        var second=food(1);second.id="second";second.physicalID="second-physical"
        var s=try session([food(1),second]);let r=try advance(&s,to:720)
        #expect(r.snapshot.resources["res.food.days"]?.amount==1.5)
        #expect(r.snapshot.unknowns.contains("inventory.food.storageAndDietarySuitability"))
        for item in r.inventory!.items {#expect(abs(item.remaining!+item.consumed-1)<1e-9)}
        #expect(r.inventory!.items.reduce(0){$0+$1.consumed}==0.5)
        second.quantity = .confirmed(Double.greatestFiniteMagnitude);second.usableQuantity=second.quantity
        let overflowing=try session([food(Double.greatestFiniteMagnitude),second])
        #expect(throws:SessionError.invalidCommand){try overflowing.query(library:SimFixtures.library)}
    }
    @Test func legacySourcesRemainWaterOnlyAndFailedWritesDoNotConsumeFood()throws {
        var old=try session([food(2)],policy:nil)
        let json=try DryRunJSON.encoder().encode(old)
        #expect(!String(decoding:json,as:UTF8.self).contains("foodPolicy"))
        old=try DryRunJSON.decoder().decode(SimulationSession.self,from:json)
        let r=try advance(&old,to:720)
        #expect(r.snapshot.resources["res.food.days"]==nil)
        #expect(r.inventory?.items[0].remaining==2);#expect(r.inventory?.items[0].consumed==0)
        var s=try session([food(2)]);let before=try s.query(library:SimFixtures.library)
        #expect(throws:SessionError.persistence){try s.commit(.init(id:"fail",actor:"director",baseRevision:0,commands:[.init(kind:"advance",minute:720)]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try s.query(library:SimFixtures.library)==before)
        let seedJSON=String(decoding:try DryRunJSON.encoder().encode(s.inventory!),as:UTF8.self).replacingOccurrences(of:"dryrun.exercise-food/1",with:"future")
        #expect(throws:(any Error).self){try DryRunJSON.decoder().decode(SessionInventorySeed.self,from:Data(seedJSON.utf8))}
    }
}
