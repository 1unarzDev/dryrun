import Foundation
import Testing
@testable import DryRunCore

@Suite("Six hazard readiness setup and current-state scenes")
struct RehearsalExperienceDesignTests {
    @Test func everySetupOptionRunsARealPackAgainstTheSameHome() throws {
        for hazard in HazardKind.allCases {
            let design = RehearsalExperienceDesign.design(for: hazard)
            let scenario = try #require(SimFixtures.library.scenario(design.scenarioID))
            #expect(design.questions.count >= 2)
            for question in design.questions {
                #expect(question.options.count >= 2)
                for option in question.options {
                    let variants = try design.variants(answers: [question.id: option.id], scenario: scenario)
                    let input = SimFixtures.input(SampleHouseholds.oak, design.scenarioID, variants: variants)
                    let before = try DryRunJSON.encoder().encode(input)
                    let result = try SimFixtures.engine.run(input)
                    #expect(result.input.variants == variants)
                    #expect(try DryRunJSON.encoder().encode(input) == before)
                    #expect(result.decisions.count >= 2, "\(design.scenarioID):\(question.id):\(option.id)")
                    for snapshot in result.snapshots {
                        let scene = try RehearsalScenePresentation(hazard: hazard, snapshot: snapshot, baseline: result.snapshots.first,
                            visibleEvents: result.events.filter { $0.simMinute <= snapshot.simMinute }, snapshotHistory: result.snapshots)
                        #expect(scene.design.hazard == hazard)
                        #expect(scene.services == snapshot.services)
                        #expect(Dictionary(uniqueKeysWithValues: scene.resources.map { ($0.id, $0.current) }) == snapshot.resources)
                        #expect(scene.temperature == nil && scene.outsidePersonIDs == nil && scene.shelteredPersonIDs == nil)
                    }
                }
            }
        }
    }
    @Test func everyConditionOptionChangesHostStateOrAnEvaluatedDependency() throws {
        var household = SampleHouseholds.oak
        household.housing.waterSource = .municipal // Same explicit source mutation for all six.
        struct State: Equatable {
            var services: [String:ServiceState]
            var resources: [String:ResourceQuantity]
            var unmet: [String]
            var affectedRooms: [String]
            var affectedOpenings: [String]
            var routes: [RouteResult]
        }
        func effects(_ snapshots: [SimulationSnapshot]) -> [State] {
            var sequence: [State] = []
            for snapshot in snapshots {
                let state = State(services: snapshot.services, resources: snapshot.resources, unmet: snapshot.unmetRequirements.sorted(),
                    affectedRooms: snapshot.spatialState?.affectedSpaceIDs.sorted() ?? [],
                    affectedOpenings: snapshot.spatialState?.affectedPortalIDs.sorted() ?? [], routes: snapshot.spatialState?.routes ?? [])
                // Extra note events, timestamps and repeated identical snapshots are not physical changes.
                if sequence.last != state { sequence.append(state) }
            }
            return sequence
        }
        struct Check: Codable {
            var scenarioID: String
            var questionID: String
            var optionID: String
            var stateChanged: Bool
            var evaluatedRulesChanged: Bool
            var addedRuleIDs: [String]
            var removedRuleIDs: [String]
        }
        var checks: [Check] = []
        for hazard in HazardKind.allCases {
            let design = RehearsalExperienceDesign.design(for: hazard, waterSource: .municipal)
            let scenario = try #require(SimFixtures.library.scenario(design.scenarioID))
            let baseline = try SimFixtures.run(household, design.scenarioID)
            for question in design.questions {
                for option in question.options where !option.variantIDs.isEmpty {
                    let variants = try design.variants(answers: [question.id: option.id], scenario: scenario)
                    let changed = try SimFixtures.run(household, design.scenarioID, variants: variants)
                    let stateChanged = effects(baseline.snapshots) != effects(changed.snapshots)
                    let beforeRules = Set(baseline.events.map { $0.evidence.ruleID })
                    let afterRules = Set(changed.events.map { $0.evidence.ruleID })
                    let rulesChanged = beforeRules != afterRules
                    #expect(stateChanged || rulesChanged, "No host effect for \(question.id):\(option.id)")
                    #expect(changed.input.household == baseline.input.household && changed.input.home == baseline.input.home)
                    checks.append(.init(scenarioID: design.scenarioID, questionID: question.id, optionID: option.id,
                                        stateChanged: stateChanged, evaluatedRulesChanged: rulesChanged,
                                        addedRuleIDs: afterRules.subtracting(beforeRules).sorted(), removedRuleIDs: beforeRules.subtracting(afterRules).sorted()))
                }
            }
        }
        #expect(Set(checks.map(\.scenarioID)).count == 6)
        if ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1" {
            try DryRunJSON.encoder().encode(checks).write(to: SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/readiness-condition-effects.json"), options: .atomic)
        }
    }

