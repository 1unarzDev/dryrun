import Foundation
import Testing
@testable import DryRunCore

/// Mechanics version 6 and the native hazard-choice contract. Paired branches hold the initial snapshot and the
/// director schedule fixed and vary only household commits; v5 sessions keep replaying unchanged.
@Suite("Hazard mechanics v6 and native hazard choices") struct HazardMechanicsV6Tests {
    let library=SimFixtures.library
    func start(_ input:RehearsalInput,version:String?=nil)throws->SimulationSession {
        if let version {
            return SimulationSession(id:"v-\(input.scenarioID)",initial:input,directorPolicy:.reviewed(library.scenario(input.scenarioID)!),mechanicsVersion:version)
        }
        return try SimulationSession.initialize(id:"v6-\(input.scenarioID)",initial:input,library:library)
    }
    @discardableResult func act(_ s:inout SimulationSession,_ commands:[SessionCommand],actor:String="user")throws->SessionReceipt {
        try s.commit(.init(id:"step-\(s.revision)",actor:actor,baseRevision:s.revision,commands:commands),library:library)
    }
    func has(_ r:SessionReceipt,_ kind:String,_ subject:String?=nil)->Bool {
        (r.experience?.debrief ?? []).contains{$0.kind==kind && (subject==nil || $0.subjectIDs.contains(subject!))}
    }
    func authored(_ r:SessionReceipt)->[String] {
        let all=Set(library.scenarios.flatMap{$0.events.map(\.id)})
        return r.events.map(\.id).filter(all.contains)
    }

    @Test func versionLevelsAndNewSessionsUseV6() throws {
        #expect(HazardExperience.version=="dryrun.hazard-mechanics/6")
        #expect(HazardExperience.supportedVersions.contains("dryrun.hazard-mechanics/5"))
        #expect(HazardExperience.level("dryrun.hazard-mechanics/5")==5)
        #expect(HazardExperience.level(nil)==0)
        #expect(HazardExperience.level("other/9")==0)
        let s=try start(SimFixtures.input(SampleHouseholds.oak,"home-fire"))
        #expect(s.mechanicsVersion==HazardExperience.version)
        #expect(try s.query(library:library).experience?.mechanicsVersion==HazardExperience.version)
    }

    // MARK: G2 fire origin

    /// A director that starts the alarm with an explicit origin room: v6 routes never pass through that room
    /// and escape through it is not offered; the same v5 commits keep their historical routes.
    @Test func explicitFireOriginIsExcludedFromRoutesFromTheAlarm() throws {
        var compared=0
        for (home,household) in [(SampleHomes.ranch,SampleHouseholds.oak),(SampleHomes.twoStory,SampleHouseholds.oak),(SampleHomes.apartment,SampleHouseholds.lake),(SampleHomes.ranch,SampleHouseholds.pine)] {
            let input=SimFixtures.input(household,"home-fire",home:home)
            for origin in home.spaces.map(\.id) {
                let start=[SessionCommand(kind:"startIncident",target:"evt.home-fire.alarm",value:origin,minute:0,hazard:.homeFire),.init(kind:"advance",minute:0)]
                var old=try self.start(input,version:"dryrun.hazard-mechanics/5"),current=try self.start(input)
                let o=try act(&old,start,actor:"director"),c=try act(&current,start,actor:"director")
                // Through the origin in v5 for someone who does not start there.
                let crossing=o.routes.filter{route in
                    route.request.startSpaceID != origin && route.primary?.spaceSequence.contains(origin)==true
                }
                guard !crossing.isEmpty else {continue}
                compared += 1
                #expect(c.snapshot.spatialState?.affectedSpaceIDs.contains(origin)==true)
                #expect(c.snapshot.spatialState?.originSpaceID==origin)
                #expect(has(c,"fireOriginExcludedFromRoutes",origin))
                #expect(!has(o,"fireOriginExcludedFromRoutes"))
                for route in c.routes where route.request.startSpaceID != origin {
                    #expect(route.primary?.spaceSequence.contains(origin) != true)
                }
                // Every offered escape is consistent with the exclusion: previewing it never routes through the origin.
                for command in c.experience?.feasibleCommands?.filter({$0.kind=="escape"}) ?? [] {
                    var probe=current
                    let after=try act(&probe,[command])
                    let route=after.routes.first{$0.request.personID==command.target}
                    #expect(route?.primary?.spaceSequence.dropFirst().contains(origin) != true)
                }
                // The later fire-origin stage keeps the same origin rather than searching for a new one.
                let later=try act(&current,[.init(kind:"advanceIncident",target:"evt.home-fire.fire-origin",minute:1,hazard:.homeFire),.init(kind:"advance",minute:1)],actor:"director")
                #expect(later.snapshot.spatialState?.originSpaceID==origin)
                #expect(later.snapshot.unknowns.contains{$0.hasPrefix("home.fireOrigin.")}==false)
            }
        }
        #expect(compared>=1)
    }

