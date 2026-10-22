import XCTest
@testable import DryRunCore

final class AuthorizedAIContextTests: XCTestCase {
    private func household() -> HouseholdProfile {
        HouseholdProfile(id:"synthetic-private-context", displayName:"Synthetic only", regionID:"synthetic-region",
            privateLocation:PrivateLocation(addressLine:"100 Synthetic Lane",latitude:41,longitude:-87),
            people:[Person(id:"person-a",alias:"Casey",ageBand:.adult,needs:[.needsHelperToEvacuate],
                           helperPersonID:"person-b",relationship:.parent,
                           emergencyInformation:PersonEmergencyInformation(essentialMedication:"Synthetic recorded medicine; retain recorded cool-storage instruction")),
                    Person(id:"person-b",alias:"Robin",ageBand:.adult)],
            housing:Housing(homeType:.singleFamily,tenancy:.renter,heatingFuel:.electric,cooling:.fansOnly,waterSource:.municipal),
            transport:Transport(),supplies:Supplies(limitedStorageSpace:true,limitedBudget:true),isFictional:true)
    }
    func testConsentAndScopeAreRequired() throws {
        let h=household()
        XCTAssertThrowsError(try AuthorizedAIContext(household:h,home:nil,state:IntegratedAIState(),sessionID:"s",cloudPlanningConsent:false))
        XCTAssertThrowsError(try AuthorizedAIContext(household:h,home:nil,state:IntegratedAIState(),sessionID:"",cloudPlanningConsent:true))
    }
    func testCompleteWireRetainsCanonicalRelationshipsAndUnknownsWithoutChangingMinimalProjection() throws {
        let h=household();let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let snapshot=try AuthorizedAIContext(household:h,home:nil,state:IntegratedAIState(),sessionID:"synthetic-session",cloudPlanningConsent:true)
        let bytes=try encoder.encode(snapshot)
        let value=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        let records=try XCTUnwrap(value["records"] as? [[String:Any]])
        let person=try XCTUnwrap(records.first{$0["sourcePath"] as? String == "person.person-a"}?["value"] as? [String:Any])
        XCTAssertEqual(person["alias"] as? String,"Casey");XCTAssertEqual(person["helperPersonID"] as? String,"person-b")
        XCTAssertEqual(records.first{$0["sourcePath"] as? String == "budgetAmount"}?["status"] as? String,"unsupported")
        XCTAssertEqual(records.first{$0["sourcePath"] as? String == "geometry"}?["status"] as? String,"not_recorded")
        let minimal=try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(HouseholdContextSnapshot(h))) as? [String:Any])
        XCTAssertNil(minimal["privateLocation"]);XCTAssertNil((minimal["people"] as? [[String:Any]])?.first?["alias"])
        // Cleared authored synthetic engineering input, never a live household or model response.
        // Written on every run so the gateway's strict-schema test (private-context.test.ts) reads current Core bytes.
        let wire=ProcessInfo.processInfo.environment["DRYRUN_CONTEXT_WIRE_PATH"].map{URL(fileURLWithPath:$0)}
            ?? SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/native-bridge/authorized-context-wire.json")
        try bytes.write(to:wire,options:.atomic)
    }
    func testSnapshotIdentityTracksMaterialChangesAndSessionIsolation() throws {
        var h=household();let state=IntegratedAIState()
        let a=try AuthorizedAIContext(household:h,home:nil,state:state,sessionID:"a",cloudPlanningConsent:true)
        let same=try AuthorizedAIContext(household:h,home:nil,state:state,sessionID:"a",cloudPlanningConsent:true)
        let b=try AuthorizedAIContext(household:h,home:nil,state:state,sessionID:"b",cloudPlanningConsent:true)
        XCTAssertEqual(a.snapshotID,same.snapshotID);XCTAssertNotEqual(a.snapshotID,b.snapshotID)
        h.people[0].helperPersonID=nil;h.bumpRevision()
        let changed=try AuthorizedAIContext(household:h,home:nil,state:state,sessionID:"a",cloudPlanningConsent:true)
        XCTAssertNotEqual(a.snapshotID,changed.snapshotID)
    }
    func testGranularHomeInventoryAndPracticeEntitiesRetainRecordedValues() throws {
        let h=household();var home=SampleHomes.ranch;home.id=h.stableHomeID
        let note=String(repeating:"Authored oversized home note. ",count:6000);home.completenessNote=note
        var state=IntegratedAIState()
        try state.inventory.confirm([InventoryItem(id:"inventory-a",physicalID:"physical-a",category:"water",quantity:.confirmed(4),unit:.liter)],baseRevision:0,at:Date(timeIntervalSince1970:0))
        var attempt=PracticeAttempt(id:"practice-a",sequence:1,variantID:"practice-check-a/0",answers:[],coached:true);attempt.archivedUnverified=true;state.practiceAttempts=[attempt]
        let context=try AuthorizedAIContext(household:h,home:home,state:state,sessionID:"granular",cloudPlanningConsent:true)
        XCTAssertTrue(context.records.contains{$0.sourcePath.hasPrefix("geometry.spaces.item.")})
        XCTAssertTrue(context.records.contains{$0.sourcePath.hasPrefix("ledger.items.item.")&&$0.subjectID=="inventory-a"})
        XCTAssertTrue(context.records.contains{$0.sourcePath.hasPrefix("practiceAttempts.item.")&&$0.subjectID=="practice-a"})
        let geometry=try XCTUnwrap(context.records.first{$0.sourcePath=="geometry"})
        if case .object(let values)=geometry.value { if case .string(let value)=values["completenessNote"] {XCTAssertEqual(value,note)} else {XCTFail("Recorded note missing")} } else {XCTFail("Home metadata missing")}
    }
}
