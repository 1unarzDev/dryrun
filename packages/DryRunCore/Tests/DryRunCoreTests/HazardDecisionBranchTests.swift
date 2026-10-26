import Foundation
import Testing
@testable import DryRunCore

/// Causal branch acceptance for all six hazards: every comparison holds the initial snapshot and
/// the director's external event schedule fixed and varies only committed household decisions.
/// Each hazard exercises at least two decision points whose alternatives change committed state,
/// later feasible options or later consequences. Simulated exercise effects only; never evidence
/// of physical safety, real arrival or score completion.
@Suite("Six-hazard decision branches") struct HazardDecisionBranchTests {
    enum Step {case director([SessionCommand]),user([SessionCommand])}

    func start(_ input:RehearsalInput,inventory:SessionInventorySeed?=nil)throws->SimulationSession {
        try SimulationSession.initialize(id:"branch-\(input.scenarioID)",initial:input,library:SimFixtures.library,inventory:inventory)
    }
    @discardableResult func act(_ s:inout SimulationSession,_ commands:[SessionCommand],actor:String="user")throws->SessionReceipt {
        try s.commit(.init(id:"step-\(s.revision)",actor:actor,baseRevision:s.revision,commands:commands),library:SimFixtures.library)
    }
    /// Plays a fixed director schedule; user steps are the only varied input between branches.
    func play(_ s:inout SimulationSession,_ steps:[Step])throws->SessionReceipt {
        var last=try s.query(library:SimFixtures.library)
        for step in steps {
            switch step {
            case .director(let commands):last=try act(&s,commands,actor:"director")
            case .user(let commands):last=try act(&s,commands)
            }
        }
        return last
    }
    func directorSchedule(_ steps:[Step])->[[SessionCommand]] {
        steps.compactMap {if case .director(let c)=$0 {return c};return nil}
    }
    /// Authored external events fired so far: identical across branches with one director schedule.
    func authored(_ r:SessionReceipt)->[String] {
        let all=Set(SimFixtures.library.scenarios.flatMap{$0.events.map(\.id)})
        return r.events.map(\.id).filter(all.contains)
    }
    func facts(_ r:SessionReceipt,_ kind:String)->[HazardDebriefFact] {r.experience?.debrief.filter{$0.kind==kind} ?? []}
    func has(_ r:SessionReceipt,_ kind:String,_ subject:String?=nil)->Bool {
        facts(r,kind).contains{subject==nil || $0.subjectIDs.contains(subject!)}
    }
    func destination()->RelocationDestination {
        RelocationDestination(id:"alternative",kind:.friendOrFamilyHome,label:"Synthetic agreed destination",conditionsConfirmed:.confirmed(true),acceptsPets:.confirmed(true),stepFreeAccess:.confirmed(true))
    }
}

// MARK: Home fire