    // MARK: G1 freeze opening, wait and outage readiness

    func freezeInput()->RehearsalInput {
        var input=SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss")
        input.household.equipment[0].compatibleBackupIDs=["bk-station"]
        input.household.equipment[0].powerWatts = .confirmed(120,unit:"W")
        input.household.preparedness=PreparednessRecord(items:["warmth":PreparationFact(available:.confirmed(true))])
        input.household.backupPower[0].setupConfirmed = .confirmed(true)
        return input
    }

    /// The local director asks the family once, before the outage, when a preparation is supported.
    @Test func freezeOpeningAsksBeforeTheScheduledGridLoss() throws {
        var s=try start(freezeInput())
        let first=try #require(LocalDirector.nextCommit(session:s,receipt:try s.query(library:library),library:library))
        let r1=try s.commit(first,library:library)
        #expect(r1.snapshot.simMinute==0)
        #expect(r1.snapshot.services[Svc.homePower] == .operational)
        let opening=try #require(LocalDirector.nextCommit(session:s,receipt:r1,library:library))
        #expect(opening.commands==[.init(kind:"requestDecision")])
        let asked=try s.commit(opening,library:library)
        #expect(asked.directorState?.awaitingUserAction==true)
        #expect(LocalDirector.dueChoice(session:s,receipt:asked,library:library)==nil)
        #expect(HazardChoices.waitAvailable(session:s,receipt:asked,library:library))
        let options=HazardChoices.options(asked,household:s.initial.household,home:s.initial.home)
        #expect(options.contains{$0.purpose == .warmth})
        #expect(options.contains{$0.purpose == .power && $0.equipmentID=="eq-oxygen" && $0.backupID=="bk-station"})
        // Not asked again after the family acts, and never on v5 sessions or without a supported preparation.
        var after=s
        let waited=try act(&after,[.init(kind:"wait")])
        #expect(LocalDirector.nextCommit(session:after,receipt:waited,library:library)?.commands != [.init(kind:"requestDecision")])
        var bare=SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss");bare.household.equipment=[];bare.household.preparedness=nil
        var none=try start(bare)
        let n1=try none.commit(LocalDirector.nextCommit(session:none,receipt:try none.query(library:library),library:library)!,library:library)
        #expect(LocalDirector.nextCommit(session:none,receipt:n1,library:library)?.commands != [.init(kind:"requestDecision")])
        var v5=try start(freezeInput(),version:"dryrun.hazard-mechanics/5")
        let v1=try v5.commit(LocalDirector.nextCommit(session:v5,receipt:try v5.query(library:library),library:library)!,library:library)
        #expect(LocalDirector.nextCommit(session:v5,receipt:v1,library:library)?.commands != [.init(kind:"requestDecision")])
    }

