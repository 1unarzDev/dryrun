import Foundation
import Testing
@testable import DryRunCore

@Suite("Versioned household evidence assessment") struct HouseholdAssessmentTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func facts(_ h:HouseholdProfile,home:HomeModel?=nil,inventory:InventoryLedger?=nil)throws->[CriterionAssessment] {
        try HouseholdAssessment.assess(household:h,home:home,inventory:inventory,at:date)
    }
    func predicate(_ values:[CriterionAssessment],_ id:String,_ key:String)->Bool? {values.first{$0.criterionID==id}?.predicates[key]}
    @Test func absentStartAndDisconnectedGeometryRemainUnknown()throws {
        var h=SampleHouseholds.oak
        for i in h.people.indices {h.people[i].sleepingSpaceID=nil}
        let missing=try facts(h,home:SimFixtures.home)
        #expect(predicate(missing,"escape","confirmedExit")==nil)
        #expect(predicate(missing,"escape","independentAlternative")==nil)
        var home=SimFixtures.home;home.portals=[];home.connectors=[]
        let disconnected=try facts(SampleHouseholds.oak,home:home)
        #expect(predicate(disconnected,"escape","confirmedExit")==nil)
        #expect(predicate(disconnected,"escape","independentAlternative")==nil)
        #expect(disconnected.allSatisfy{$0.assessmentVersion==HouseholdAssessment.version})
    }
    @Test func availableButUnverifiedPathCannotEarnConfirmedCredit()throws {
        var h=SampleHouseholds.oak
        h.people=[Person(id:"resident",alias:"A",ageBand:.adult,sleepingSpaceID:"sp-living")]
        var home=SimFixtures.home
        for i in home.portals.indices {home.portals[i].clearWidthMeters = .unknown}
        let route=EgressPlanner().plan(RouteRequest(personID:"resident",startSpaceID:"sp-living",mobility:.walking),in:home)
        let path=try #require(route.primary)
        #expect(!path.verificationNeeded.isEmpty)
        let assessed=try facts(h,home:home)
        #expect(predicate(assessed,"escape","confirmedExit")==nil)
        #expect(predicate(assessed,"escape","independentAlternative")==nil)
    }
    @Test func shelterUsesConfirmedInteriorObjectiveAndActualRoutes()throws {
        var h=SampleHouseholds.oak
        h.people=[Person(id:"resident",alias:"A",ageBand:.adult,sleepingSpaceID:"sp-living")]
        var original=SimFixtures.home
        let index=try #require(original.spaces.firstIndex{$0.id=="sp-closet"})
        original.spaces[index].interiorNoWindowsConfirmed = .unknown
        #expect(predicate(try facts(h,home:original),"shelter","suitable")==nil)
        let reviewed=HomeConfirmation.apply(.shelterSpot(spaceID:"sp-closet",interiorNoWindows:true),to:original,at:date)
        #expect(reviewed.revision>original.revision)
        let confirmed=try facts(h,home:reviewed)
        #expect(predicate(confirmed,"shelter","suitable")==true)
        #expect(predicate(confirmed,"shelter","reachable")==true)
        h.people[0].sleepingSpaceID=nil
        let missingStart=try facts(h,home:SimFixtures.home)
        #expect(predicate(missingStart,"shelter","suitable")==true)
        #expect(predicate(missingStart,"shelter","reachable")==nil)
        h.people[0].sleepingSpaceID="sp-living";h.people[0].needs=[.usesWheelchair]
        let narrow=try facts(h,home:SimFixtures.home)
        #expect(predicate(narrow,"shelter","suitable")==true)
        #expect(predicate(narrow,"shelter","reachable")==nil)
    }
    @Test func invalidatedShelterCannotEarnSuitabilityOrBorrowExteriorRoute()throws {
        var home=SimFixtures.home
        let shelter=try #require(ShelterSuitability.confirmedRoom(in:home))
        let index=try #require(home.spaces.firstIndex{$0.id==shelter.id})
        home.spaces[index].interiorNoWindowsConfirmed = .unknown
        let values=try facts(SampleHouseholds.oak,home:home)
        #expect(predicate(values,"shelter","suitable")==nil)
        #expect(predicate(values,"shelter","reachable")==nil)
    }
    @Test func locationDoesNotProveFoodAccessAndConfirmationPropagates()throws {
        var h=SampleHouseholds.oak
        h.preparedness=PreparednessRecord(items:["food":PreparationFact(available:.confirmed(true),location:"Locked shed")])
        let unknown=try facts(h)
        #expect(predicate(unknown,"food","quantity")==true)
        #expect(predicate(unknown,"food","accessible")==nil)
        var ledger=InventoryLedger()
        var food=InventoryItem(id:"food",physicalID:"pantry-box",category:"food",quantity:.confirmed(3),unit:.day,usableQuantity:.confirmed(3),accessible:.confirmed(false))
        try ledger.confirm([food],baseRevision:0,at:date)
        #expect(predicate(try facts(h,inventory:ledger),"food","accessible")==false)
        food.accessible = .confirmed(true)
        try ledger.confirm([food],baseRevision:1,at:date)
        #expect(predicate(try facts(h,inventory:ledger),"food","accessible")==true)
        food.expiresAt=date.addingTimeInterval(-1)
        try ledger.confirm([food],baseRevision:2,at:date)
        #expect(predicate(try facts(h,inventory:ledger),"food","accessible")==false)
    }
    @Test func waterDisjunctionPreservesUnknownAndConfirmedNegative()throws {
        var ledger=InventoryLedger()
        func item(_ id:String,_ access:EvidenceValue<Bool>)->InventoryItem {
            InventoryItem(id:id,physicalID:id,category:"water",quantity:.confirmed(2),unit:.liter,usableQuantity:.confirmed(2),accessible:access)
        }
        try ledger.confirm([item("a",.confirmed(false)),item("b",.unknown)],baseRevision:0,at:date)
        #expect(predicate(try facts(SampleHouseholds.oak,inventory:ledger),"water","accessible")==nil)
        try ledger.confirm([item("b",.confirmed(false))],baseRevision:1,at:date)
        #expect(predicate(try facts(SampleHouseholds.oak,inventory:ledger),"water","accessible")==false)
        try ledger.confirm([item("b",.confirmed(true))],baseRevision:2,at:date)
        #expect(predicate(try facts(SampleHouseholds.oak,inventory:ledger),"water","accessible")==true)
    }
    @Test func carrierAndTransportAbsenceAreUnknown()throws {
        var h=SampleHouseholds.oak;h.transport=Transport();h.pets=[Pet(id:"pet",kind:.cat)]
        let unknown=try facts(h)
        #expect(predicate(unknown,"pets","transport")==nil)
        #expect(predicate(unknown,"meetups","transport")==nil)
        h.pets[0].carrierAvailable = .confirmed(false)
        #expect(predicate(try facts(h),"pets","transport")==false)
    }
    @Test func helperApplicabilityAndIdentityUseRecordedEvidence()throws {
        for person in [Person(id:"needs",alias:"A",ageBand:.infant),Person(id:"needs",alias:"A",ageBand:.child),Person(id:"needs",alias:"A",ageBand:.adult,needs:[.deafOrHardOfHearing])] {
            var h=SampleHouseholds.oak;h.people=[person,Person(id:"helper",alias:"B",ageBand:.adult)]
            let unknown=try facts(h)
            #expect(unknown.first{$0.criterionID=="assistance"}?.notApplicableRule==nil)
            #expect(unknown.first{$0.criterionID=="care"}?.notApplicableRule==nil)
            #expect(predicate(unknown,"assistance","assigned")==nil)
            for invalid in ["needs","missing-person"] {
                h.people[0].helperPersonID=invalid
                #expect(predicate(try facts(h),"assistance","assigned")==false)
            }
            h.people[0].helperPersonID="helper"
            #expect(predicate(try facts(h),"assistance","assigned")==true)
        }
    }
    @Test func policyVersionsCannotMixAndLegacyScoresStillDecode()throws {
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let original=try facts(SampleHouseholds.oak)
        let current=try ScoreCompiler.compile(rubric:rubric,assessments:original)
        #expect(current.assessmentVersion==HouseholdAssessment.version)
        var mixed=original;mixed[0].assessmentVersion=nil
        #expect(throws:SessionError.invalidCommand){try ScoreCompiler.compile(rubric:rubric,assessments:mixed)}
        mixed[0].assessmentVersion="dryrun.household-assessment/1"
        #expect(throws:SessionError.invalidCommand){try ScoreCompiler.compile(rubric:rubric,assessments:mixed)}
        let legacy=original.map{a in var a=a;a.assessmentVersion=nil;return a}
        let old=try ScoreCompiler.compile(rubric:rubric,assessments:legacy)
        #expect(old.overall==current.overall);#expect(old.evidenceCoverage==current.evidenceCoverage)
        let decoded=try DryRunJSON.decoder().decode(PreparednessScorecard.self,from:DryRunJSON.encoder().encode(old))
        #expect(decoded.assessmentVersion==nil)
    }
    @Test func removedReconnectionRecordCannotEstablishOfflineContactAccess() throws {
        var h=SampleHouseholds.oak
        h.contacts=[HouseholdContact(id:"trusted",role:.other,alias:"Trusted contact",phone:"5550100")]
        let baseline=try facts(h)
        for recorded in [true,false] {
            h.preparedness=PreparednessRecord(items:["reconnect":PreparationFact(available:.confirmed(recorded),location:"Legacy arrangement",notes:"Preserve this owner text")])
            let assessed=try facts(h)
            #expect(predicate(assessed,"contact","usableContact")==true)
            #expect(predicate(assessed,"contact","offlineAccess")==nil)
            #expect(assessed.first{$0.criterionID=="contact"}?.evidenceIDs==["contacts"])
            let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
            #expect(try ScoreCompiler.compile(rubric:rubric,assessments:assessed).overall==ScoreCompiler.compile(rubric:rubric,assessments:baseline).overall)
            let restored=try DryRunJSON.decoder().decode(HouseholdProfile.self,from:DryRunJSON.encoder().encode(h))
            #expect(restored.preparedness?.items["reconnect"]?.available.confirmedValue==recorded)
            #expect(restored.preparedness?.items["reconnect"]?.notes=="Preserve this owner text")
            #expect(restored.contacts==h.contacts)
        }
    }

}
