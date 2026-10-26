import Foundation
import Testing
@testable import DryRunCore

/// Mirrors the native phone scripts in `HazardChoiceUITests` with the same sample family, home and local director,
/// so the accessibility identifiers the phone reviewer taps (`rehearsal.cmd.<kind>.<target>.<value>`) are known to be
/// offered by the host. The app policy: tap the target choice when offered, otherwise answer a due authored question
/// with its first option, otherwise let the local director continue.
@Suite("Native hazard choice scripts") struct NativeHazardChoiceScriptTests {
    let library=SimFixtures.library

    struct Run {
        var session:SimulationSession
        var receipt:SessionReceipt
    }

    func open(_ household:HouseholdProfile,_ scenario:String,_ home:HomeModel)throws->Run {
        let input=SimFixtures.input(household,scenario,home:home)
        var s=try SimulationSession.initialize(id:"native-\(scenario)",initial:input,library:library)
        var r=try s.query(library:library)
        if let first=LocalDirector.nextCommit(session:s,receipt:r,library:library) {r=try s.commit(first,library:library)}
        return Run(session:s,receipt:r)
    }
    func ids(_ run:Run)->[String] {
        HazardChoices.options(run.receipt,household:run.session.initial.household,home:run.session.initial.home).map{"rehearsal.cmd.\($0.id)"}
    }
    /// Advances like the app until `prefix` is offered; returns the matching identifier or nil.
    func advance(_ run:inout Run,until prefix:String,steps:Int=12,answer:Bool=true)throws->String? {
        for _ in 0..<steps {
            if let id=ids(run).first(where:{$0.hasPrefix(prefix)}) {return id}
            if run.receipt.finished {return nil}
            if run.receipt.directorState?.awaitingUserAction==true {
                if answer,let choice=LocalDirector.dueChoice(session:run.session,receipt:run.receipt,library:library) {
                    run.receipt=try run.session.commit(.init(id:"u\(run.session.revision)",actor:"user",baseRevision:run.session.revision,commands:[.init(kind:"choose",target:choice.id,value:choice.options[0].id)]),library:library)
                } else if HazardChoices.waitAvailable(session:run.session,receipt:run.receipt,library:library) {
                    run.receipt=try run.session.commit(.init(id:"u\(run.session.revision)",actor:"user",baseRevision:run.session.revision,commands:[.init(kind:"wait")]),library:library)
                } else {return nil}
                continue
            }
            guard let next=LocalDirector.nextCommit(session:run.session,receipt:run.receipt,library:library) else {return nil}
            run.receipt=try run.session.commit(next,library:library)
        }
        return nil
    }
    @discardableResult func tap(_ run:inout Run,_ id:String)throws->SessionReceipt {
        let choice=try #require(HazardChoices.options(run.receipt,household:run.session.initial.household,home:run.session.initial.home).first{"rehearsal.cmd.\($0.id)"==id})
        run.receipt=try run.session.commit(.init(id:"t\(run.session.revision)",actor:"user",baseRevision:run.session.revision,commands:[choice.command]),library:library)
        return run.receipt
    }

    /// Heat, hh-lake in the ranch: shade the living room, then move Bà there.
    @Test func heatShadeThenMove()throws {
        var run=try open(SampleHouseholds.lake,"heat-grid-strain",SampleHomes.ranch)
        let shade=try #require(try advance(&run,until:"rehearsal.cmd.reduceSolarGain.sp-living"))
        try tap(&run,shade)
        #expect(ids(run).contains("rehearsal.cmd.moveTo.p-lake-1.sp-living"))
        let moved=try tap(&run,"rehearsal.cmd.moveTo.p-lake-1.sp-living")
        #expect(moved.experience?.occupantRoomIDs["p-lake-1"]=="sp-living")
        #expect(!ids(run).contains{$0.hasPrefix("rehearsal.cmd.moveTo.p-lake-1.")})
    }

