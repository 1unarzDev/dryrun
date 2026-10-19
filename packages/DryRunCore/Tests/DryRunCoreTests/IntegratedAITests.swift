import Foundation
import Testing
@testable import DryRunCore

@Suite("Integrated AI authority and deterministic host") struct IntegratedAITests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    func waterSession() -> SimulationSession {SimulationSession(id:"test",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"))}
    func loss(_ session:inout SimulationSession) throws {
        try session.commit(SessionCommit(id:"loss",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
    }
    @Test func actionConservationReplayAndAtomicity() throws {
        var essential=waterSession();try loss(&essential)
        var all=essential
        try essential.commit(.init(id:"user",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"essential")]),library:SimFixtures.library)
        try all.commit(.init(id:"user",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"all")]),library:SimFixtures.library)
        let a=try essential.commit(.init(id:"advance",actor:"director",baseRevision:2,commands:[.init(kind:"advance",minute:720)]),library:SimFixtures.library)
        let b=try all.commit(.init(id:"advance",actor:"director",baseRevision:2,commands:[.init(kind:"advance",minute:720)]),library:SimFixtures.library)
        #expect(a.snapshot.resources["res.water.stored"]?.amount == 3)
        #expect(b.snapshot.resources["res.water.stored"]?.amount == 1)
        let decoded=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(all))
        #expect(try decoded.query(library:SimFixtures.library)==b)
        let before=try all.query(library:SimFixtures.library)
        #expect(throws:SessionError.duplicate){try all.commit(.init(id:"advance",actor:"director",baseRevision:3,commands:[.init(kind:"advance",minute:1000)]),library:SimFixtures.library)}
        #expect(throws:SessionError.stale){try all.commit(.init(id:"late",actor:"director",baseRevision:0,commands:[.init(kind:"finish")]),library:SimFixtures.library)}
        #expect(throws:SessionError.persistence){try all.commit(.init(id:"atomic",actor:"director",baseRevision:3,commands:[.init(kind:"advance",minute:1000)]),library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
        #expect(try all.query(library:SimFixtures.library)==before)
        let fallback=try all.commit(all.fallback(),library:SimFixtures.library)
        #expect(fallback.snapshot.resources==before.snapshot.resources)
    }
    @Test func permissionsSchedulingAndDepletion() throws {
        var session=waterSession();try loss(&session)
        #expect(throws:SessionError.invalidCommand){try session.commit(.init(id:"move",actor:"director",baseRevision:1,commands:[.init(kind:"moveTo",target:"p-oak-1",value:"sp-kitchen")]),library:SimFixtures.library)}
        let receipt=try session.commit(.init(id:"long",actor:"director",baseRevision:1,commands:[.init(kind:"advance",minute:4320)]),library:SimFixtures.library)
        #expect(receipt.snapshot.simMinute==1800) // stored-water depletion is a mandatory boundary
        #expect(receipt.snapshot.resources["res.water.stored"]!.amount!>=0)
        #expect(throws:SessionError.budget){try session.commit(.init(id:"past",actor:"director",baseRevision:2,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0)]),library:SimFixtures.library)}
    }
    @Test func inventoryUnknownsDedupAndConversion() throws {
        var ledger=InventoryLedger()
        let item=InventoryItem(id:"water",physicalID:"container-1",category:"water",quantity:.confirmed(2),unit:.usGallon,usableQuantity:.confirmed(2),accessible:.confirmed(true))
        try ledger.confirm([item],baseRevision:0,at:date)
        let gap=try ledger.waterGap(people:2,at:date)
        #expect(abs(gap.deficit!-4*3.785411784)<0.000001)
        var duplicate=item;duplicate.id="photo-2"
        #expect(throws:SessionError.duplicate){try ledger.confirm([duplicate],baseRevision:1,at:date)}
        var unknown=item;unknown.usableQuantity = .unknown
        try ledger.confirm([unknown],baseRevision:1,at:date)
        #expect(try ledger.waterGap(people:2,at:date).deficit==nil)
        let legacy=try InventoryLedger.migrating(SampleHouseholds.oak.supplies,at:date)
        #expect(try legacy.waterGap(people:4,at:date).unknown)
    }
    @Test func controlledStressRetestAndAllHazards() throws {
        for id in SimFixtures.scenarioIDs {
            let scenario=SimFixtures.library.scenario(id)!
            let input=SimFixtures.input(SampleHouseholds.oak,id)
            var session=SimulationSession(id:id,initial:input)
            #expect(try session.query(library:SimFixtures.library).snapshot.simMinute==0)
            let eligible=scenario.events.filter{Applicability.holds($0.when,household:input.household,home:input.home,variants:input.variants)}
            for (n,e) in eligible.prefix(4).enumerated(){try session.commit(.init(id:"profile-\(n)",actor:"director",baseRevision:session.revision,commands:[.init(kind:"schedule",target:e.id,minute:e.minute)]),library:SimFixtures.library)}
            _=try session.commit(.init(id:"advance",actor:"director",baseRevision:session.revision,commands:[.init(kind:"advance",minute:scenario.durationMinutes)]),library:SimFixtures.library)
        }
    }
    @Test func scoreIsIndependentOfRubricAndDictionaryOrder() throws {
        var rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let assessments=rubric.criteria.enumerated().map{n,c in CriterionAssessment(criterionID:c.id,predicates:Dictionary(uniqueKeysWithValues:c.predicateIDs.enumerated().map{($0.element,($0.offset+n)%3 != 0)}),evidenceIDs:["confirmed"]) }
        let expected=try DryRunJSON.encoder().encode(ScoreCompiler.compile(rubric:rubric,assessments:assessments))
        rubric.criteria.reverse()
        rubric.domainWeights=Dictionary(uniqueKeysWithValues:rubric.domainWeights.sorted{$0.key>$1.key})
        let actual=try DryRunJSON.encoder().encode(ScoreCompiler.compile(rubric:rubric,assessments:assessments.reversed()))
        #expect(actual==expected)
    }
    @Test func rubricMutationsAndLatestPractice() throws {
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let full=rubric.criteria.map{CriterionAssessment(criterionID:$0.id,predicates:Dictionary(uniqueKeysWithValues:$0.predicateIDs.map{($0,true)}),evidenceIDs:["confirmed"]) }
        let unassessed=try ScoreCompiler.compile(rubric:rubric,assessments:[])
        #expect(unassessed.overall==nil);#expect(unassessed.cap==79)
        let baseline=try ScoreCompiler.compile(rubric:rubric,assessments:full)
        #expect(baseline.preparation==100);#expect(baseline.overall==90)
        var gap=full;gap[0].predicates["checked"]=false
        let capped=try ScoreCompiler.compile(rubric:rubric,assessments:gap)
        #expect(capped.overall==59);#expect(capped.evidenceCoverage==100)
        let first=PracticeAttempt(id:"first",sequence:1,variantID:"practice-check-a/0",answers:ScoreCompiler.competencies.map{.init(competencyID:$0,credit:1,committedActionID:"action-\($0)",beforeFeedback:true)})
        let interrupted=PracticeAttempt(id:"second",sequence:2,variantID:"practice-check-b/0",answers:[.init(competencyID:"initialResponse",credit:0,committedActionID:"unsafe",beforeFeedback:true)])
        let card=try ScoreCompiler.compile(rubric:rubric,assessments:full,attempts:[first,interrupted])
        #expect(card.practice==0);#expect(card.practiceAssessed==1)
        for c in rubric.criteria {
            var removed=full;let i=removed.firstIndex{$0.criterionID==c.id}!;removed[i].predicates=[:]
            #expect(try ScoreCompiler.compile(rubric:rubric,assessments:removed).overall!<=baseline.overall!)
        }
    }
}

