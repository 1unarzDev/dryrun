import Foundation
import Testing
@testable import DryRunCore

@Suite("Current shelter suitability")
struct ShelterSuitabilityTests {
    private let shelterID = "sp-closet"
    private var request: RouteRequest {
        RouteRequest(startSpaceID: "sp-living", purpose: .interiorShelter, destinationSpaceID: shelterID)
    }
    private func needsShelterReview(_ home: HomeModel) -> Bool {
        HomeConfirmation.steps(for: home).contains { $0.kind == .shelterSpot }
    }

    @Test("Current floor grade and legacy ground semantics agree in confirmation and routing")
    func grades() {
        for source in [HomeSource.manual, .sample, .roomPlanScan] {
            for grade: ExteriorGrade? in [nil, .unknown, .aboveGround, .ground, .belowGround, .walkout] {
                var home = SampleHomes.ranch
                home.source = source; home.floors[0].exteriorGrade = grade
                let allowed = grade == .ground || grade == .belowGround || grade == .walkout
                    || (grade == nil && source != .roomPlanScan)
                #expect(ShelterSuitability.isConfirmed(roomID: shelterID, in: home) == allowed)
                #expect(needsShelterReview(home) == !allowed)
                #expect((EgressPlanner().plan(request, in: home).primary != nil) == allowed)
                let answered = HomeConfirmation.apply(.shelterSpot(spaceID: shelterID, interiorNoWindows: true), to: home)
                #expect(ShelterSuitability.isConfirmed(roomID: shelterID, in: answered) == allowed)
            }
        }
        var upper = SampleHomes.ranch
        upper.floors[0].level = 2; upper.floors[0].elevationMeters = 6
        #expect(ShelterSuitability.confirmedRoom(in: upper) == nil, "Legacy nil grade does not establish ground in an upper-floor unit")
        #expect(EgressPlanner().plan(request, in: upper).primary == nil)
    }

    @Test("Changing a shelter floor to unknown requeues review and requires explicit reconfirmation")
    func gradeCorrection() {
        let original = SampleHomes.ranch
        let unknown = HomeConfirmation.apply(.floorGrade(floorID: original.floors[0].id, grade: .unknown), to: original)
        #expect(needsShelterReview(unknown))
        #expect(unknown.annotations.first { $0.kind == .tornadoShelterCandidate }?.verification == .proposed)
        #expect(unknown.space(shelterID)?.interiorNoWindowsConfirmed.confirmedValue == true, "Retain the recorded room answer")
        #expect(EgressPlanner().plan(request, in: unknown).primary == nil)
        let ground = HomeConfirmation.apply(.floorGrade(floorID: original.floors[0].id, grade: .ground), to: unknown)
        #expect(needsShelterReview(ground))
        #expect(EgressPlanner().plan(request, in: ground).primary == nil)
        let reconfirmed = HomeConfirmation.apply(.shelterSpot(spaceID: shelterID, interiorNoWindows: true), to: ground)
        #expect(!needsShelterReview(reconfirmed))
        #expect(EgressPlanner().plan(request, in: reconfirmed).primary != nil)
    }

    @Test("A newly recorded lower level invalidates a historical marker without deleting its evidence")
    func lowerLevel() {
        var home = SampleHomes.ranch
        home.floors.append(Floor(id: "basement", level: -1, label: "Our basement", elevationMeters: -2.5, exteriorGrade: .belowGround))
        #expect(home.annotations.contains { $0.kind == .tornadoShelterCandidate && $0.verification == .verified })
        #expect(needsShelterReview(home))
        #expect(EgressPlanner().plan(request, in: home).primary == nil)
        #expect(HomeConfirmation.apply(.shelterSpot(spaceID: shelterID, interiorNoWindows: true), to: home) == home)
        let declined = HomeConfirmation.apply(.shelterSpot(spaceID: shelterID, interiorNoWindows: false), to: home)
        #expect(declined.space(shelterID)?.interiorNoWindowsConfirmed.confirmedValue == false)
        #expect(!declined.annotations.contains { $0.kind == .tornadoShelterCandidate && $0.spaceID == shelterID })
    }

    @Test("Window inventory contradicts a no-window shelter even when rejected as an escape option")
    func windows() {
        for state in VerificationState.allCases {
            var home = SampleHomes.ranch
            home.portals.append(Portal(id: "new-window", floorID: home.floors[0].id, kind: .window,
                a: Vec2(4.5, 6.4), b: Vec2(4.5, 7.1), sideA: .space(shelterID), sideB: .unknown,
                operable: .confirmed(false), verification: state))
            #expect(needsShelterReview(home))
            #expect(EgressPlanner().plan(request, in: home).primary == nil)
            #expect(HomeConfirmation.apply(.shelterSpot(spaceID: shelterID, interiorNoWindows: true), to: home) == home)
        }
    }