    /// Paired opening decisions under one schedule: prepare (warmth + backup) versus keep watching (wait) versus
    /// disconnect. What was in place at the grid loss, device service and temperature all differ.
    @Test func freezePreparedVersusWaitingChangesOutageRecordServiceAndTemperature() throws {
        let base=try start(freezeInput())
        let opening:[SessionCommand]=[.init(kind:"schedule",target:"evt.freeze-power-loss.cold-arrives",minute:0),.init(kind:"advance",minute:0),.init(kind:"requestDecision")]
        let outage:[SessionCommand]=[.init(kind:"schedule",target:"evt.freeze-power-loss.grid-loss",minute:180),.init(kind:"advance",minute:180)]
        let later:[SessionCommand]=[.init(kind:"advance",minute:420)]
        var prepared=base,waited=base,unpowered=base
        _=try act(&prepared,opening,actor:"director");_=try act(&waited,opening,actor:"director");_=try act(&unpowered,opening,actor:"director")
        _=try act(&prepared,[.init(kind:"warmLayers"),.init(kind:"allocatePower",target:"eq-oxygen",value:"bk-station")])
        _=try act(&waited,[.init(kind:"wait")])
        _=try act(&unpowered,[.init(kind:"allocatePower",target:"eq-oxygen",value:"none")])
        let p=try act(&prepared,outage,actor:"director"),w=try act(&waited,outage,actor:"director"),u=try act(&unpowered,outage,actor:"director")
        #expect(authored(p)==authored(w) && authored(w)==authored(u))
        #expect(has(p,"outageBeganWithRecordedProtection"))
        #expect(has(w,"outageBeganWithoutRecordedProtection","p-oak-4"))
        #expect(has(p,"outageBeganWithBackupAssigned","eq-oxygen"))
        #expect(has(w,"outageBeganWithBackupAssigned","eq-oxygen"))
        #expect(has(u,"outageBeganWithoutBackupAssigned","eq-oxygen"))
        #expect((u.experience?.debrief.first{$0.kind=="outageBeganWithoutBackupAssigned"}?.nextActionID)=="prep.medicalBackup")
        #expect(has(w,"action.wait"))
        let p2=try act(&prepared,later,actor:"director"),u2=try act(&unpowered,later,actor:"director"),w2=try act(&waited,later,actor:"director")
        #expect(p2.snapshot.services[Svc.device("eq-oxygen")] == .operational)
        #expect(u2.snapshot.services[Svc.device("eq-oxygen")] != .operational)
        #expect(p2.experience!.temperature!.lowerC>w2.experience!.temperature!.lowerC)
        // The outage record is fixed at the boundary: a later warmth choice does not rewrite it.
        let late=try act(&waited,[.init(kind:"warmLayers")])
        #expect(has(late,"outageBeganWithoutRecordedProtection"))
        #expect(!has(late,"outageBeganWithRecordedProtection"))
        // Restored sessions reproduce the same record.
        let restored=try JSONDecoder().decode(SimulationSession.self,from:JSONEncoder().encode(waited))
        #expect(try restored.query(library:library)==late)
    }

    @Test func waitIsAVersionSixDecisionOnly() throws {
        var current=try start(SimFixtures.input(SampleHouseholds.lake,"heat-grid-strain"))
        let r=try act(&current,[.init(kind:"wait")])
        #expect(has(r,"action.wait"))
        #expect(throws:SessionError.invalidCommand){var c=current;try act(&c,[.init(kind:"wait",target:"x")])}
        var old=try start(SimFixtures.input(SampleHouseholds.lake,"heat-grid-strain"),version:"dryrun.hazard-mechanics/5")
        #expect(throws:SessionError.invalidCommand){try act(&old,[.init(kind:"wait")])}
        var authored=SimulationSession(id:"authored",initial:SimFixtures.input(SampleHouseholds.lake,"heat-grid-strain"))
        #expect(throws:SessionError.invalidCommand){try act(&authored,[.init(kind:"wait")])}
    }

    // MARK: Native hazard-choice descriptions