@Suite("AI source review, refresh and migration") struct AIReviewTests {
    let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
    @Test func concernAuthorityAndMaterialEvidenceDedup() throws {
        let manifest=RoomImageManifest(id:"photo",homeRevision:1,roomID:"sp-living",digest:String(repeating:"a",count:64),capturedAt:date,width:640,height:480,orientation:"up",calibration:"none",transforms:[],redactedRegions:[[0.1,0.1,0.2,0.2]])
        let proposal=HomeConcernProposal(id:"doorway-box",homeRevision:1,imageID:"photo",imageDigest:manifest.digest,box:[0.1,0.2,0.3,0.4],roomID:"sp-living",category:"possibleObstruction",visibleEvidence:"Box near doorway",unknowns:["Depth and full doorway clearance unknown"],actionID:"prep.clearExits",scenarioIDs:["home-fire"])
        var ledger=ConcernLedger();try ledger.review(proposal,decision:.uncertain,manifest:manifest,currentHomeRevision:1,at:date)
        #expect(ledger.reviewed[0].taskID==nil);#expect(!ledger.reviewed[0].canAffectConfirmedScenario)
        try ledger.review(proposal,decision:.confirmed,manifest:manifest,currentHomeRevision:1,at:date)
        #expect(ledger.reviewed[0].taskID != nil);#expect(!ledger.shouldOffer(proposal))
        #expect(throws:SessionError.invalidCommand){try ledger.review(proposal,decision:.confirmed,manifest:manifest,currentHomeRevision:2,at:date)}
    }
    @Test func cloudRevokeCancelsStaleRefreshButKeepsLocalPlans() throws {
        var refresh=ResourceStrategyRefresh();let key=ResourceStrategyKey(gapCategories:["water","water"],transport:"walking",limitedBudget:true,regionID:"outside-pack")
        #expect(refresh.begin(key)==nil);refresh.setCloudOptIn(true);let first=refresh.begin(key)!
        #expect(refresh.begin(key)==nil);refresh.setCloudOptIn(false)
        #expect(throws:SessionError.stale){try refresh.accept([],ticket:first)}
        refresh.setCloudOptIn(true);let retry=refresh.begin(key)!;try refresh.accept([],ticket:retry)
        #expect(refresh.acceptedKey==key);refresh.setCloudOptIn(false);#expect(refresh.acceptedKey==key)
    }
    @Test func missingInventoryAndDeviceDocumentationAreUnknown() throws {
        let h=SampleHouseholds.oak
        let assessment=try HouseholdAssessment.assess(household:h,home:nil,inventory:InventoryLedger(),at:date)
        #expect(assessment.first{$0.criterionID=="device"}?.predicates["approvedAlternative"]==nil)
        #expect(try InventoryLedger().waterGap(people:2,at:date).deficit==nil)
        let data=try DryRunJSON.encoder().encode(HouseholdContextSnapshot(h))
        let string=String(decoding:data,as:UTF8.self)
        #expect(!string.contains("555-"));#expect(!string.contains("Grandpa"));#expect(!string.contains("carePlanNotes"));#expect(!string.contains("privateLocation"))
    }
    @Test func practiceRestartCannotEraseUnfinishedAttempt() throws {
        var local=IntegratedAIState()
        let first=try local.beginPractice(id:"first",variantID:"practice-check-a/0")
        let resumed=try local.beginPractice(id:"reroll",variantID:"practice-check-b/0")
        #expect(first.id==resumed.id);#expect(first.variantID==resumed.variantID)
        #expect(throws:SessionError.invalidCommand){try local.recordPracticeAnswer(.init(competencyID:"initialResponse",credit:1,committedActionID:"model-said-so",beforeFeedback:true),attemptID:first.id)}
    }
}

