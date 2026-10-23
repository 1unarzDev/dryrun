import Foundation
import Testing
@testable import DryRunCore

@Suite("Six hazard differentiation gates") struct SixHazardExperienceTests {
    @Test func everySelectedHazardCarriesExecutableMechanicsAndDistinctScene() throws {
        var scenes=Set<String>()
        for scenario in SimFixtures.library.scenarios {
            let input=SimFixtures.input(SampleHouseholds.oak,scenario.id)
            let session=try SimulationSession.initialize(id:scenario.id,initial:input,library:SimFixtures.library)
            let receipt=try session.query(library:SimFixtures.library)
            let json=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(receipt)) as! [String:Any]
            let experience=json["experience"] as? [String:Any]
            #expect(experience != nil, "Missing selected-hazard mechanics: \(scenario.id)")
            if let experience {
                #expect(experience["hazard"] as? String == scenario.hazard.rawValue)
                if let scene=experience["scene"] as? String {scenes.insert(scene)}
            }
        }
        #expect(scenes.count == 6)
    }
}

extension SixHazardExperienceTests {
    func session(_ id:String)throws->SimulationSession {
        var input=SimFixtures.input(SampleHouseholds.oak,id)
        input.household.people=input.household.people.map {person in var p=person;p.sleepingSpaceID="sp-bed1";return p}
        input.household.transport=Transport(vehicles:[Vehicle(id:"car",seats:8,wheelchairAccessible:.confirmed(true))],destinations:[RelocationDestination(id:"alternative",kind:.friendOrFamilyHome,label:"Synthetic agreed destination",conditionsConfirmed:.confirmed(true),acceptsPets:.confirmed(true),stepFreeAccess:.confirmed(true))])
        input.household.preparedness=PreparednessRecord(items:["warmth":PreparationFact(available:.confirmed(true))])
        input.household.supplies.storedWaterGallons = .confirmed(12)
        input.household.housing.waterSource = .municipal
        return try SimulationSession.initialize(id:id,initial:input,library:SimFixtures.library)
    }
    @discardableResult func act(_ session:inout SimulationSession,_ commands:[SessionCommand],actor:String="user")throws->SessionReceipt {
        try session.commit(.init(id:"step-\(session.revision)",actor:actor,baseRevision:session.revision,commands:commands),library:SimFixtures.library)
    }
    @Test func fireEscapeAndAccountingAreSeparateAndCannotReenter()throws {
        var s=try session("home-fire")
        let before=try act(&s,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let person=s.initial.household.people[0].id
        let route=try #require(before.routes.first{$0.request.personID==person}?.primary)
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"accountOutside",target:person)])}
        let escaped=try act(&s,[.init(kind:"escape",target:person,value:route.exitPortalID)])
        #expect(escaped.experience?.outsidePersonIDs == [person])
        #expect(escaped.experience?.accountedPersonIDs == [])
        let accounted=try act(&s,[.init(kind:"accountOutside",target:person)])
        #expect(accounted.experience?.accountedPersonIDs == [person])
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"escape",target:person,value:route.exitPortalID)])}
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try restored.query(library:SimFixtures.library)==accounted)
    }
    @Test func thermalChoicesChangeComputedTrendsAndKeepHeatPowerInitiallyAvailable()throws {
        for hazard in ["freeze-power-loss","heat-grid-strain"] {
            var baseline=try session(hazard),protected=baseline
            let start=try baseline.query(library:SimFixtures.library)
            #expect(start.snapshot.services[Svc.grid] == .operational)
            let event=SimFixtures.library.scenario(hazard)!.events.first{$0.rule==RuleID.setExternal && $0.params["service"]==Svc.grid && $0.params["state"]=="unavailable"}!
            let commands:[SessionCommand]=[.init(kind:"schedule",target:event.id,minute:0),.init(kind:"advance",minute:0)]
            _=try act(&baseline,commands,actor:"director");_=try act(&protected,commands,actor:"director")
            if hazard=="freeze-power-loss" {_=try act(&protected,[.init(kind:"warmLayers")])}
            else {
                let room=protected.initial.home!.portals.first{$0.kind == .window}!.sideA
                guard case .space(let roomID)=room else {throw SessionError.invalidCommand}
                _=try act(&protected,[.init(kind:"reduceSolarGain",target:roomID)])
            }
            let a=try act(&baseline,[.init(kind:"advance",minute:180)],actor:"director")
            let b=try act(&protected,[.init(kind:"advance",minute:180)],actor:"director")
            #expect(a.experience?.temperature != b.experience?.temperature)
            let relocated=try act(&protected,[.init(kind:hazard=="freeze-power-loss" ? "heatedAlternative":"cooledAlternative",target:"alternative")])
            #expect(relocated.experience?.relocated == true)
            let stable=try act(&protected,[.init(kind:"advance",minute:240)],actor:"director")
            #expect(stable.experience?.temperature == relocated.experience?.temperature)
        }
    }
    @Test func waterUseConservesVolumeAndChemicalAdvisoryCannotBeBoiledAway()throws {
        var s=try session("water-outage")
        let before=try s.query(library:SimFixtures.library)
        let after=try act(&s,[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:1)])
        #expect(abs((before.experience!.availableWaterGallons!-after.experience!.availableWaterGallons!)*3.785411784-1)<1e-8)
        let remaining=try act(&s,[.init(kind:"useWater",target:"recordedStored",value:"hygiene",quantityLiters:2)])
        #expect(remaining.experience!.availableWaterGallons!<after.experience!.availableWaterGallons!)
        var input=s.initial;input.variants=["do-not-use"]
        var chemical=try SimulationSession.initialize(id:"chemical",initial:input,library:SimFixtures.library)
        _=try act(&chemical,[.init(kind:"schedule",target:"evt.water-outage.do-not-use",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        for activity in ["drink","boiledDrink","hygiene"] {
            #expect(throws:SessionError.invalidCommand){try act(&chemical,[.init(kind:"useWater",target:"tap",value:activity,quantityLiters:1)])}
        }
        #expect(try chemical.query(library:SimFixtures.library).snapshot.services[Svc.grid] == .operational)
        #expect(try chemical.query(library:SimFixtures.library).snapshot.spatialState == nil)
    }
    @Test func selectedHazardSurvivesFallbackAndPersistenceFailure()throws {
        for scenario in SimFixtures.library.scenarios {
            var s=try session(scenario.id)
            let before=try s.query(library:SimFixtures.library)
            let fallback=try s.fallback(library:SimFixtures.library)
            #expect(throws:SessionError.persistence){try s.commit(fallback,library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
            #expect(try s.query(library:SimFixtures.library)==before)
            let after=try s.commit(fallback,library:SimFixtures.library)
            #expect(after.experience?.hazard==scenario.hazard)
            #expect(after.snapshot.spatialState?.hazard==nil || after.snapshot.spatialState?.hazard==scenario.hazard)
            if [.homeFire,.tornado,.flashFlood,.waterOutage].contains(scenario.hazard) {#expect(after.snapshot.services[Svc.grid] == .operational)}
        }
    }
}

extension SixHazardExperienceTests {
    @Test func tornadoArrivalAndAccessVariantAreComputed()throws {
        var s=try session("tornado")
        let warning=SimFixtures.library.scenario("tornado")!.events.first{$0.rule==RuleID.tornadoWarning}!
        _=try act(&s,[.init(kind:"schedule",target:warning.id,minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let shelter=try #require(ShelterSuitability.confirmedRoom(in:s.initial.home!))
        let person=s.initial.household.people[0].id
        let arrived=try act(&s,[.init(kind:"reachShelter",target:person,value:shelter.id)])
        #expect(arrived.experience?.shelteredPersonIDs.contains(person)==true)
        #expect(arrived.experience?.outsidePersonIDs.isEmpty==true)
        let other=s.initial.household.people[1].id
        #expect(arrived.experience?.shelteredPersonIDs.contains(other)==false)
        let together=try act(&s,[.init(kind:"reachShelter",target:other,value:shelter.id)])
        #expect(together.experience?.shelteredPersonIDs.count==2)
        var input=s.initial;input.household.housing.homeType = .manufacturedHome
        var variant=try SimulationSession.initialize(id:"manufactured",initial:input,library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try act(&variant,[.init(kind:"reachShelter",target:person,value:shelter.id)])}
    }
    @Test func floodEarlyDepartureDiffersFromLostAccessAndNoTransport()throws {
        var early=try session("flash-flood"),late=early
        let departed=try act(&early,[.init(kind:"leaveEarly",target:"alternative")])
        #expect(departed.experience?.relocated==true)
        #expect(departed.experience?.feasibleCommands?.isEmpty==true)
        #expect(departed.experience?.openGapIDs.isEmpty==true)
        #expect(departed.experience?.debrief.contains{$0.kind=="earlyDepartureUsed"}==true)
        #expect(departed.experience?.debrief.contains{$0.kind=="noSupportedRefugeApproach"}==false)
        #expect(throws:SessionError.invalidCommand){try act(&early,[.init(kind:"leaveEarly",target:"alternative")])}
        let closed = try #require(SimFixtures.library.scenario("flash-flood")?.events.first { $0.params["service"] == Svc.roads && $0.params["state"] == "unavailable" })
        _=try act(&late,[.init(kind:"schedule",target:"evt.flash-flood.warning",minute:0),.init(kind:"schedule",target:closed.id,minute:1),.init(kind:"advance",minute:1)],actor:"director")
        #expect(throws:SessionError.invalidCommand){try act(&late,[.init(kind:"leaveEarly",target:"alternative")])}
        var input=early.initial;input.household.transport.vehicles=[]
        var noCar=try SimulationSession.initialize(id:"no-car",initial:input,library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try act(&noCar,[.init(kind:"leaveEarly",target:"alternative")])}
        #expect(try noCar.query(library:SimFixtures.library).experience?.shelteredPersonIDs.isEmpty==true)
    }
}

extension SixHazardExperienceTests {
    @Test func accompanimentComputesHelperApproachAndBothShelterArrivalsWithoutTeleporting()throws {
        var s=try session("tornado")
        let child=s.initial.household.people[2],helper=try #require(child.helperPersonID)
        let receipt=try act(&s,[.init(kind:"accompanyShelter",target:child.id,value:helper)])
        #expect(receipt.experience?.shelteredPersonIDs.contains(child.id)==true)
        #expect(receipt.experience?.shelteredPersonIDs.contains(helper)==true)
        var input=s.initial
        let helperIndex=try #require(input.household.people.firstIndex{$0.id==helper})
        input.household.people[helperIndex].sleepingSpaceID="missing-room"
        var blocked=try SimulationSession.initialize(id:"unreachable-helper",initial:input,library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try act(&blocked,[.init(kind:"accompanyShelter",target:child.id,value:helper)])}
    }
}

extension SixHazardExperienceTests {
    @Test func debriefFactsFollowActualConditioningAndWaterActions()throws {
        var water=try session("water-outage")
        let baseline=try water.query(library:SimFixtures.library)
        #expect(baseline.experience?.debrief.contains{$0.kind=="storedWaterActivityDebited"}==false)
        let used=try act(&water,[.init(kind:"useWater",target:"recordedStored",value:"drink",quantityLiters:0.25)])
        #expect(used.experience?.debrief.contains{$0.kind=="storedWaterActivityDebited"}==true)
        #expect(used.experience?.debrief.contains{$0.kind=="recordedWarmthUsed"}==false)
        var freeze=try session("freeze-power-loss")
        let powered=try freeze.query(library:SimFixtures.library)
        #expect(powered.experience?.debrief.contains{$0.kind=="conditioningAvailable"}==true)
        _=try act(&freeze,[.init(kind:"schedule",target:"evt.freeze-power-loss.grid-loss",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let layers=try act(&freeze,[.init(kind:"warmLayers")])
        #expect(layers.experience?.debrief.contains{$0.kind=="conditioningUnavailable"}==true)
        #expect(layers.experience?.debrief.contains{$0.kind=="recordedWarmthUsed"}==true)
        #expect(layers.experience?.debrief.contains{$0.kind=="storedWaterActivityDebited"}==false)
    }
}

extension SixHazardExperienceTests {
    func heatRooms(_ receipt:SessionReceipt)throws->[String:[String:Any]] {
        let json=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(receipt)) as! [String:Any]
        let experience=try #require(json["experience"] as? [String:Any])
        return try #require(experience["roomTemperatures"] as? [String:[String:Any]])
    }
    @Test func v2HeatShadingIsRoomScopedAndComposedSelectionsPersist()throws {
        var a=try session("heat-grid-strain"),b=a
        let shadeA="sp-living",shadeB="sp-bed1"
        _=try act(&a,[.init(kind:"reduceSolarGain",target:shadeA)])
        _=try act(&b,[.init(kind:"reduceSolarGain",target:shadeB)])
        let outage:[SessionCommand]=[.init(kind:"schedule",target:"evt.heat-grid-strain.rotating-outage",minute:0),.init(kind:"advance",minute:120)]
        let ra=try act(&a,outage,actor:"director"),rb=try act(&b,outage,actor:"director")
        let roomsA=try heatRooms(ra),roomsB=try heatRooms(rb)
        #expect((roomsA[shadeA]!["upperC"] as! Double)<(roomsB[shadeA]!["upperC"] as! Double))
        #expect((roomsB[shadeB]!["upperC"] as! Double)<(roomsA[shadeB]!["upperC"] as! Double))
        let both=try act(&a,[.init(kind:"reduceSolarGain",target:shadeB)])
        let json=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(both)) as! [String:Any]
        let experience=json["experience"] as! [String:Any]
        #expect(experience["shadedRoomIDs"] as? [String] == [shadeB,shadeA].sorted())
        // A selection changes future drift, never retroactively cools a room.
        let selectedRooms=try heatRooms(both)
        #expect(selectedRooms[shadeB]!["upperC"] as! Double == roomsA[shadeB]!["upperC"] as! Double)
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(a))
        #expect(try restored.query(library:SimFixtures.library)==both)
        #expect(throws:SessionError.invalidCommand){try act(&a,[.init(kind:"reduceSolarGain",target:shadeA)])}
    }
    @Test func v2HeatReducedCoolingDiffersFromFullLossAndFactsStayQualified()throws {
        var reduced=try session("heat-grid-strain"),lost=reduced
        let reducedReceipt=try act(&reduced,[.init(kind:"schedule",target:"evt.heat-grid-strain.grid-strain",minute:0),.init(kind:"advance",minute:120)],actor:"director")
        let lostReceipt=try act(&lost,[.init(kind:"schedule",target:"evt.heat-grid-strain.rotating-outage",minute:0),.init(kind:"advance",minute:120)],actor:"director")
        #expect(reducedReceipt.snapshot.services[Svc.grid] == .degraded)
        #expect(reducedReceipt.snapshot.services[Svc.cooling] == .degraded)
        #expect(reducedReceipt.experience?.debrief.contains{$0.kind=="conditioningReduced"}==true)
        #expect(reducedReceipt.experience?.debrief.contains{$0.kind=="conditioningUnavailable"}==false)
        #expect(reducedReceipt.experience!.temperature!.upperC<lostReceipt.experience!.temperature!.upperC)
    }
}

extension SixHazardExperienceTests {
    @Test func v2UnknownCoolingRemainsUnknownInsteadOfBecomingAnOutage()throws {
        var input=try session("heat-grid-strain").initial
        input.household.housing.cooling = .unknown
        var unknown=try SimulationSession.initialize(id:"unknown-cooling",initial:input,library:SimFixtures.library)
        let receipt=try act(&unknown,[.init(kind:"advance",minute:120)],actor:"director")
        #expect(receipt.snapshot.services[Svc.cooling] == .unknown)
        #expect(receipt.experience?.conditioningService == .unknown)
        #expect(receipt.experience?.debrief.contains{$0.kind=="conditioningUnknown"}==true)
        #expect(receipt.experience?.debrief.contains{$0.kind=="conditioningUnavailable"}==false)
        let ranges=try heatRooms(receipt)
        for range in ranges.values {
            #expect(range["lowerC"] as? Double == 27)
            #expect(range["upperC"] as? Double == 31)
        }
    }
}
extension SixHazardExperienceTests {
    @Test func v2PortableACDoesNotManufactureCoolingCoverageForEveryRoom()throws {
        var input=try session("heat-grid-strain").initial
        input.household.housing.cooling = .windowOrPortableAC
        var localized=try SimulationSession.initialize(id:"localized-cooling",initial:input,library:SimFixtures.library)
        let receipt=try act(&localized,[.init(kind:"advance",minute:120)],actor:"director")
        #expect(receipt.snapshot.services[Svc.cooling] == .operational)
        #expect(receipt.experience?.roomCoolingCoverageUnknown==true)
        #expect(receipt.experience?.openGapIDs.contains("roomCoolingCoverage")==true)
        let ranges=try heatRooms(receipt)
        for range in ranges.values {
            #expect(range["lowerC"] as? Double == 27)
            #expect(range["upperC"] as? Double == 31)
        }
        let later=try act(&localized,[.init(kind:"advance",minute:180)],actor:"director")
        #expect(later.experience?.roomTemperatures?.values.allSatisfy{$0.assumption.count<600}==true)
        #expect(later.experience?.debrief.contains{$0.kind=="conditioningUnavailable"}==false)
    }
}
extension SixHazardExperienceTests {
    @Test func recordedPowerGapCheckNamesTheActualUnknownWithoutDisconnectingOrConfirmingIt()throws {
        var s=try session("freeze-power-loss")
        let before=try s.query(library:SimFixtures.library)
        let gap="equipment.\(s.initial.household.equipment[0].id).backup"
        #expect(before.snapshot.unknowns.contains(gap))
        #expect(before.experience?.feasibleCommands?.contains{$0.kind=="identifyGap" && $0.target==gap}==true)
        let after=try act(&s,[.init(kind:"identifyGap",target:gap)])
        #expect(after.snapshot.resources==before.snapshot.resources)
        #expect(after.snapshot.services==before.snapshot.services)
        #expect(after.snapshot.unknowns.contains(gap))
        #expect(after.experience?.identifiedGapIDs.contains(gap)==true)
        #expect(after.experience?.debrief.contains{$0.kind=="recordedDependencyGapIdentified" && $0.subjectIDs==[gap] && $0.nextActionID=="prep.medicalBackup"}==true)
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"identifyGap",target:gap)])}
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"identifyGap",target:"equipment.invented.backup")])}
        let prior=SimulationSession(id:"v2-frozen",initial:s.initial,directorPolicy:s.directorPolicy,mechanicsVersion:"dryrun.hazard-mechanics/2")
        #expect(try prior.query(library:SimFixtures.library).experience?.openGapIDs.contains(gap)==false)
    }
}