    /// Every feasible hazard command is described with its person/purpose/destination, primary objective first.
    @Test func hazardChoicesDescribePersonPurposeAndDestination() throws {
        // Fire: escape choices name the exit's room; accompaniment names the helper.
        var fire=try start(SimFixtures.input(SampleHouseholds.oak,"home-fire"))
        let alarm=try act(&fire,[.init(kind:"schedule",target:"evt.home-fire.alarm",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let fireChoices=HazardChoices.options(alarm,household:fire.initial.household,home:fire.initial.home)
        let escapes=fireChoices.filter{$0.purpose == .escape}
        #expect(!escapes.isEmpty)
        for choice in escapes {
            #expect(choice.personID != nil && choice.exitPortalID != nil)
            #expect(choice.roomID.flatMap{fire.initial.home?.space($0)} != nil)
            #expect(choice.id=="escape.\(choice.personID!).\(choice.exitPortalID!)")
        }
        for choice in fireChoices where choice.purpose == .accompanyEscape {#expect(choice.helperID != nil && choice.helperID != choice.personID)}
        #expect(fireChoices.first.map{[.escape,.accompanyEscape].contains($0.purpose)}==true)
        #expect(fireChoices.allSatisfy{$0.command.kind != "assignHelper"})
        // Every feasible command except director-only kinds has a description.
        let described=Set(fireChoices.map(\.command))
        for command in alarm.experience?.feasibleCommands ?? [] {#expect(described.contains(command))}

        // Heat: shading a room adds a person-specific move into it for the heat-sensitive person.
        let home=SampleHomes.apartment
        let window=try #require(home.portals.filter{$0.kind == .window}.compactMap{portal->String? in
            for side in [portal.sideA,portal.sideB] {if case .space(let id)=side {return id}};return nil}.sorted().first)
        var lake=SimFixtures.input(SampleHouseholds.lake,"heat-grid-strain",home:home)
        lake.household.people=lake.household.people.map{var p=$0;p.sleepingSpaceID = p.id=="p-lake-1" ? (window=="sp-living" ? "sp-kitchen":"sp-living"):window;return p}
        var heat=try start(lake)
        let h0=try heat.query(library:library)
        let shade=try #require(HazardChoices.options(h0,household:lake.household,home:lake.home).first{$0.purpose == .shade && $0.roomID==window})
        let shaded=try act(&heat,[shade.command])
        let move=HazardChoices.options(shaded,household:lake.household,home:lake.home).filter{$0.purpose == .moveToShade}
        #expect(move.contains{$0.personID=="p-lake-1" && $0.roomID==shade.roomID})
        let moved=try act(&heat,[try #require(move.first{$0.personID=="p-lake-1"}).command])
        #expect(moved.experience?.occupantRoomIDs["p-lake-1"]==shade.roomID)
        #expect(HazardChoices.options(moved,household:lake.household,home:lake.home).contains{$0.purpose == .moveToShade && $0.personID=="p-lake-1"}==false)
        // A committed command can still be described after it is no longer offered.
        #expect(HazardChoices.describe(move[0].command,receipt:shaded,household:lake.household,home:lake.home)?.purpose == .moveToShade)

        // Water: activity and source are explicit.
        var water=try start(SimFixtures.input(SampleHouseholds.oak,"water-outage"))
        let w=try act(&water,[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let waterChoices=HazardChoices.options(w,household:water.initial.household,home:water.initial.home).filter{$0.purpose == .water}
        #expect(!waterChoices.isEmpty)
        #expect(waterChoices.allSatisfy{$0.activity != nil && $0.waterSource != nil && $0.quantityLiters != nil})
        #expect(waterChoices.contains{$0.waterSource=="tap"}==false) // well pump down: no tap use is offered
    }

    /// Tornado: shelter and accompaniment choices name the recorded shelter room; once everyone is there none remain.
    @Test func tornadoChoicesNameShelterAndRetireAfterArrival() throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"tornado")
        input.household.people=input.household.people.map{var p=$0;p.sleepingSpaceID="sp-bed1";return p}
        var s=try start(input)
        let warned=try act(&s,[.init(kind:"schedule",target:"evt.tornado.warning",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        let shelter=try #require(warned.experience?.shelterRoomID)
        let choices=HazardChoices.options(warned,household:input.household,home:input.home)
        #expect(choices.filter{$0.purpose == .shelter}.allSatisfy{$0.roomID==shelter})
        let accompany=try #require(choices.first{$0.purpose == .accompanyShelter && $0.personID=="p-oak-3"})
        #expect(accompany.helperID=="p-oak-1" && accompany.roomID==shelter)
        var r=try act(&s,[accompany.command])
        for choice in HazardChoices.options(r,household:input.household,home:input.home) where choice.purpose == .shelter {r=try act(&s,[choice.command])}
        #expect(Set(r.experience?.shelteredPersonIDs ?? [])==Set(input.household.people.map(\.id)))
        #expect(HazardChoices.options(r,household:input.household,home:input.home).contains{[.shelter,.accompanyShelter].contains($0.purpose)}==false)
    }
}
