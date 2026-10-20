import Foundation
import Testing
@testable import DryRunCore

@Suite("Flood higher-refuge action") struct FloodRefugeActionTests {
    func input(wheelchair:Bool=false,confirmed:Bool=true,blockedStairs:Bool=false)->RehearsalInput {
        var home=SampleHomes.twoStory
        for i in home.floors.indices {home.floors[i].exteriorGrade=home.floors[i].level==0 ? .ground:.aboveGround}
        home.spaces[home.spaces.firstIndex{$0.id=="sp-bed1"}!].higherRefugeConfirmed = confirmed ? .confirmed(true):.unknown
        if blockedStairs {home.connectors=[]}
        var h=SampleHouseholds.oak
        h.people=[Person(id:"resident",alias:"Synthetic resident",ageBand:.adult,needs:wheelchair ? [.usesWheelchair]:[],sleepingSpaceID:"sp-hall"),Person(id:"second",alias:"Synthetic second",ageBand:.adult,needs:[],sleepingSpaceID:"sp-hall")]
        h.equipment=[];h.backupPower=[]
        var input=SimFixtures.input(h,"flash-flood",home:home)
        input.spatialOptions = .init(floodAffectedSpaceIDs:["sp-living"],refugeSpaceID:"sp-bed1")
        return input
    }
    @discardableResult func act(_ s:inout SimulationSession,_ commands:[SessionCommand],actor:String="user")throws->SessionReceipt {
        try s.commit(.init(id:"step-\(s.revision)",actor:actor,baseRevision:s.revision,commands:commands),library:SimFixtures.library)
    }
    func warned(_ input:RehearsalInput)throws->SimulationSession {
        var s=try SimulationSession.initialize(id:"flood-refuge",initial:input,library:SimFixtures.library)
        try act(&s,[.init(kind:"schedule",target:"evt.flash-flood.warning",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        return s
    }
    @Test func followsOnlyTheComputedRefugeAndPersistsActualArrivalWithoutDepartureOrSafetyClaims()throws {
        var s=try warned(input())
        let before=try s.query(library:SimFixtures.library)
        let action=SessionCommand(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")
        #expect(before.experience?.refugeRoomID=="sp-bed1")
        #expect(before.experience?.refugedPersonIDs==[])
        #expect(before.experience?.feasibleCommands?.contains(action)==true)
        #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed2")])}
        let arrived=try act(&s,[action])
        #expect(arrived.experience?.occupantRoomIDs["resident"]=="sp-bed1")
        #expect(arrived.experience?.refugedPersonIDs==["resident"])
        #expect(arrived.experience?.relocated==false)
        #expect(arrived.experience?.debrief.contains{$0.kind=="recordedHigherRefugeArrival" && $0.subjectIDs.contains("resident")}==true)
        #expect(arrived.experience?.feasibleCommands?.contains(action)==false)
        #expect(throws:SessionError.invalidCommand){try act(&s,[action])}
        let decoded=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(s))
        #expect(try decoded.query(library:SimFixtures.library)==arrived)
    }
    @Test func noTeleportationOrInventedRefugeAcrossAccessAndEvidenceVariants()throws {
        for input in [input(wheelchair:true),input(confirmed:false),input(blockedStairs:true)] {
            var s=try warned(input)
            let before=try s.query(library:SimFixtures.library)
            #expect(before.experience?.feasibleCommands?.contains{$0.kind=="reachHigherRefuge" && $0.target=="resident"}==false)
            #expect(before.experience?.openGapIDs.contains("higherRefuge.resident")==true)
            #expect(before.experience?.debrief.contains{$0.kind=="noSupportedRefugeApproach" && $0.subjectIDs.contains("resident")}==true)
            #expect(throws:SessionError.invalidCommand){try act(&s,[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")])}
            #expect(try s.query(library:SimFixtures.library)==before)
        }
        var unobserved=try SimulationSession.initialize(id:"before-warning",initial:input(),library:SimFixtures.library)
        #expect(throws:SessionError.invalidCommand){try act(&unobserved,[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")])}
        var old=SimulationSession(id:"historical",initial:input(),directorPolicy:.reviewed(SimFixtures.library.scenario("flash-flood")!),mechanicsVersion:"dryrun.hazard-mechanics/3")
        try act(&old,[.init(kind:"schedule",target:"evt.flash-flood.warning",minute:0),.init(kind:"advance",minute:0)],actor:"director")
        #expect(throws:SessionError.invalidCommand){try act(&old,[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")])}
        #expect(try old.query(library:SimFixtures.library).experience?.refugeRoomID==nil)
    }
    @Test func persistenceFailureDoesNotMoveAnyoneOrRetireTheirAction()throws {
        var s=try warned(input());let before=s
        #expect(throws:SessionError.persistence){try s.commit(.init(id:"save-fails",actor:"user",baseRevision:s.revision,commands:[.init(kind:"reachHigherRefuge",target:"resident",value:"sp-bed1")]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try s.query(library:SimFixtures.library)==before.query(library:SimFixtures.library))
    }
}