extension SixHazardExperienceTests {
    @Test func lostCommitAcknowledgementReconcilesDurableStateWithoutRepeatingWaterUse() throws {
        var s=try session("water-outage")
        let command=try #require(s.query(library:SimFixtures.library).experience?.feasibleCommands?.first{$0.kind == "useWater"})
        let proposal=SessionCommit(id:"lost-water-ack",actor:"user",baseRevision:s.revision,commands:[command])
        #expect(try s.reconcileDurableCommit(proposal,library:SimFixtures.library).status == .absent)
        var durable:Data?
        let committed=try s.commit(proposal,library:SimFixtures.library,persist:{durable=try DryRunJSON.encoder().encode($0)})
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:#require(durable))
        let result=try restored.reconcileDurableCommit(proposal,library:SimFixtures.library)
        #expect(result.status == .committed)
        #expect(result.acceptedRevision == 1)
        #expect(result.current == committed)
        #expect(restored.commits.count == 1)
        var conflict=proposal;conflict.commands=[.init(kind:"unsupported")]
        #expect(throws:SessionError.duplicate){try restored.reconcileDurableCommit(conflict,library:SimFixtures.library)}
        #expect(throws:SessionError.duplicate){try s.commit(proposal,library:SimFixtures.library)}
        #expect(try s.query(library:SimFixtures.library) == committed)
    }
    @Test func failedDurableWriteNeverCreatesAReconciliationReceipt() throws {
        var s=try session("water-outage")
        let proposal=SessionCommit(id:"failed-write",actor:"user",baseRevision:0,commands:[.init(kind:"unsupported")])
        #expect(throws:SessionError.persistence){try s.commit(proposal,library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try s.reconcileDurableCommit(proposal,library:SimFixtures.library).status == .absent)
        #expect(s.commits.isEmpty)
    }
}