    @Test func setupRejectsUnknownInputsAndSeparatesFocusFromFacts() throws {
        let heat = RehearsalExperienceDesign.design(for: .heatGridStrain)
        let scenario = try #require(SimFixtures.library.scenario(heat.scenarioID))
        #expect(throws: SessionError.invalidCommand) { try heat.variants(answers: ["not-a-question":"recorded"], scenario: scenario) }
        #expect(throws: SessionError.invalidCommand) { try heat.variants(answers: ["heat-grid-strain.grid":"invented"], scenario: scenario) }
        #expect(throws: SessionError.invalidCommand) { try heat.variants(answers: [:], scenario: SimFixtures.library.scenario("home-fire")!) }
        #expect(try heat.variants(answers: ["heat-grid-strain.focus":"water"], scenario: scenario).isEmpty)
        #expect(heat.focusedServiceIDs(answers: ["heat-grid-strain.focus":"water"]).first == Svc.waterSupply)
        let flood = RehearsalExperienceDesign.design(for: .flashFlood)
        #expect(try flood.variants(answers: ["flash-flood.event":"householdLeak", "flash-flood.extent":"home-flooded"],
            scenario: SimFixtures.library.scenario("flash-flood")!) == ["householdLeak"])
    }
    @Test func wellSetupCannotOfferMunicipalAdvisoryVariants() throws {
        let well = try #require(RehearsalExperienceDesign.design(scenarioID: "water-outage", household: SampleHouseholds.oak))
        #expect(well.questions.count == 2)
        #expect(well.questions.allSatisfy { !$0.id.hasSuffix(".advisory") })
        let municipal = RehearsalExperienceDesign.design(for: .waterOutage, waterSource: .municipal)
        #expect(municipal.questions.contains { $0.id.hasSuffix(".advisory") })
        #expect(throws: SessionError.invalidCommand) { try well.variants(answers: ["water-outage.advisory":"do-not-use"], scenario: SimFixtures.library.scenario("water-outage")!) }
    }
    @Test func barsPreserveUnknownEmptyUnitsAndFiniteValues() {
        func visual(_ amount: Double?, _ baseline: Double?, unit: String = "Wh", originalUnit: String = "Wh") -> RehearsalResourceVisual {
            .init(id: "test", current: .init(amount: amount, unit: unit), baseline: .init(amount: baseline, unit: originalUnit))
        }
        #expect(visual(nil, 100).remainingFraction == nil)
        #expect(visual(0, 100).remainingFraction == 0)
        #expect(visual(50, 100).remainingFraction == 0.5)
        #expect(visual(120, 100).remainingFraction == 1)
        #expect(visual(50, 0).remainingFraction == nil)
        #expect(visual(50, 100, unit: "h").remainingFraction == nil)
        #expect(visual(.infinity, 100).remainingFraction == nil)
        #expect(visual(-1, 100).remainingFraction == nil)
        #expect(visual(40, 100).change == -60)
    }
    @Test func advisoryUsesOnlyAppliedVisibleEventsAndNeverLeaksAcrossHazards() throws {
        func event(_ id: String, _ minute: Int, _ advisory: String) -> SimulationEvent {
            .init(id: id, simMinute: minute, phaseID: "test", titleKey: "test", templateValues: ["advisory":advisory], evidence: .init(ruleID:"test"))
        }
        let applied = event("applied", 5, "boilWater"), future = event("future", 30, "doNotUse"), unfired = event("unfired", 6, "doNotDrink")
        let snapshot = SimulationSnapshot(simMinute: 10, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: ["applied","future"])
        let before = snapshot
        let water = try RehearsalScenePresentation(hazard: .waterOutage, snapshot: snapshot, baseline: nil, visibleEvents: [applied, unfired, future])
        #expect(water.advisory == .boilWater)
        #expect(snapshot == before)
        let heat = try RehearsalScenePresentation(hazard: .heatGridStrain, snapshot: snapshot, baseline: nil, visibleEvents: [applied])
        #expect(heat.advisory == nil)
        let empty = try RehearsalScenePresentation(hazard: .waterOutage, snapshot: snapshot, baseline: nil)
        #expect(empty.advisory == nil)
    }
    @Test func incrementalProjectionCarriesActualExperienceAndRejectsWrongHazard() throws {
        let session = try SimulationSession.initialize(id: "scene-projection", initial: SimFixtures.input(SampleHouseholds.oak,"heat-grid-strain"), library: SimFixtures.library)
        let receipt = try session.query(library: SimFixtures.library)
        let experience = try #require(receipt.experience)
        let snapshot = receipt.snapshot
        let scene = try RehearsalScenePresentation(hazard: .heatGridStrain, snapshot: snapshot, baseline: nil, experience: experience)
        #expect(scene.temperature == experience.temperature)
        #expect(scene.roomTemperatures == experience.roomTemperatures)
        #expect(scene.relocated == experience.relocated)
        #expect(throws: SessionError.invalidCommand) { try RehearsalScenePresentation(hazard: .homeFire, snapshot: snapshot, baseline: nil, experience: experience) }
    }
    @Test func actualWaterAdvisoryPersistsAtLaterCursorBoundaries() throws {
        var household = SampleHouseholds.oak
        household.housing.waterSource = .municipal
        let result = try SimFixtures.run(household, "water-outage", variants: ["do-not-use"])
        let advisoryEvent = try #require(result.events.first { $0.templateValues["advisory"] == "doNotUse" })
        var checked = 0
        for snapshot in result.snapshots where snapshot.simMinute > advisoryEvent.simMinute {
            let scene = try RehearsalScenePresentation(hazard: .waterOutage, snapshot: snapshot, baseline: result.snapshots.first,
                visibleEvents: result.events.filter { $0.simMinute <= snapshot.simMinute }, snapshotHistory: result.snapshots)
            #expect(scene.advisory == .doNotUse)
            checked += 1
        }
        #expect(checked > 2)
        let initial = try #require(result.snapshots.first)
        let hidden = try RehearsalScenePresentation(hazard: .waterOutage, snapshot: initial, baseline: nil,
            visibleEvents: result.events, snapshotHistory: result.snapshots)
        #expect(hidden.advisory != .doNotUse)
    }
    @Test func poweredHeatFollowupBranchesOnRecordedArrangementWithoutInventingOutage() throws {
        var household = SampleHouseholds.oak
        household.transport.vehicles[0].wheelchairAccessible = .confirmed(true)
        household.transport.destinations = [.init(id: "synthetic-cooling", kind: .friendOrFamilyHome, label: "Synthetic alternative",
            conditionsConfirmed: .confirmed(true), acceptsPets: .confirmed(true), stepFreeAccess: .confirmed(true))]
        let design = RehearsalExperienceDesign.design(for: .heatGridStrain)
        let variants = try design.variants(answers: ["heat-grid-strain.grid":"no-rotating-outage"], scenario: SimFixtures.library.scenario("heat-grid-strain")!)
        let first = "choice.heat-grid-strain.hottest-hours", later = "choice.heat-grid-strain.powered-evening"
        let stay = try SimFixtures.run(household, "heat-grid-strain", choices: [first:"stay-cool",later:"stay"], variants: variants)
        let leave = try SimFixtures.run(household, "heat-grid-strain", choices: [first:"stay-cool",later:"relocate"], variants: variants)
        #expect(stay.decisions.count == 2 && leave.decisions.count == 2)
        #expect(stay.events.allSatisfy { $0.serviceChanges[Svc.grid] != .unavailable })
        #expect(leave.events.contains { $0.evidence.ruleID == "rule.relocation" && $0.titleKey == "scenario.common.relocation.done" })
        #expect(!stay.events.contains { $0.titleKey == "scenario.common.relocation.done" })
        #expect(leave.events.contains { $0.titleKey == "scenario.common.relocation.done" && $0.evidence.causedByEventIDs.contains("evt." + later) })
        household.transport.destinations = []
        let missing = try SimFixtures.run(household, "heat-grid-strain", choices: [first:"stay-cool",later:"relocate"], variants: variants)
        #expect(missing.events.contains { $0.titleKey == "scenario.common.relocation.blocked" })
        #expect(missing.snapshots.last?.unmetRequirements.contains("req.relocation") == true)
    }
    @Test func sixDesignsAndSetupVariantsRoundTripWithoutEditingFacts() throws {
        struct Run: Codable {
            var design: RehearsalExperienceDesign
            var answers: [String:String]
            var input: RehearsalInput
            var scenes: [RehearsalScenePresentation]
            var decisions: [DecisionPoint]
        }
        struct Export: Codable {
            var version = "dryrun.rehearsal-experience-review/1"
            var synthetic = true
            var nativeVerified = false
            var modelCalls = 0
            var runs: [Run]
        }
        var runs: [Run] = []
        for hazard in HazardKind.allCases {
            let design = RehearsalExperienceDesign.design(for: hazard, waterSource: SampleHouseholds.oak.housing.waterSource)
            let scenario = try #require(SimFixtures.library.scenario(design.scenarioID))
            for alternate in [false,true] {
                let answers = Dictionary(uniqueKeysWithValues: design.questions.map { ($0.id, alternate ? $0.options.last!.id : $0.defaultOptionID) })
                let variants = try design.variants(answers: answers, scenario: scenario)
                let input = SimFixtures.input(SampleHouseholds.oak, design.scenarioID, variants: variants)
                let result = try SimFixtures.engine.run(input)
                #expect(result.input.household == SampleHouseholds.oak)
                #expect(result.input.home == SimFixtures.home)
                #expect(result.decisions.count >= 2)
                let scenes = try result.snapshots.map { snapshot in
                    try RehearsalScenePresentation(hazard: hazard, snapshot: snapshot, baseline: result.snapshots.first,
                        visibleEvents: Array(result.events.prefix(snapshot.revealedEventCount ?? result.events.count)), snapshotHistory: result.snapshots)
                }
                #expect(try DryRunJSON.decoder().decode([RehearsalScenePresentation].self, from: DryRunJSON.encoder().encode(scenes)) == scenes)
                runs.append(.init(design: design, answers: answers, input: input, scenes: scenes, decisions: result.decisions))
            }
        }
        #expect(Set(runs.map { $0.design.sceneKey }).count == 6)
        #expect(Set(runs.map { $0.design.objectiveKey }).count == 6)
        if ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1" {
            try DryRunJSON.encoder().encode(Export(runs: runs)).write(to: SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/rehearsal-experience-review.json"), options: .atomic)
        }
    }
    @Test func everyExperienceStringResolvesInEverySupportedLocale() throws {
        let library = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let english = library.tables["en"]?["native"] ?? [:]
        let keys = english.keys.filter { $0.hasPrefix("experience.") }
        #expect(keys.count >= 112)
        for locale in ["en", "es", "vi"] {
            let l = Localizer(locale: locale, tables: library.tables, manifest: library.localeManifest)
            for key in keys {
                let value = l.text(key, ["quantity":"1 Wh", "reason":"test", "count":"1", "a":"room A", "b":"room B", "steps":"route", "connections":"hall"])
                #expect(!value.isMissing && !value.isFallback && value.unfilledPlaceholders.isEmpty, "\(locale):\(key)")
            }
        }
    }
}