@Suite("TypeScript Swift recorded contracts") struct AIContractRoundTrips {
    @Test func imageManifestsAndLiveDirectorProposalDecode() throws {
        struct ImageCase:Decodable{var manifest:RoomImageManifest}
        struct Images:Decodable{var cases:[ImageCase]}
        let images=try DryRunJSON.decoder().decode(Images.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/images/annotations.json")))
        for image in images.cases {
            let encoded=try DryRunJSON.encoder().encode(image.manifest)
            #expect(try DryRunJSON.decoder().decode(RoomImageManifest.self,from:encoded)==image.manifest)
            #expect(image.manifest.calibration=="none")
        }
        struct Result:Decodable{var proposal:DirectorProposal?;var binding:AgentContextBinding?}
        struct Turn:Decodable{var result:Result?}
        struct Trace:Decodable{var trace:[Turn]}
        for variant in ["all","essential"] {
            let trace=try DryRunJSON.decoder().decode(Trace.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/adaptive-trace-\(variant).json")))
            #expect(trace.trace.contains{$0.result?.proposal != nil})
            for turn in trace.trace {if let proposal=turn.result?.proposal {#expect(proposal.actor=="director");#expect(proposal.commands.allSatisfy{["schedule","advance","requestDecision","finish"].contains($0.kind)})}}
        }
    }
}

@Suite("AI boundary regressions") struct AIBoundaryRegressions {
    @Test func inaccessibleInventoryAndAtomicProjection() throws {
        let date=Date(timeIntervalSince1970:1792368000)
        var h=SampleHouseholds.oak,local=IntegratedAIState()
        let item=InventoryItem(id:"water",physicalID:"water",category:"water",quantity:.confirmed(12),unit:.usGallon,usableQuantity:.confirmed(12),accessible:.confirmed(false))
        try local.inventory.confirm([item],baseRevision:0,at:date)
        let gap=try local.inventory.waterGap(people:4,at:date)
        #expect(!gap.unknown);#expect(gap.confirmedUsable==0);#expect(gap.deficit != nil)
        let old=h.revision
        #expect(throws:SessionError.persistence){try local.confirmInventory([],household:&h,baseHouseholdRevision:old,baseInventoryRevision:1,at:date,persist:{_,_ in throw SessionError.persistence})}
        #expect(h.revision==old);#expect(local.inventory.revision==1)
    }
    @Test func practiceCreditMustMatchHostAnchor() throws {
        var s=SimulationSession(id:"check",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"))
        try s.commit(.init(id:"loss",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        try s.commit(.init(id:"answer",actor:"user",baseRevision:1,commands:[.init(kind:"useStoredWater",value:"all")]),library:SimFixtures.library)
        var local=IntegratedAIState(sessions:[s]);let attempt=try local.beginPractice(id:"a",variantID:"practice-check-a/0")
        #expect(throws:SessionError.invalidCommand){try local.recordPracticeAnswer(.init(competencyID:"initialResponse",credit:1,committedActionID:"answer",beforeFeedback:true),attemptID:attempt.id,library:SimFixtures.library)}
        try local.recordPracticeAnswer(.init(competencyID:"initialResponse",credit:0,committedActionID:"answer",beforeFeedback:true),attemptID:attempt.id,library:SimFixtures.library)
        #expect(local.practiceAttempts[0].answers[0].credit==0)
    }
    @Test func movedResidentOverridesRecordedStartAndReplays() throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"home-fire")
        let home=SampleHomes.ranch
        input.home=home
        let person=input.household.people[0]
        let spaces=home.spaces.filter{$0.floorID==home.floors[0].id}
        guard spaces.count>1 else {Issue.record("Fixture needs multiple rooms");return}
        input.spatialOptions = .init(startingSpaceIDs:[person.id:spaces[0].id])
        var s=SimulationSession(id:"move",initial:input)
        let r=try s.commit(.init(id:"move",actor:"user",baseRevision:0,commands:[.init(kind:"moveTo",target:person.id,value:spaces[1].id)]),library:SimFixtures.library)
        #expect(r.routes.first(where:{$0.request.personID==person.id})?.request.startSpaceID==spaces[1].id)
        #expect(try s.query(library:SimFixtures.library)==r)
    }
}

@Suite("Controlled stress comparison") struct ControlledStressRegression {
    @Test func sameScheduleRetestDelaysDepletionWithoutChangingFacts() throws {
        let input=SimFixtures.input(SampleHouseholds.oak,"water-outage")
        let finding=try PlanStressTester.execute(initial:input,profileIDs:["evt.water-outage.well-pump-failure"],library:SimFixtures.library,intervention:.init(actionID:"act.water.store-3day"))
        #expect(finding.baseline.events.first{$0.id.contains("water-depleted")}?.simMinute==1800)
        #expect(finding.controlledRetest?.events.first{$0.id.contains("water-depleted")}?.simMinute==4320)
        #expect(input.household.supplies.storedWaterGallons.confirmedValue==5)
    }
}

@Suite("Simultaneous resource boundaries") struct SimultaneousResourceRegression {
    @Test func phoneAndWaterDepletionBothExecuteAtSameMinute() throws {
        var input=SimFixtures.input(SampleHouseholds.oak,"water-outage")
        input.household.backupPower=[];input.variants=["with-power-loss"]
        input.household.supplies.storedWaterGallons = .confirmed(Double(input.household.people.count)/4)
        input.household.communications.handsetRuntimeHours = .confirmed(6)
        input.household.communications.powerBankCharges = .confirmed(0)
        var session=SimulationSession(id:"simultaneous",initial:input)
        try session.commit(.init(id:"loss",actor:"director",baseRevision:0,commands:[.init(kind:"schedule",target:"evt.water-outage.well-pump-failure",minute:0),.init(kind:"schedule",target:"evt.water-outage.power-loss",minute:0),.init(kind:"advance",minute:0)]),library:SimFixtures.library)
        let result=try session.commit(.init(id:"advance",actor:"director",baseRevision:1,commands:[.init(kind:"advance",minute:720)]),library:SimFixtures.library)
        #expect(result.snapshot.simMinute==360)
        #expect(result.events.contains{$0.id.contains("water-depleted") && $0.simMinute==360})
        #expect(result.events.contains{$0.id.contains("handset-depleted") && $0.simMinute==360})
        #expect(try session.query(library:SimFixtures.library)==result)
    }
}

@Suite("Score evidence invariants") struct ScoreEvidenceInvariants {
    @Test func orderingAndUnrelatedShoppingCannotClearDeviceCap() throws {
        let rubric=try DryRunJSON.decoder().decode(RubricDefinition.self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        var facts=rubric.criteria.map{CriterionAssessment(criterionID:$0.id,predicates:Dictionary(uniqueKeysWithValues:$0.predicateIDs.map{($0,true)}),evidenceIDs:["typed-confirmation"]) }
        let index=facts.firstIndex{$0.criterionID=="device"}!
        facts[index].predicates["approvedAlternative"]=false
        let a=try ScoreCompiler.compile(rubric:rubric,assessments:facts)
        let b=try ScoreCompiler.compile(rubric:rubric,assessments:Array(facts.reversed()))
        #expect(a.overall==b.overall);#expect(a.cap==59)
        let food=facts.firstIndex{$0.criterionID=="food"}!
        facts[food].predicates=[:]
        #expect(try ScoreCompiler.compile(rubric:rubric,assessments:facts).cap==59)
        let repeated=PracticeAttempt(id:"repeat",sequence:1,variantID:"practice-check-a/0",answers:ScoreCompiler.competencies.map{.init(competencyID:$0,credit:1,committedActionID:"same-action",beforeFeedback:true)})
        #expect(throws:SessionError.invalidCommand){try ScoreCompiler.compile(rubric:rubric,assessments:facts,attempts:[repeated])}
    }
}

@Suite("Recorded supply requirement arithmetic") struct RecordedSupplyRequirementTests {
    @Test func subjectUnitsExpiryAndIdentityCannotInflateCredit() throws {
        let date=Date(timeIntervalSince1970:1792368000)
        var ledger=InventoryLedger()
        let item=InventoryItem(id:"item",physicalID:"box",category:"recorded-care-supply",quantity:.confirmed(5),unit:.count,usableQuantity:.confirmed(4),accessible:.confirmed(true),subjectIDs:["person-a"],evidenceIDs:["typed"])
        try ledger.confirm([item],baseRevision:0,at:date)
        let requirement=RecordedSupplyRequirement(id:"care-instructions",category:item.category,quantity:6,unit:.count,subjectIDs:["person-a"],sourceIDs:["recorded-instructions"])
        #expect(try ledger.gap(for:requirement,at:date).deficit==2)
        var other=requirement;other.subjectIDs=["person-b"]
        #expect(try ledger.gap(for:other,at:date).deficit==nil)
        var incompatible=requirement;incompatible.unit = .day
        #expect(throws:SessionError.invalidCommand){try ledger.gap(for:incompatible,at:date)}
        var second=item;second.id="second";second.physicalID="other-box"
        try ledger.confirm([second],baseRevision:1,at:date)
        var collision=item;collision.physicalID="other-box"
        #expect(throws:SessionError.duplicate){try ledger.confirm([collision],baseRevision:2,at:date)}
        #expect(ledger.revision==2)
        var expired=item;expired.expiresAt=date
        try ledger.confirm([expired],baseRevision:2,at:date)
        #expect(try ledger.gap(for:requirement,at:date).confirmedUsable==4)
    }
}