extension HazardDecisionBranchTests {
    /// Decision 1: exit now versus stay; decision 2: account outside versus not.
    @Test func fireExitTimingAndAccountingChangeLaterOptionsAcrossLayouts()throws {
        var exercised=0
        for (home,household) in [(SampleHomes.ranch,SampleHouseholds.oak),(SampleHomes.apartment,SampleHouseholds.lake),(SampleHomes.twoStory,SampleHouseholds.oak),(SampleHomes.manufactured,SampleHouseholds.pine),(SampleHomes.scannedRanch,SampleHouseholds.oak)] {
            let input=SimFixtures.input(household,"home-fire",home:home)
            var base=try start(input)
            let alarm=try act(&base,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"schedule",target:"evt.home-fire.fire-origin",minute:1),.init(kind:"advance",minute:0)],actor:"director")
            let person=household.people[0].id
            guard let exit=alarm.routes.first(where:{$0.request.personID==person})?.primary?.exitPortalID else {
                // No supported route: escape is never offered and the limitation is explicit.
                #expect(alarm.experience?.feasibleCommands?.contains{$0.kind=="escape" && $0.target==person}==false)
                #expect(throws:SessionError.invalidCommand){try act(&base,[.init(kind:"escape",target:person,value:"pt-front")])}
                continue
            }
            exercised += 1
            var early=base,stayed=base,unaccounted=base
            let tail:[Step]=[.director([.init(kind:"advance",minute:1)])]
            _=try act(&early,[.init(kind:"escape",target:person,value:exit)])
            _=try act(&unaccounted,[.init(kind:"escape",target:person,value:exit)])
            let e=try play(&early,tail),s=try play(&stayed,tail),u=try play(&unaccounted,tail)
            // Same initial snapshot and director schedule; only the committed decision differs.
            #expect(early.initial==stayed.initial)
            #expect(authored(e)==authored(s))
            #expect(e.experience?.outsidePersonIDs.contains(person)==true)
            #expect(s.experience?.outsidePersonIDs.contains(person)==false)
            #expect(e.experience?.occupantRoomIDs[person]=="exterior")
            #expect(s.experience?.occupantRoomIDs[person] != "exterior")
            // Later option differs: only the departed branch can account this person outside.
            #expect(u.experience?.feasibleCommands?.contains(.init(kind:"accountOutside",target:person))==(home.meetingPoint?.verification == .verified))
            #expect(throws:SessionError.invalidCommand){try act(&stayed,[.init(kind:"accountOutside",target:person)])}
            if home.meetingPoint?.verification == .verified {
                let accounted=try act(&early,[.init(kind:"accountOutside",target:person)])
                #expect(accounted.experience?.accountedPersonIDs.contains(person)==true)
                #expect(u.experience?.accountedPersonIDs.contains(person)==false)
                #expect(facts(accounted,"outsideAccounting").first?.subjectIDs.contains(person)==false)
                #expect(facts(u,"outsideAccounting").first?.subjectIDs.contains(person)==true)
                // The debrief cites the actual committed trace in order.
                let trace=accounted.experience!.debrief.filter{$0.kind.hasPrefix("action.")}.map(\.kind)
                #expect(trace==["action.escape","action.accountOutside"])
                #expect(has(accounted,"action.escape",exit))
            }
            // Reentry is never offered after departure.
            #expect(throws:SessionError.invalidCommand){try act(&early,[.init(kind:"moveTo",target:person,value:"sp-hall")])}
        }
        #expect(exercised>=2)
    }

    /// Origin variation (director input, not a decision): a fire starting in the occupied room removes
    /// that person's supported exit, while a kitchen origin leaves only the exit away from it.
    @Test func fireOriginInOccupiedRoomRemovesSupportedEscape()throws {
        let input=SimFixtures.input(SampleHouseholds.oak,"home-fire")
        let person="p-oak-4" // records sp-living, limited mobility, cold-sensitive
        var outcomes:[String:SessionReceipt]=[:]
        for origin in ["sp-kitchen","sp-living"] {
            var s=try start(input)
            outcomes[origin]=try act(&s,[.init(kind:"startIncident",target:"evt.home-fire.fire-origin",value:origin,minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)],actor:"director")
        }
        let kitchen=try #require(outcomes["sp-kitchen"]),living=try #require(outcomes["sp-living"])
        #expect(kitchen.experience?.feasibleCommands?.contains(.init(kind:"escape",target:person,value:"pt-front"))==true)
        #expect(kitchen.experience?.feasibleCommands?.contains(.init(kind:"escape",target:person,value:"pt-back"))==false)
        #expect(living.experience?.feasibleCommands?.contains{$0.kind=="escape" && $0.target==person}==false)
        #expect(has(living,"noSupportedEscape",person) || has(living,"escapeRouteUnassessed",person))
    }

    /// Without any verified exterior opening, no escape is invented and the limitation is explicit.
    @Test func fireWithoutAnyExteriorExitReportsNoSupportedAction()throws {
        var home=SampleHomes.ranch
        home.portals.removeAll{$0.sideA == .exterior || $0.sideB == .exterior}
        var s=try start(SimFixtures.input(SampleHouseholds.oak,"home-fire",home:home))
        let r=try act(&s,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        #expect(r.experience?.feasibleCommands?.contains{$0.kind != "identifyGap"}==false)
        #expect(r.experience?.openGapIDs.contains("escapeRoute")==true)
        #expect(has(r,"noSupportedHazardAction","escapeRoute"))
        #expect(!has(r,"objectiveReached"))
    }
}

