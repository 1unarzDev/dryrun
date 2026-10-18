import Foundation
import Testing
@testable import DryRunCore

@Suite("Living family plan and private place snapshot")
struct LivingPlanTests {
    @Test("A household without geometry has a basic card and keeps international contacts and text meetups")
    func noLayoutCard() throws {
        var h = SampleHouseholds.oak
        h.homeID = "personal-home"; h.isFictional = false
        h.privateLocation = PrivateLocation(addressLine: "12 Rue Exemple", countryCode: "FR")
        h.contacts = [HouseholdContact(id: "contact", role: .outOfAreaContact, alias: "Aunt", phone: "+33 1 23 45 67 89")]
        let meeting = SavedPlace(homeID: h.stableHomeID, purpose: .outsideMeetingPoint, label: "Old oak", findingInstructions: "Across the driveway, beside the gate")
        let doc = PlanBuilder.build(household: h, home: nil, savedPlaces: [meeting], results: [], localizer: try PlanBuilderTests.localizer("en"), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        #expect(doc.visualSnapshot?.home == nil)
        #expect(doc.homeRevision == 0)
        #expect(doc.pages.first?.id == "family-card")
        let text = doc.pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(text.contains("+33 1 23 45 67 89"))
        #expect(text.contains("Across the driveway, beside the gate"))
        #expect(!doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "plan.help.911" })
        #expect(PlanValidator.validate(doc, household: h).isEmpty)
        #expect(!doc.isStale(household: h, home: nil, contentVersion: "test", savedPlaces: [meeting]))
    }

    @Test("Geographic meetup additions, edits and removals invalidate the matching document; other homes are excluded")
    func placeRevisions() throws {
        var h = SampleHouseholds.oak; h.homeID = "own-home"
        let place = SavedPlace(id: "place", homeID: h.stableHomeID, purpose: .backupMeetingPlace, label: "Library", addressText: "1 Main Road")
        let other = SavedPlace(homeID: "different-home", purpose: .outsideMeetingPoint, label: "DO NOT EXPORT")
        let doc = PlanBuilder.build(household: h, home: nil, savedPlaces: [place, other], results: [], localizer: try PlanBuilderTests.localizer("en"), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        #expect(doc.visualSnapshot?.savedPlaces == [place])
        #expect(!doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.text.contains("DO NOT EXPORT") })
        var edited = place; edited.findingInstructions = "South entrance"
        #expect(doc.isStale(household: h, home: nil, contentVersion: "test", savedPlaces: [edited]))
        #expect(doc.isStale(household: h, home: nil, contentVersion: "test", savedPlaces: []))
        #expect(!doc.isStale(household: h, home: nil, contentVersion: "test", savedPlaces: [place, other]))
    }

    @Test("Legacy private places and plans decode without newer optional visual or instruction fields")
    func legacyDocument() throws {
        let place = SavedPlace(homeID: "h", purpose: .outsideMeetingPoint, label: "Gate")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as! [String: Any]
        json.removeValue(forKey: "findingInstructions")
        let restored = try JSONDecoder().decode(SavedPlace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.findingInstructions == nil)
        let h = SampleHouseholds.oak
        let doc = PlanBuilder.build(household: h, home: nil, results: [], localizer: try PlanBuilderTests.localizer("en"), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        json.removeValue(forKey: "visualSnapshot")
        let legacy = try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.visualSnapshot == nil)
        #expect(legacy.pages == doc.pages)
    }
}

extension LivingPlanTests {
    @Test("Sensitive fields are selected independently and no home is needed for their preview")
    func selectedContent() throws {
        var h = SampleHouseholds.oak
        h.people[0].emergencyInformation = PersonEmergencyInformation(criticalConditions: "CONDITION-CANARY", severeAllergies: "ALLERGY-CANARY", essentialMedication: "MEDICATION-CANARY", responderInstructions: "INSTRUCTION-CANARY")
        let l = try PlanBuilderTests.localizer("en")
        func text(_ selection: FamilyCardSelection) -> String {
            PlanBuilder.build(household: h, home: nil, results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate, options: .init(familyCardSelection: selection)).pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined(separator: "\n")
        }
        let omitted = text(.init())
        #expect(!omitted.contains("CONDITION-CANARY") && !omitted.contains("MEDICATION-CANARY") && !omitted.contains("INSTRUCTION-CANARY"))
        let critical = text(.init(includeCriticalInformation: true))
        #expect(critical.contains("CONDITION-CANARY") && critical.contains("ALLERGY-CANARY"))
        #expect(!critical.contains("MEDICATION-CANARY") && !critical.contains("INSTRUCTION-CANARY"))
        let instructions = text(.init(includeMedication: true, includeResponderInstructions: true, includeContacts: false))
        #expect(instructions.contains("MEDICATION-CANARY") && instructions.contains("INSTRUCTION-CANARY"))
        #expect(!instructions.contains("CONDITION-CANARY") && !instructions.contains("ALLERGY-CANARY"))
    }
}

extension LivingPlanTests {
    @Test("Shelter export follows the current supported scene and never relabels an interior path as outside")
    func canonicalShelterOnly() throws {
        let h = SampleHouseholds.oak
        var home = PlanBuilderTests.tinyHome()
        home = HomeConfirmation.apply(.shelterSpot(spaceID: "sp-bed1", interiorNoWindows: true), to: home)
        let route = EgressPlanner().plan(RouteRequest(personID: h.people[0].id, startSpaceID: "sp-bed1", purpose: .interiorShelter, destinationSpaceID: "sp-bed1"), in: home)
        #expect(route.primary != nil)
        var result = PlanBuilderTests.fakeResult("tornado", household: h, home: home, routes: [route])
        let l = try PlanBuilderTests.localizer("en")
        func shelterLines() -> [PlanLine] {
            PlanBuilder.build(household: h, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
                .pages.first { $0.id == "scenario-tornado" }!.sections.first { $0.id == "shelter" }!.lines
        }
        // Legacy annotations/routes alone do not establish the scene's accepted destination.
        #expect(!shelterLines().contains { $0.key == "plan.shelter.line" })
        result.snapshots = [SimulationSnapshot(simMinute: 1, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: SpatialExerciseState(hazard: .tornado, seed: 1, stageID: "shelter", destinationSpaceID: "sp-bed1", routes: [route], assumption: "Confirmed exercise shelter"))]
        #expect(shelterLines().contains { $0.key == "plan.shelter.line" })
        let routeLine = try #require(shelterLines().first { $0.key == "plan.route.from" })
        #expect(!routeLine.text.contains("outside"))
        #expect(!shelterLines().contains { $0.key == "plan.route.altNone" })
        result.snapshots[0].spatialState?.destinationSpaceID = nil
        result.snapshots[0].spatialState?.routes = []
        #expect(!shelterLines().contains { $0.key == "plan.shelter.line" })
    }

    @Test("Critical selection applies to scenario recommendations and diagram annotation labels; notes consent is independent")
    func privacyAcrossSectionsAndDiagrams() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].label = "PRIVATE-DEVICE-NAME"
        h.equipment[0].carePlanNotes = "INTENTIONALLY-SELECTED-NOTE"
        var home = SampleHomes.ranch
        home.annotations.append(Annotation(id: "private-med", kind: .medicalEquipment, floorID: home.floors[0].id, spaceID: home.spaces[0].id, position: Vec2(1,1), label: "PRIVATE-ANNOTATION", verification: .verified))
        let rec = Recommendation(actionID: "act.backup.confirm-medical-backup", tier: .unmetEssentialRequirement,
            titleKey: "action.act.backup.confirm-medical-backup.title", whyKey: "action.act.backup.confirm-medical-backup.why",
            templateValues: ["device": "PRIVATE-DEVICE-NAME"], matchedFactIDs: [], causeEventIDs: [], scenarioIDs: ["freeze-power-loss"], tryIntervention: nil, modeledEffectKey: nil, effort: .low, sourceIDs: ["S25"], verificationStatus: .unknown, subjectID: "equipment." + h.equipment[0].id)
        let result = PlanBuilderTests.fakeResult("freeze-power-loss", household: h, home: home, recommendations: [rec])
        let doc = PlanBuilder.build(household: h, home: home, results: [result], localizer: try PlanBuilderTests.localizer("en"), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate, options: .init(includePrivateNotes: true))
        let text = doc.pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(!text.contains("PRIVATE-DEVICE-NAME"))
        #expect(text.contains("INTENTIONALLY-SELECTED-NOTE"))
        #expect(doc.visualSnapshot?.home?.annotations.contains { $0.label == "PRIVATE-ANNOTATION" } == false)
        #expect(doc.visualSnapshot?.home?.annotations.contains { $0.kind == .medicalEquipment } == false)
    }

    @Test("Plan diagrams and text use the final scenario stage, including blocked paths, and reject legacy history")
    func finalRoutesOnly() throws {
        let h = SampleHouseholds.oak, home = SampleHomes.ranch
        let initial = EgressPlanner().plan(RouteRequest(personID: h.people[0].id, startSpaceID: "sp-bed1"), in: home)
        #expect(initial.primary != nil)
        let blocked = RouteResult(request: initial.request, primary: nil, alternative: nil, alternativeStatus: .none,
            noRouteReason: .blockedByScenario, exclusions: [], homeID: home.id, homeRevision: home.revision)
        var result = PlanBuilderTests.fakeResult("home-fire", household: h, home: home, routes: [initial, blocked])
        let l = try PlanBuilderTests.localizer("en")
        func document(_ result: RehearsalResult) -> PlanDocument {
            PlanBuilder.build(household: h, home: home, results: [result], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        }
        #expect(document(result).visualSnapshot?.routes == [blocked])
        result.snapshots = [SimulationSnapshot(simMinute: 1, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: SpatialExerciseState(hazard: .homeFire, seed: 1, stageID: "blocked", routes: [blocked], assumption: "Authored blockage"))]
        let doc = document(result)
        #expect(doc.visualSnapshot?.routes == [blocked])
        #expect(!doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "plan.route.from" })
        #expect(doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "plan.route.none" })
        result.snapshots[0].spatialState?.routes = []
        #expect(document(result).visualSnapshot?.routes.isEmpty == true)
    }
}
