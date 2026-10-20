import Foundation
import Testing
@testable import DryRunCore

@Suite("Completed rehearsal outcome evidence")
struct RehearsalDebriefEvidenceTests {
    /// Answer each reached decision explicitly, retaining the engine's actual conditional schedule.
    private func completed(_ input: RehearsalInput) throws -> RehearsalCursor {
        var cursor = RehearsalCursor(result: try SimFixtures.engine.run(input))
        for _ in 0..<40 {
            cursor.advanceUntilDecisionOrEnd()
            if cursor.isFinished { return cursor }
            let decision = try #require(cursor.pendingDecision)
            let option = try #require(decision.options.first)
            var next = cursor.result.input
            next.choices[decision.id] = option.id
            cursor.replace(result: try SimFixtures.engine.run(next))
        }
        Issue.record("Rehearsal never finished")
        throw SessionError.invalidCommand
    }

    @Test func incompleteRunCannotProduceFinalOutcomes() throws {
        let cursor = RehearsalCursor(result: try SimFixtures.run(SampleHouseholds.oak, "home-fire"))
        #expect(throws: SessionError.invalidCommand) { try RehearsalDebriefEvidence(completed: cursor) }
    }

    @Test func allSixUseOnlyTheirActualCompletedStateAndRoundTrip() throws {
        let household = SampleHouseholds.oak
        let purposes: [String:RoutePurpose] = ["home-fire":.outdoorEgress, "tornado":.interiorShelter, "flash-flood":.higherRefuge]
        let services: [String:[String]] = ["home-fire":[], "tornado":[Svc.alerts], "flash-flood":[Svc.roads,Svc.transport],
            "freeze-power-loss":[Svc.heat,Svc.homePower], "heat-grid-strain":[Svc.cooling,Svc.homePower], "water-outage":[Svc.waterSupply]]
        var exported: [RehearsalDebriefEvidence] = []
        for id in SimFixtures.scenarioIDs {
            let input = SimFixtures.input(household, id)
            let original = try DryRunJSON.encoder().encode(input)
            let cursor = try completed(input)
            let evidence = try RehearsalDebriefEvidence(completed: cursor)
            let final = try #require(cursor.result.snapshots.last)
            exported.append(evidence)
            #expect(Set(evidence.routes.compactMap { $0.request.personID }).count == evidence.routes.count)
            #expect(evidence.scene.design.scenarioID == id)
            #expect(evidence.scene.services == final.services)
            #expect(evidence.serviceIDs == services[id])
            if let purpose = purposes[id] {
                #expect(evidence.routes == (final.spatialState?.routes ?? []).filter { $0.request.purpose == purpose })
                #expect(!evidence.routes.isEmpty)
            } else { #expect(evidence.routes.isEmpty) }
            #expect(evidence.scene.temperature == nil)
            #expect(evidence.scene.outsidePersonIDs == nil && evidence.scene.shelteredPersonIDs == nil)
            #expect(evidence.unresolvedRequirementIDs == final.unmetRequirements.sorted())
            for resource in evidence.resourceReadings {
                #expect(resource.current == final.resources[resource.id])
                #expect(resource.baseline == cursor.result.snapshots.first?.resources[resource.id])
            }
            #expect(cursor.result.input.household == household && cursor.result.input.home == SimFixtures.home)
            #expect(try DryRunJSON.encoder().encode(input) == original)
            let replay = try completed(cursor.result.input)
            #expect(try RehearsalDebriefEvidence(completed: replay) == evidence)
            #expect(try DryRunJSON.decoder().decode(RehearsalDebriefEvidence.self, from: DryRunJSON.encoder().encode(evidence)) == evidence)
        }
        if ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1" {
            try DryRunJSON.encoder().encode(exported).write(to: SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/rehearsal-debrief-outcomes.json"), options: .atomic)
        }
    }

    @Test func completedOutcomesRejectMissingSnapshotsAndKeepUnknownDistinctFromEmpty() throws {
        let cursor = try completed(SimFixtures.input(SampleHouseholds.oak, "water-outage"))
        var noSnapshots = cursor.result
        noSnapshots.snapshots = []
        var invalid = cursor; invalid.replace(result: noSnapshots)
        #expect(throws: SessionError.invalidCommand) { try RehearsalDebriefEvidence(completed: invalid) }
        for amount: Double? in [nil, 0] {
            var result = cursor.result
            let last = result.snapshots.count - 1
            result.snapshots[last].resources["res.water.stored"] = .init(amount: amount, unit: "gal")
            var changed = cursor; changed.replace(result: result)
            let evidence = try RehearsalDebriefEvidence(completed: changed)
            let reading = try #require(evidence.resourceReadings.first { $0.id == "res.water.stored" })
            #expect(reading.current.amount == amount)
            if amount == nil { #expect(reading.remainingFraction == nil && reading.change == nil) }
            else { #expect(reading.remainingFraction == 0) }
        }
    }

    @Test func relocationUsesCausalEventsAndCannotBeInferredFromAvailableTransport() throws {
        var household = SampleHouseholds.oak
        household.transport.vehicles[0].wheelchairAccessible = .confirmed(true)
        household.transport.destinations = [.init(id: "synthetic-cooling", kind: .friendOrFamilyHome, label: "Synthetic alternative",
            conditionsConfirmed: .confirmed(true), acceptsPets: .confirmed(true), stepFreeAccess: .confirmed(true))]
        let choices = ["choice.heat-grid-strain.hottest-hours":"stay-cool", "choice.heat-grid-strain.powered-evening":"relocate"]
        let variants = ["no-rotating-outage", "cooling-followup"]
        let usedCursor = try completed(SimFixtures.input(household, "heat-grid-strain", choices: choices, variants: variants))
        let used = try RehearsalDebriefEvidence(completed: usedCursor)
        #expect(used.relocation == .used && !used.relocationEventIDs.isEmpty)
        for id in used.relocationEventIDs {
            let event = try #require(usedCursor.result.events.first { $0.id == id })
            #expect(event.evidence.ruleID == "rule.relocation")
            #expect(event.titleKey == "scenario.common.relocation.done")
            #expect(!event.evidence.causedByEventIDs.isEmpty)
        }
        var stayChoices = choices; stayChoices["choice.heat-grid-strain.powered-evening"] = "stay"
        let stayed = try RehearsalDebriefEvidence(completed: completed(SimFixtures.input(household, "heat-grid-strain", choices: stayChoices, variants: variants)))
        #expect(stayed.relocation == .notRecorded && stayed.relocationEventIDs.isEmpty)
        household.transport.destinations = []
        let blocked = try RehearsalDebriefEvidence(completed: completed(SimFixtures.input(household, "heat-grid-strain", choices: choices, variants: variants)))
        #expect(blocked.relocation == .blocked && !blocked.relocationEventIDs.isEmpty)
        #expect(blocked.unresolvedRequirementIDs.contains("req.relocation"))
    }

    @Test func advisorySurvivesThroughTheFinalOutcomeWithoutChangingSupplyFacts() throws {
        var household = SampleHouseholds.oak
        household.housing.waterSource = .municipal
        for (variant, expected) in [("", WaterAdvisory.boilWater), ("do-not-drink", .doNotDrink), ("do-not-use", .doNotUse)] {
            let cursor = try completed(SimFixtures.input(household, "water-outage", variants: variant.isEmpty ? [] : [variant]))
            let evidence = try RehearsalDebriefEvidence(completed: cursor)
            #expect(evidence.scene.advisory == expected)
            #expect(evidence.resourceReadings.map(\.id) == ["res.water.stored"])
            #expect(evidence.scene.services == cursor.result.snapshots.last?.services)
        }
    }
}
