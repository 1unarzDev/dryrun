import Foundation
import Testing
@testable import DryRunCore

@Suite("Exercise inventory conservation and access") struct SessionInventoryTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func session(_ scenario:String="water-outage",expiry:Date?=nil,unknown:Bool=false)throws->SimulationSession {
        var ledger=InventoryLedger()
        try ledger.confirm([InventoryItem(id:"water",physicalID:"container",category:"water",quantity:.confirmed(5),unit:.usGallon,usableQuantity:unknown ? .unknown : .confirmed(5),accessible:.confirmed(true),locationID:"sp-kitchen",expiresAt:expiry)],baseRevision:0,at:date)
        var input=SimFixtures.input(SampleHouseholds.oak,scenario)
        var options=input.effectiveSpatialOptions
        for person in input.household.people {options.startingSpaceIDs[person.id]="sp-kitchen"}
        input.spatialOptions=options
        return SimulationSession(id:"inventory",initial:input,inventory:.init(ledger:ledger,asOf:date))
    }
    func submit(_ session:inout SimulationSession,_ commands:[SessionCommand],actor:String="user")throws->SessionReceipt {
        try session.commit(.init(id:"commit-\(session.revision)",actor:actor,baseRevision:session.revision,commands:commands),library:SimFixtures.library)
    }
    @Test func exactConsumptionReplayAndNoHouseholdMutation()throws {
        var s=try session()
        let original=try DryRunJSON.encoder().encode(s.inventory!.ledger)
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let r=try submit(&s,[.init(kind:"advance",minute:720)],actor:"director")
        #expect(r.snapshot.resources["res.water.stored"]?.amount==3)
        #expect(abs(r.inventory!.items[0].remaining!-3)<1e-9)
        #expect(abs(r.inventory!.items[0].consumed-2)<1e-9)
        let resumed=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try resumed.query(library:SimFixtures.library)==r)
        #expect(try DryRunJSON.encoder().encode(s.inventory!.ledger)==original)
        #expect(s.initial.household.supplies.storedWaterGallons.confirmedValue==5)
        #expect(throws:SessionError.duplicate){try s.commit(s.commits.last!,library:SimFixtures.library)}
        #expect(try s.query(library:SimFixtures.library)==r)
    }
    @Test func storageBlockedVersusSuppliesCarriedBeforeIncident()throws {
        var blocked=try session("home-fire"),carried=blocked
        let person=carried.initial.household.people[0].id
        _=try submit(&carried,[.init(kind:"takeSupply",target:"water",value:person),.init(kind:"moveTo",target:person,value:"sp-living"),.init(kind:"transferSupply",target:"water",value:"sp-living")])
        let incident:[SessionCommand]=[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1),.init(kind:"advance",minute:1)]
        let a=try submit(&blocked,incident,actor:"director"),b=try submit(&carried,incident,actor:"director")
        #expect(a.inventory!.items[0].accessible==false)
        #expect(a.snapshot.resources["res.water.stored"]?.amount==0)
        #expect(a.inventory!.items[0].remaining==5) // blocked stock still physically exists
        #expect(b.inventory!.items[0].accessible==true)
        #expect(b.inventory!.items[0].locationID=="sp-living")
        #expect(b.snapshot.resources["res.water.stored"]?.amount==5)
        #expect(throws:SessionError.invalidCommand){try submit(&blocked,[.init(kind:"takeSupply",target:"water",value:person)])}
        #expect(try blocked.query(library:SimFixtures.library)==a)
        #expect(blocked.inventory!.ledger.items[0].locationID=="sp-kitchen")
        #expect(carried.inventory!.ledger.items[0].locationID=="sp-kitchen")
    }
    @Test func expiryIsMandatoryBoundaryAndUnknownNeverBecomesKnown()throws {
        var s=try session(expiry:date.addingTimeInterval(60*60))
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let r=try submit(&s,[.init(kind:"advance",minute:720)],actor:"director")
        #expect(r.snapshot.simMinute==60)
        #expect(r.inventory!.items[0].accessible==false)
        #expect(abs(r.inventory!.items[0].consumed-Double(4)/24)<1e-9)
        #expect(r.snapshot.resources["res.water.stored"]?.amount==0)
        var unknown=try session(unknown:true)
        let u=try submit(&unknown,[.init(kind:"advance",minute:720)],actor:"director")
        #expect(u.snapshot.resources["res.water.stored"]?.amount==nil)
        #expect(u.inventory!.items[0].remaining==nil)
        #expect(u.snapshot.unknowns.contains("inventory.water.available"))
    }
    @Test func mixedUnitsConserveEachPhysicalContainer()throws {
        var ledger=InventoryLedger()
        try ledger.confirm([
            InventoryItem(id:"a",physicalID:"liters",category:"water",quantity:.confirmed(2*3.785411784),unit:.liter,usableQuantity:.confirmed(2*3.785411784),accessible:.confirmed(true)),
            InventoryItem(id:"b",physicalID:"gallons",category:"water",quantity:.confirmed(3),unit:.usGallon,usableQuantity:.confirmed(3),accessible:.confirmed(true))
        ],baseRevision:0,at:date)
        var s=SimulationSession(id:"units",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),inventory:.init(ledger:ledger,asOf:date))
        _=try submit(&s,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let r=try submit(&s,[.init(kind:"advance",minute:720)],actor:"director")
        #expect(r.snapshot.resources["res.water.stored"]?.amount==3)
        for item in r.inventory!.items {
            let source=ledger.items.first{$0.id==item.id}!
            #expect(abs(item.remaining!+item.consumed-source.usableQuantity.confirmedValue!)<1e-9)
            #expect(item.remaining!>=0)
        }
    }
    @Test func fractionalExpiryRoundsConservatively()throws {
        var s=try session(expiry:date.addingTimeInterval(59*60+30))
        let r=try submit(&s,[.init(kind:"advance",minute:720)],actor:"director")
        #expect(r.snapshot.simMinute==59)
        #expect(r.inventory!.items[0].accessible==false)
        #expect(r.inventory!.items[0].remaining==5)
    }
    @Test func authorityMovementAndAtomicPersistence()throws {
        var s=try session();let person=s.initial.household.people[0].id
        let before=try s.query(library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"takeSupply",target:"water",value:person)],actor:"director")}
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"transferSupply",target:"water",value:"sp-living")])}
        #expect(throws:SessionError.persistence){try s.commit(.init(id:"save",actor:"user",baseRevision:0,commands:[.init(kind:"takeSupply",target:"water",value:person)]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try s.query(library:SimFixtures.library)==before)
        _=try submit(&s,[.init(kind:"moveTo",target:person,value:"sp-living")])
        #expect(throws:SessionError.invalidCommand){try submit(&s,[.init(kind:"takeSupply",target:"water",value:person)])}
    }
}
