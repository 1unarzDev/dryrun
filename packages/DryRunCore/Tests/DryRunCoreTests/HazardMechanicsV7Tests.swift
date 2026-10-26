import Foundation
import Testing
@testable import DryRunCore

/// Mechanics version 7 (freeze gathering, G1 opening) and the receipt device-name fallback chain.
/// v6 sessions keep their offered commands; v7 only adds a physical freeze choice that credits no warmth.
@Suite("Hazard mechanics v7 freeze opening and receipt names") struct HazardMechanicsV7Tests {
    let library=SimFixtures.library
    func start(_ input:RehearsalInput,version:String?=nil)throws->SimulationSession {
        if let version {
            return SimulationSession(id:"v-\(input.scenarioID)",initial:input,directorPolicy:.reviewed(library.scenario(input.scenarioID)!),mechanicsVersion:version)
        }
        return try SimulationSession.initialize(id:"v7-\(input.scenarioID)",initial:input,library:library)
    }
    static let physical:Set<String>=["warmLayers","moveTo","allocatePower"]
    func isPhysical(_ c:SessionCommand)->Bool {Self.physical.contains(c.kind) && !(c.kind=="allocatePower" && c.value=="none")}
    /// Local director's first commit (the opening key moment), as the app runs it.
    func opening(_ s:inout SimulationSession)throws->SessionReceipt {
        let first=try #require(LocalDirector.nextCommit(session:s,receipt:try s.query(library:library),library:library))
        return try s.commit(first,library:library)
    }