// MARK: Tornado

extension HazardDecisionBranchTests {
    /// Decision 1: reach shelter during the warning; decision 2: accompany the dependent child.
    @Test func tornadoShelterAndAccompanimentChangeShelteredStatusAndFallback()throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"tornado")
        input.household.people=input.household.people.map{var p=$0;p.sleepingSpaceID="sp-bed1";return p}
        var base=try start(input)
        _=try act(&base,[.init(kind:"schedule",target:"evt.tornado.warning",minute:0),.init(kind:"schedule",target:"evt.tornado.passed",minute:30),.init(kind:"advance",minute:0)],actor:"director")
        let shelter=try #require(ShelterSuitability.confirmedRoom(in:input.home!)).id
        let adult="p-oak-2",child="p-oak-3",helper="p-oak-1"
        var none=base,one=base,both=base
        _=try act(&one,[.init(kind:"reachShelter",target:adult,value:shelter)])
        _=try act(&both,[.init(kind:"reachShelter",target:adult,value:shelter)])
        let accompanied=try act(&both,[.init(kind:"accompanyShelter",target:child,value:helper)])
        #expect(accompanied.experience?.shelteredPersonIDs==[adult,helper,child].sorted())
        let tail:[Step]=[.director([.init(kind:"advance",minute:30)])]
        let n=try play(&none,tail),o=try play(&one,tail),b=try play(&both,tail)
        #expect(authored(n)==authored(b))
        #expect(n.experience?.shelteredPersonIDs==[])
        #expect(o.experience?.shelteredPersonIDs==[adult])
        #expect(Set(b.experience!.shelteredPersonIDs)==[adult,child,helper])
        #expect(facts(o,"notYetSheltered").first?.subjectIDs.contains(child)==true)
        #expect(facts(b,"notYetSheltered").first?.subjectIDs.contains(child)==false)
        // Later options differ: the accompaniment is no longer offered after both arrived.
        #expect(o.experience?.feasibleCommands?.contains(.init(kind:"accompanyShelter",target:child,value:helper))==true)
        #expect(b.experience?.feasibleCommands?.contains(.init(kind:"accompanyShelter",target:child,value:helper))==false)
        #expect(has(b,"action.accompanyShelter",child))
    }

    /// Manufactured home and a layout without a suitable room: no shelter arrival is invented.
    @Test func tornadoWithoutSupportedShelterNeverInventsArrival()throws {
        let pine=SimFixtures.input(SampleHouseholds.pine,"tornado",home:SampleHomes.manufactured)
        var s=try start(pine)
        let r=try act(&s,[.init(kind:"schedule",target:"evt.tornado.warning",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        #expect(r.experience?.feasibleCommands?.contains{$0.kind=="reachShelter" || $0.kind=="accompanyShelter"}==false)
        #expect(r.experience?.shelteredPersonIDs==[])
        #expect(!has(r,"objectiveReached"))
        // No recorded contact channel either: the absence of any supported action is explicit.
        #expect(r.experience?.feasibleCommands?.contains(where:{$0.kind != "identifyGap"})==false)
        #expect(has(r,"noSupportedHazardAction"))
        #expect(has(r,"noSuitableRecordedShelter"))
    }
}

// MARK: Flash flood

extension HazardDecisionBranchTests {
    func floodInput()->RehearsalInput {
        var home=SampleHomes.twoStory
        for i in home.floors.indices {home.floors[i].exteriorGrade=home.floors[i].level==0 ? .ground:.aboveGround}
        home.spaces[home.spaces.firstIndex{$0.id=="sp-bed1"}!].higherRefugeConfirmed = .confirmed(true)
        var h=SampleHouseholds.oak
        h.people=[Person(id:"resident",alias:"Synthetic resident",ageBand:.adult,sleepingSpaceID:"sp-hall"),Person(id:"second",alias:"Synthetic second",ageBand:.adult,sleepingSpaceID:"sp-hall")]
        h.equipment=[];h.backupPower=[]
        h.transport=Transport(vehicles:[Vehicle(id:"car",seats:4,wheelchairAccessible:.confirmed(true))],destinations:[destination()])
        var input=SimFixtures.input(h,"flash-flood",home:home)
        input.spatialOptions = .init(floodAffectedSpaceIDs:["sp-living"],refugeSpaceID:"sp-bed1")
        return input
    }
    func floodSupply()throws->SessionInventorySeed {
        let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
        var ledger=InventoryLedger()
        try ledger.confirm([InventoryItem(id:"water",physicalID:"jug",category:"water",quantity:.confirmed(3),unit:.usGallon,usableQuantity:.confirmed(3),accessible:.confirmed(true),locationID:"sp-hall")],baseRevision:0,at:date)
        return .init(ledger:ledger,asOf:date)
    }
    var accessLost:String {SimFixtures.library.scenario("flash-flood")!.events.first{$0.params["service"]==Svc.roads && $0.params["state"]=="unavailable"}!.id}

    /// Decision 1: leave early before access closes; decision 2: reach the confirmed refuge (and carry
    /// the supply) before the later access-loss stage. Timing changes who keeps a supported approach.
    @Test func floodTimingDecidesRefugeApproachAndSupplyAccess()throws {
        let base=try start(floodInput(),inventory:floodSupply())
        let schedule:[SessionCommand]=[.init(kind:"schedule",target:"evt.flash-flood.warning",minute:10),.init(kind:"schedule",target:accessLost,minute:120),.init(kind:"advance",minute:0)]
        var departed=base,refuge=base,waited=base
        _=try act(&departed,schedule,actor:"director");_=try act(&refuge,schedule,actor:"director");_=try act(&waited,schedule,actor:"director")
        // Decision 1 at minute 0: only the departed branch leaves while access remains.
        let left=try act(&departed,[.init(kind:"leaveEarly",target:"alternative")])
        #expect(left.experience?.relocated==true)
        let warning:[SessionCommand]=[.init(kind:"advance",minute:10)]
        let w=try act(&waited,warning,actor:"director");_=try act(&refuge,warning,actor:"director")
        #expect(throws:SessionError.invalidCommand){try act(&waited,[.init(kind:"leaveEarly",target:"alternative")])}
        #expect(w.experience?.refugeRoomID=="sp-bed1")
        // Decision 2 after the warning: carry the hall supply, then reach the refuge before access loss.
        _=try act(&refuge,[.init(kind:"takeSupply",target:"water",value:"resident"),.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1"),.init(kind:"reachHigherRefuge",target:"second",value:"sp-bed1")])
        let loss:[SessionCommand]=[.init(kind:"advance",minute:120)]
        let r=try act(&refuge,loss,actor:"director"),l=try act(&waited,loss,actor:"director")
        // Identical schedule fired in both at-home branches.
        #expect(authored(r)==authored(l))
        #expect(r.experience?.refugedPersonIDs==["resident","second"])
        #expect(has(r,"atHigherRefugeBeforeAccessLoss","resident"))
        #expect(!has(r,"refugeApproachLostAtAccessLoss"))
        #expect(r.inventory?.items.first?.accessible==true)
        #expect(r.inventory?.items.first?.locationID=="sp-bed1")
        // Waiting: the hall joins the excluded lower spaces, the approach and the supply are lost.
        #expect(l.snapshot.spatialState?.affectedSpaceIDs.contains("sp-hall")==true)
        #expect(has(l,"refugeApproachLostAtAccessLoss","resident"))
        #expect(l.experience?.feasibleCommands?.contains{$0.kind=="reachHigherRefuge"}==false)
        #expect(throws:SessionError.invalidCommand){try act(&waited,[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")])}
        #expect(l.inventory?.items.first?.accessible==false)
        #expect(has(l,"floodSupplyAccessLost","water"))
        #expect(has(r,"floodSupplyKeptAccessible","water"))
        // The departed branch reached its objective and its fallback ends rather than inventing a sequel.
        let d=try act(&departed,[.init(kind:"advance",minute:120)],actor:"director")
        #expect(has(d,"objectiveReached"))
        #expect(try departed.fallback(library:SimFixtures.library).commands==[.init(kind:"finish")])
    }
}

// MARK: Freeze and power loss

extension HazardDecisionBranchTests {
    func freezeInput()->RehearsalInput {
        var input=SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss")
        input.household.equipment[0].compatibleBackupIDs=["bk-station"]
        input.household.equipment[0].powerWatts = .confirmed(120,unit:"W")
        input.household.preparedness=PreparednessRecord(items:["warmth":PreparationFact(available:.confirmed(true))])
        input.household.backupPower[0].setupConfirmed = .confirmed(true)
        return input
    }

    /// Decision 1: allocate the finite station to the oxygen concentrator or hold it;
    /// decision 2: use recorded warmth before committing to stay. Reserves, device service,
    /// temperature and the person-specific stay record all differ under one schedule.
    @Test func freezeAllocationAndWarmthChangeReservesTemperatureAndStayRecord()throws {
        let base=try start(freezeInput())
        let outage:[SessionCommand]=[.init(kind:"schedule",target:"evt.freeze-power-loss.grid-loss",minute:0),.init(kind:"advance",minute:0)]
        var powered=base,held=base
        _=try act(&powered,outage,actor:"director");_=try act(&held,outage,actor:"director")
        _=try act(&powered,[.init(kind:"allocatePower",target:"eq-oxygen",value:"bk-station")])
        _=try act(&held,[.init(kind:"allocatePower",target:"eq-oxygen",value:"none")])
        _=try act(&powered,[.init(kind:"warmLayers")])
        let stay=SessionCommand(kind:"choose",target:"choice.freeze-power-loss.keep-warm",value:"layer-up")
        let p=try act(&powered,[stay]),h=try act(&held,[stay])
        let later:[SessionCommand]=[.init(kind:"advance",minute:240)]
        let p2=try act(&powered,later,actor:"director"),h2=try act(&held,later,actor:"director")
        #expect(authored(p2)==authored(h2))
        #expect(p2.snapshot.services[Svc.device("eq-oxygen")] == .operational)
        #expect(h2.snapshot.services[Svc.device("eq-oxygen")] != .operational)
        let pw=try #require(p2.snapshot.resources["res.backup.bk-station"]?.amount),hw=try #require(h2.snapshot.resources["res.backup.bk-station"]?.amount)
        #expect(pw<hw)
        #expect(p2.experience!.temperature!.lowerC>h2.experience!.temperature!.lowerC)
        // The stay decision records what was in place at the moment of choice.
        #expect(has(p,"thermalStayWithRecordedProtection","choice.freeze-power-loss.keep-warm"))
        #expect(has(h,"thermalStayWithoutRecordedProtection","choice.freeze-power-loss.keep-warm"))
        #expect(has(h,"thermalStaySensitivePersonExposed","p-oak-4"))
        #expect(has(h,"thermalStayEssentialEquipmentUnpowered","eq-oxygen"))
        #expect(!has(p,"thermalStayEssentialEquipmentUnpowered"))
        #expect(has(p2,"sensitivePersonWithRecordedWarmth","p-oak-4"))
        #expect(has(h2,"sensitivePersonWithoutRecordedWarmth","p-oak-4"))
        // Choosing to stay alone never manufactures warmth: the held branch's drift is unprotected.
        #expect(h2.experience?.selectedProtection==nil)
        #expect(facts(h,"thermalStayWithoutRecordedProtection").first?.nextActionID=="prep.heatCold")
    }

    /// Without recorded warmth, the warm-layers action is never offered.
    @Test func freezeWithoutRecordedWarmthOffersNoWarmthAction()throws {
        var input=freezeInput();input.household.preparedness=nil
        var s=try start(input)
        let r=try act(&s,[.init(kind:"schedule",target:"evt.freeze-power-loss.grid-loss",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        #expect(r.experience?.feasibleCommands?.contains(.init(kind:"warmLayers"))==false)
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"warmLayers")])}
    }
}

// MARK: Heat and grid strain

extension HazardDecisionBranchTests {
    func heatInput(home:HomeModel=SampleHomes.apartment)->RehearsalInput {
        var input=SimFixtures.input(SampleHouseholds.lake,"heat-grid-strain",home:home)
        input.household.people=input.household.people.map{var p=$0;p.sleepingSpaceID = p.id=="p-lake-1" ? "sp-hall":"sp-bed2";return p}
        return input
    }
    func windowRoom(_ home:HomeModel)->String? {
        home.portals.filter{$0.kind == .window}.compactMap{portal->String? in
            for side in [portal.sideA,portal.sideB] {if case .space(let id)=side {return id}};return nil
        }.sorted().first
    }

    /// Decision 1: choose a shaded room; decision 2: move the heat-sensitive person into it before
    /// committing to stay. The person's exposure record and room range differ; no cooling is added.
    @Test func heatShadeAndMoveChangeSensitivePersonExposureAcrossLayouts()throws {
        var exercised=0
        for home in [SampleHomes.apartment,SampleHomes.ranch,SampleHomes.twoStory] {
            guard let room=windowRoom(home) else {continue}
            var input=heatInput(home:home)
            input.household.people=input.household.people.map{var p=$0;p.sleepingSpaceID = p.id=="p-lake-1" ? (room=="sp-living" ? "sp-kitchen":"sp-living"):room;return p}
            guard input.household.people.allSatisfy({home.space($0.sleepingSpaceID ?? "") != nil}) else {continue}
            let base=try start(input)
            let outage=SimFixtures.library.scenario("heat-grid-strain")!.events.first{$0.rule==RuleID.setExternal && $0.params["service"]==Svc.grid && $0.params["state"]=="unavailable"}!
            var moved=base,shadedOnly=base
            let schedule:[SessionCommand]=[.init(kind:"schedule",target:outage.id,minute:0),.init(kind:"advance",minute:0)]
            _=try act(&moved,schedule,actor:"director");_=try act(&shadedOnly,schedule,actor:"director")
            _=try act(&moved,[.init(kind:"reduceSolarGain",target:room)])
            let offered=try act(&shadedOnly,[.init(kind:"reduceSolarGain",target:room)])
            let move=SessionCommand(kind:"moveTo",target:"p-lake-1",value:room)
            guard offered.experience?.feasibleCommands?.contains(move)==true else {
                // A supported path must exist for the offer; the limitation is the recorded room access.
                #expect(throws:SessionError.invalidCommand){try act(&moved,[move])}
                continue
            }
            exercised += 1
            _=try act(&moved,[move])
            let stay=SessionCommand(kind:"choose",target:"choice.heat-grid-strain.hottest-hours",value:"stay-cool")
            let m=try act(&moved,[stay]),s=try act(&shadedOnly,[stay])
            let later:[SessionCommand]=[.init(kind:"advance",minute:180)]
            let m2=try act(&moved,later,actor:"director"),s2=try act(&shadedOnly,later,actor:"director")
            #expect(authored(m2)==authored(s2))
            #expect(m2.experience?.occupantRoomIDs["p-lake-1"]==room)
            #expect(s2.experience?.occupantRoomIDs["p-lake-1"] != room)
            #expect(has(m2,"sensitivePersonInShadedRoom","p-lake-1"))
            #expect(has(s2,"sensitivePersonInUnshadedRoom","p-lake-1"))
            #expect(!has(m,"thermalStaySensitivePersonExposed"))
            #expect(has(s,"thermalStaySensitivePersonExposed","p-lake-1"))
            let mRange=try #require(m2.experience?.roomTemperatures?[room])
            let sRoom=try #require(s2.experience?.occupantRoomIDs["p-lake-1"])
            let sRange=try #require(s2.experience?.roomTemperatures?[sRoom])
            #expect(mRange.upperC<sRange.upperC)
            // Both stayed with conditioning unavailable and a shading assumption: never a cooling claim.
            #expect(m2.snapshot.services[Svc.cooling] != .operational)
            #expect(has(m,"thermalStayWithRecordedProtection"))
            #expect(m2.experience?.feasibleCommands?.contains(move)==false)
        }
        #expect(exercised>=2)
    }

    /// Before an outage the stay decision is recorded as made with conditioning available.
    @Test func heatStayBeforeOutageIsNotReportedAsUnprotected()throws {
        var s=try start(heatInput())
        let r=try act(&s,[.init(kind:"choose",target:"choice.heat-grid-strain.hottest-hours",value:"stay-cool")])
        if r.snapshot.services[Svc.cooling] == .operational {
            #expect(has(r,"thermalStayWithConditioning"))
            #expect(!has(r,"thermalStayWithoutRecordedProtection"))
        }
    }
}

// MARK: Water outage

extension HazardDecisionBranchTests {
    /// Decision 1: essential-only versus all-use allocation; decision 2: an explicit stored-water
    /// activity. Remaining quantity and the advisory-dependent later options differ.
    @Test func waterAllocationAndActivityChangeLaterQuantityAndOptions()throws {
        var input=SimFixtures.input(SampleHouseholds.lake,"water-outage",home:SampleHomes.apartment)
        input.household.supplies.storedWaterGallons = .confirmed(6)
        let base=try start(input)
        let schedule:[SessionCommand]=[.init(kind:"schedule",target:"evt.water-outage.main-break",minute:0),.init(kind:"advance",minute:0)]
        var essential=base,all=base
        _=try act(&essential,schedule,actor:"director");_=try act(&all,schedule,actor:"director")
        _=try act(&essential,[.init(kind:"useStoredWater",value:"essential")])
        _=try act(&all,[.init(kind:"useStoredWater",value:"all")])
        let drink=SessionCommand(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:2)
        let e=try act(&essential,[drink])
        #expect(has(e,"storedWaterActivityDebited"))
        let later:[SessionCommand]=[.init(kind:"advance",minute:300)]
        let e2=try act(&essential,later,actor:"director"),a2=try act(&all,later,actor:"director")
        #expect(authored(e2)==authored(a2))
        let eg=try #require(e2.experience?.availableWaterGallons),ag=try #require(a2.experience?.availableWaterGallons)
        #expect(eg != ag)
        // Tap use is unavailable during the quantity outage in both branches.
        #expect(e2.experience?.feasibleCommands?.contains{$0.kind=="useWater" && $0.target=="tap"}==false)
        #expect(has(e2,"action.useStoredWater","essential"))
        #expect(has(a2,"action.useStoredWater","all"))
    }

    /// With no stored water and tap service lost, no supply action is invented.
    @Test func waterWithoutStoredSupplyOrTapReportsNoSupportedAction()throws {
        var input=SimFixtures.input(SampleHouseholds.lake,"water-outage",home:SampleHomes.apartment)
        input.household.supplies.storedWaterGallons = .confirmed(0)
        var s=try start(input)
        let r=try act(&s,[.init(kind:"schedule",target:"evt.water-outage.main-break",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        #expect(r.experience?.feasibleCommands?.contains{$0.kind=="useWater"}==false)
        #expect(r.experience?.openGapIDs.contains("storedWater")==true)
        #expect(r.experience?.feasibleCommands?.contains(where:{$0.kind != "identifyGap"})==false)
        #expect(has(r,"noSupportedHazardAction","storedWater"))
    }
}

// MARK: Trace (authored playback stability is covered by the versioned AuthoredAdapterTests hashes)

extension HazardDecisionBranchTests {
    /// The trace survives restore and is bounded.
    @Test func traceRoundTripsAndIsBounded()throws {
        var input=SimFixtures.input(SampleHouseholds.lake,"water-outage",home:SampleHomes.apartment)
        input.household.supplies.storedWaterGallons = .confirmed(20)
        var s=try start(input)
        for _ in 0..<30 {_=try act(&s,[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)])}
        let r=try s.query(library:SimFixtures.library)
        #expect(facts(r,"action.useWater").count==24)
        #expect(r.experience!.debrief.count<=100)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try restored.query(library:SimFixtures.library)==r)
    }
}