    /// Fire, hh-oak in the ranch: Parent A escapes by an offered exit, then is checked at the meeting place.
    @Test func fireEscapeThenAccount()throws {
        var run=try open(SampleHouseholds.oak,"home-fire",SampleHomes.ranch)
        let escape=try #require(try advance(&run,until:"rehearsal.cmd.escape.p-oak-1.",answer:false))
        try tap(&run,escape)
        #expect(run.receipt.experience?.outsidePersonIDs.contains("p-oak-1")==true)
        let account="rehearsal.cmd.accountOutside.p-oak-1"
        if SampleHomes.ranch.meetingPoint?.verification == .verified {
            #expect(ids(run).contains(account))
            let accounted=try tap(&run,account)
            let trace=accounted.experience!.debrief.filter{$0.kind.hasPrefix("action.")}.map(\.kind)
            #expect(trace.suffix(2)==["action.escape","action.accountOutside"])
        } else {
            #expect(!ids(run).contains(account))
        }
        // Never offered back inside.
        #expect(!ids(run).contains{$0.hasPrefix("rehearsal.cmd.escape.p-oak-1.")})
    }

    /// Tornado, hh-oak in the ranch: Parent A takes the child to the shelter; the others go themselves.
    @Test func tornadoShelterAndAccompany()throws {
        var run=try open(SampleHouseholds.oak,"tornado",SampleHomes.ranch)
        let accompany=try #require(try advance(&run,until:"rehearsal.cmd.accompanyShelter.p-oak-3.p-oak-1",steps:16))
        try tap(&run,accompany)
        let sheltered=Set(run.receipt.experience?.shelteredPersonIDs ?? [])
        #expect(sheltered.contains("p-oak-1") && sheltered.contains("p-oak-3"))
        for id in ids(run) where id.hasPrefix("rehearsal.cmd.reachShelter.") {try tap(&run,id)}
        #expect(!ids(run).contains{$0.hasPrefix("rehearsal.cmd.reachShelter.") || $0.hasPrefix("rehearsal.cmd.accompanyShelter.")})
    }

    /// Water, hh-oak in the ranch (private well): stored-water uses are offered with explicit activity; no tap use.
    @Test func waterAllocationOffersStoredUsesOnly()throws {
        var run=try open(SampleHouseholds.oak,"water-outage",SampleHomes.ranch)
        let drink=try #require(try advance(&run,until:"rehearsal.cmd.useWater.",answer:false))
        #expect(!ids(run).contains{$0.hasPrefix("rehearsal.cmd.useWater.tap.")})
        let before=run.receipt.snapshot.resources["res.water.stored"]?.amount
        try tap(&run,drink)
        let after=run.receipt.snapshot.resources["res.water.stored"]?.amount
        if let before,let after {#expect(after<before)}
    }

    /// Water, hh-lake (city water): under the later boil-water advisory, boiling tap water is offered and unboiled
    /// tap drinking is not (mirrors `testWaterAllocationUnderAdvisory`).
    @Test func waterAdvisoryOffersBoilNotDrink()throws {
        var run=try open(SampleHouseholds.lake,"water-outage",SampleHomes.ranch)
        #expect(try advance(&run,until:"rehearsal.cmd.useWater.") != nil)
        let boiled=try #require(try advance(&run,until:"rehearsal.cmd.useWater.tap.boiledDrink",steps:20))
        #expect(!ids(run).contains("rehearsal.cmd.useWater.tap.drink"))
        #expect(run.receipt.experience?.waterAdvisory == .boilWater)
        try tap(&run,boiled)
    }

    /// Flood: when the host establishes a higher refuge, its approach is offered before the access-loss stage and
    /// a waiting branch records the lost approach.
    @Test func floodRefugeBeforeAccessLossWhenEstablished()throws {
        var found=0
        for (household,home) in [(SampleHouseholds.oak,SampleHomes.twoStory),(SampleHouseholds.lake,SampleHomes.twoStory),(SampleHouseholds.oak,SampleHomes.ranch)] {
            var run=try open(household,"flash-flood",home)
            guard let refuge=try advance(&run,until:"rehearsal.cmd.reachHigherRefuge.",steps:16) else {continue}
            found += 1
            var waited=run
            try tap(&run,refuge)
            // The waiting branch continues to access loss with the same director.
            _=try advance(&waited,until:"rehearsal.cmd.never",steps:6)
            let lost=waited.receipt.experience?.debrief.contains{$0.kind=="refugeApproachLostAtAccessLoss"}==true
            let fired=waited.receipt.snapshot.firedEventIDs.contains("evt.flash-flood.access-lost")
            if fired {#expect(lost)}
        }
        // Sample homes record no confirmed higher refuge and adaptive sessions carry no setup refuge, so no sample
        // flood offers one natively (Core pairs are covered in HazardDecisionBranchTests). If this changes, extend
        // HazardChoiceUITests with the refuge-before-access-loss script.
        #expect(found==0)
    }
}