    @Test("Both selection and room evidence must be current; a negative answer only clears its own room")
    func currentEvidence() {
        let original = SampleHomes.ranch
        var missingMarker = original
        missingMarker.annotations.removeAll { $0.kind == .tornadoShelterCandidate }
        var missingAnswer = original
        missingAnswer.spaces[missingAnswer.spaces.firstIndex { $0.id == shelterID }!].interiorNoWindowsConfirmed = .unknown
        var corrected = original
        corrected.spaces[corrected.spaces.firstIndex { $0.id == shelterID }!].geometryNeedsReview = true
        var wrongFloor = original
        wrongFloor.annotations[wrongFloor.annotations.firstIndex { $0.kind == .tornadoShelterCandidate }!].floorID = "different-floor"
        for home in [missingMarker, missingAnswer, corrected, wrongFloor] {
            #expect(needsShelterReview(home))
            #expect(EgressPlanner().plan(request, in: home).primary == nil)
        }
        let otherRoomNo = HomeConfirmation.apply(.shelterSpot(spaceID: "sp-living", interiorNoWindows: false), to: original)
        #expect(ShelterSuitability.isConfirmed(roomID: shelterID, in: otherRoomNo))
    }

    @Test("Simulation does not announce or route to a stale candidate rejected by the planner")
    func simulationAgreement() throws {
        let original = SampleHomes.ranch
        var unknown = original; unknown.floors[0].exteriorGrade = .unknown
        var above = original; above.floors[0].exteriorGrade = .aboveGround
        var lower = original
        lower.floors.append(Floor(id: "lower", level: -1, label: "Lower", elevationMeters: -3, exteriorGrade: .belowGround))
        var exposed = original
        exposed.portals.append(Portal(id: "shelter-window", floorID: exposed.floors[0].id, kind: .window,
            a: Vec2(4.5, 6.4), b: Vec2(4.5, 7.1), sideA: .space(shelterID), sideB: .unknown))
        var household = SampleHouseholds.oak
        household.people = [Person(id: "resident", alias: "Example resident", ageBand: .adult, sleepingSpaceID: "sp-living")]
        household.equipment = []; household.backupPower = []
        for home in [original, unknown, above, lower, exposed] {
            let valid = ShelterSuitability.confirmedRoom(in: home) != nil
            let result = try SimFixtures.run(household, "tornado", home: home)
            #expect(result.events.contains { $0.id == "evt.tornado.shelter-preselected" } == valid)
            #expect(result.events.contains { $0.id == "evt.tornado.shelter-not-chosen" } == !valid)
            for scene in result.snapshots.compactMap(\.spatialState) where scene.hazard == .tornado {
                #expect(scene.destinationSpaceID == (valid ? shelterID : nil))
                if !valid { #expect(scene.routes.allSatisfy { $0.primary == nil }) }
            }
        }
    }

    @Test("Choosing a shelter in comparison creates only hypothetical evidence and retains hard exclusions")
    func comparisonIsolation() throws {
        var home = SampleHomes.ranch
        home.annotations.removeAll { $0.kind == .tornadoShelterCandidate }
        home.spaces[home.spaces.firstIndex { $0.id == shelterID }!].interiorNoWindowsConfirmed = .unknown
        var household = SampleHouseholds.oak
        household.people = [Person(id: "resident", alias: "Example resident", ageBand: .adult, sleepingSpaceID: "sp-living")]
        household.equipment = []; household.backupPower = []
        let input = SimFixtures.input(household, "tornado", home: home), original = input
        let intervention = Intervention(actionID: "act.tornado.choose-shelter")
        let comparison = try SimFixtures.engine.compare(input, applying: intervention)
        #expect(input == original && comparison.modified.input.home == home)
        #expect(comparison.modified.input.household == household)
        #expect(comparison.modified.input.interventions == [intervention])
        #expect(comparison.diff.resolvedRequirements.contains("req.shelter"))
        #expect(comparison.baseline.snapshots.compactMap(\.spatialState).allSatisfy { $0.destinationSpaceID == nil })
        #expect(comparison.modified.snapshots.compactMap(\.spatialState).contains { $0.destinationSpaceID == shelterID && $0.routes.contains { $0.primary != nil } })
        let copied = InterventionApplier.apply([intervention], household: household, home: home).1
        #expect(copied.space(shelterID)?.interiorNoWindowsConfirmed.origin == .scenarioAssumption)
        #expect(copied.annotations.contains { $0.kind == .tornadoShelterCandidate && $0.note?.contains("Hypothetical exercise") == true })
        #expect(ShelterSuitability.confirmedRoom(in: home) == nil, "The actual home still needs a recorded selection")
        for grade in [ExteriorGrade.unknown, .aboveGround] {
            var excluded = home; excluded.floors[0].exteriorGrade = grade
            let attempted = InterventionApplier.apply([intervention], household: household, home: excluded).1
            #expect(attempted == excluded, "A hypothetical answer cannot override unsuitable recorded floor facts")
        }
    }
}