    @Test func newSessionsUseV7AndV6StaysSupported() throws {
        #expect(HazardExperience.version=="dryrun.hazard-mechanics/7")
        #expect(HazardExperience.supportedVersions.contains("dryrun.hazard-mechanics/6"))
        #expect(HazardExperience.level(HazardExperience.version)==7)
        let s=try start(SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss"))
        #expect(s.mechanicsVersion=="dryrun.hazard-mechanics/7")
    }

    /// Unedited sample households (no recorded warmth, no compatible backup) in every sample layout: the v7 freeze
    /// opening offers at least one physical command, the local director asks the opening decision, and the same
    /// v6 session offers no such command and is not asked.
    @Test func freezeOpeningOffersAPhysicalChoiceForEverySampleHousehold() throws {
        var covered=0
        for household in SampleHouseholds.all {
            for home in [SampleHomes.ranch,SampleHomes.apartment,SampleHomes.twoStory] {
                let input=SimFixtures.input(household,"freeze-power-loss",home:home)
                var current=try start(input)
                let r=try opening(&current)
                #expect(r.snapshot.services[Svc.homePower] == .operational)
                let physical=(r.experience?.feasibleCommands ?? []).filter(isPhysical)
                guard household.people.contains(where:{home.space($0.sleepingSpaceID ?? "") != nil}) else {continue}
                #expect(!physical.isEmpty,"\(household.id) in \(home.id) has a physical freeze opening choice")
                #expect(r.experience?.supportedActions.contains("moveTo")==true)
                let ask=LocalDirector.nextCommit(session:current,receipt:r,library:library)
                #expect(ask?.commands==[.init(kind:"requestDecision")],"\(household.id) in \(home.id) is asked before the outage")
                // Every gathering choice is described for the native card, with a recorded room.
                let gathers=HazardChoices.options(r,household:input.household,home:input.home).filter{$0.purpose == .gather}
                #expect(gathers.count==physical.filter{$0.kind=="moveTo"}.count)
                for g in gathers {#expect(g.personID != nil && g.roomID.flatMap{home.space($0)} != nil)}
                // v6: same input, no gathering command and no opening decision.
                var old=try start(input,version:"dryrun.hazard-mechanics/6")
                let o=try opening(&old)
                let oldPhysical=(o.experience?.feasibleCommands ?? []).filter(isPhysical)
                #expect(oldPhysical.isEmpty)
                let oldNext=LocalDirector.nextCommit(session:old,receipt:o,library:library)
                #expect(oldNext.map{$0.commands != [SessionCommand(kind:"requestDecision")]} ?? true)
                covered += 1
            }
        }
        #expect(covered>=3)
    }

    /// Oak in the ranch: everyone else gathers in Grandpa's (cold-sensitive) room. The move commits through the
    /// route owner, the choice retires for that person, and no warmth is credited: the temperature after the grid
    /// loss matches the "keep watching" branch under the same schedule.
    @Test func gatheringMovesPeopleWithoutWarmthCredit() throws {
        let input=SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss")
        let anchor=try #require(input.household.people.first{$0.needs.contains(.coldSensitive)})
        let room=try #require(anchor.sleepingSpaceID)
        let base=try start(input)
        let schedule:[SessionCommand]=[.init(kind:"schedule",target:"evt.freeze-power-loss.cold-arrives",minute:0),.init(kind:"advance",minute:0),.init(kind:"requestDecision")]
        var gathered=base,waited=base
        _=try gathered.commit(.init(id:"d0",actor:"director",baseRevision:0,commands:schedule),library:library)
        let asked=try waited.commit(.init(id:"d0",actor:"director",baseRevision:0,commands:schedule),library:library)
        let moves=(asked.experience?.feasibleCommands ?? []).filter{$0.kind=="moveTo"}
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy{$0.value==room && $0.target != anchor.id})
        var after=asked
        for move in moves {
            after=try gathered.commit(.init(id:"u\(gathered.revision)",actor:"user",baseRevision:gathered.revision,commands:[move]),library:library)
            #expect(after.experience?.occupantRoomIDs[move.target!]==room)
        }
        #expect((after.experience?.feasibleCommands ?? []).contains{$0.kind=="moveTo"}==false)
        _=try waited.commit(.init(id:"u1",actor:"user",baseRevision:waited.revision,commands:[.init(kind:"wait")]),library:library)
        let outage:[SessionCommand]=[.init(kind:"schedule",target:"evt.freeze-power-loss.grid-loss",minute:180),.init(kind:"advance",minute:420)]
        let g=try gathered.commit(.init(id:"d\(gathered.revision)",actor:"director",baseRevision:gathered.revision,commands:outage),library:library)
        let w=try waited.commit(.init(id:"d\(waited.revision)",actor:"director",baseRevision:waited.revision,commands:outage),library:library)
        #expect(g.experience?.temperature==w.experience?.temperature)
        #expect(g.experience?.selectedProtection==nil)
        // Restored sessions reproduce the same receipt.
        let restored=try JSONDecoder().decode(SimulationSession.self,from:JSONEncoder().encode(gathered))
        #expect(try restored.query(library:library)==g)
    }

    /// No person with a recorded cold sensitivity or mobility need: nothing to gather around, so nothing is offered.
    @Test func noGatheringAnchorOffersNoMove() throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"freeze-power-loss")
        input.household.people=input.household.people.map{var p=$0;p.needs=[];return p}
        var s=try start(input)
        let r=try opening(&s)
        #expect((r.experience?.feasibleCommands ?? []).contains{$0.kind=="moveTo"}==false)
    }

    // MARK: Receipt device names

    func localizer()throws->Localizer {
        let content=try ContentLibrary.load(from:LeadTestSupport.contentRoot)
        return Localizer(locale:"en",tables:content.tables,manifest:content.localeManifest)
    }

    @Test func receiptNamesFallBackFromCustomToLegacyToLocalizedPurpose() throws {
        let l=try localizer()
        // Sample Oak: the default English label was cleared on creation and kept as the legacy label.
        var device=SampleHouseholds.oak.equipment[0]
        #expect(device.label.isEmpty)
        #expect(device.receiptName(l)=="Oxygen concentrator")
        device.label="Grandpa's O2 machine"
        #expect(device.receiptName(l)=="Grandpa's O2 machine")
        device.label="  ";device.legacyOriginalLabel=nil
        #expect(device.receiptName(l)==l("equipment.oxygenConcentrator"))
        #expect(!device.receiptName(l).trimmingCharacters(in:.whitespaces).isEmpty)
        var backup=SampleHouseholds.oak.backupPower[0]
        #expect(backup.receiptName(l)=="Portable battery station")
        backup.legacyOriginalLabel=nil
        #expect(backup.receiptName(l)==l("enum.portableBatteryStation"))
        backup.label="Garage battery"
        #expect(backup.receiptName(l)=="Garage battery")
    }

    /// Every device/backup event of an Oak freeze run gets a non-blank receipt title naming the device, including
    /// a device event that carries only its service change (no equipment fact).
    @Test func freezeReceiptTitlesNameTheDevice() throws {
        let l=try localizer()
        var household=SampleHouseholds.oak
        household.equipment[0].compatibleBackupIDs=["bk-station"]
        let result=try SimFixtures.run(household,"freeze-power-loss")
        let deviceEvents=result.events.filter{$0.templateValues["device"] != nil}
        #expect(!deviceEvents.isEmpty)
        for event in deviceEvents {
            #expect(event.templateValues["device"]?.isEmpty==true,"engine values keep the stored (blank) label")
            let title=event.receiptTitle(household:household,localizer:l)
            #expect(title.contains("Oxygen concentrator"),"\(event.titleKey)")
        }
        for event in result.events where event.templateValues["backup"] != nil {
            #expect(event.receiptTitle(household:household,localizer:l).contains("Portable battery station"))
        }
        var bare=try #require(deviceEvents.first)
        bare.evidence.factIDs=[]
        bare.serviceChanges=[Svc.device("eq-oxygen"):.unavailable]
        #expect(bare.localizedTemplateValues(household:household,localizer:l)["device"]=="Oxygen concentrator")
        household.equipment[0].label="Grandpa's O2 machine"
        #expect(bare.receiptTitle(household:household,localizer:l).contains("Grandpa's O2 machine"))
    }
}
