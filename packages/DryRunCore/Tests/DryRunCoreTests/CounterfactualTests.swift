import Foundation
import Testing
@testable import DryRunCore

@Suite("Counterfactual")
struct CounterfactualTests {
    @Test("Try-this-change preserves the baseline and isolates the change")
    func isolation() throws {
        let baseInput = SimFixtures.input(SampleHouseholds.oak, "freeze-power-loss")
        let snapshotOfInput = baseInput
        let baseline = try SimFixtures.engine.run(baseInput)
        let rec = try #require(baseline.recommendations.first { $0.actionID == "act.backup.confirm-medical-backup" })
        let cmp = try SimFixtures.engine.compare(baseInput, applying: try #require(rec.tryIntervention))

        #expect(baseInput == snapshotOfInput)                       // input value untouched
        #expect(cmp.baseline == baseline)                           // baseline identical to an independent run
        #expect(cmp.modified.input.seed == baseInput.seed)
        #expect(cmp.modified.input.scenarioVersion == baseInput.scenarioVersion)
        #expect(cmp.modified.input.contentVersion == baseInput.contentVersion)
        #expect(cmp.modified.input.household == baseInput.household) // the real profile is not changed
        #expect(cmp.modified.input.interventions == [rec.tryIntervention!])

        // Same authored schedule in both runs.
        let authored = Set(SimFixtures.library.scenario("freeze-power-loss")!.events.map(\.id))
        #expect(Set(cmp.baseline.events.map(\.id)).intersection(authored) == Set(cmp.modified.events.map(\.id)).intersection(authored))

        #expect(cmp.diff.resolvedRequirements.contains("req.power.eq-oxygen"))
        #expect(cmp.diff.addedEventIDs.contains("evt.freeze-power-loss.svc.device.eq-oxygen.on-backup"))
        #expect(cmp.diff.removedEventIDs.contains("evt.freeze-power-loss.svc.device.eq-oxygen.unavailable"))
        #expect(cmp.diff.serviceChanges["svc.device.eq-oxygen"] == [.unavailable, .operational])
        // Heat and water are unaffected by a device backup.
        #expect(!cmp.diff.resolvedRequirements.contains("req.heat"))
        #expect(cmp.diff.resolvedRecommendations.contains("act.backup.confirm-medical-backup"))
        // Hypothetical evidence is marked as a scenario assumption.
        #expect(cmp.modified.recommendations.contains { $0.actionID == "act.medical.document-runtime" })
    }

    @Test("Water storage change extends stored water and resolves the water requirement")
    func waterStorage() throws {
        let input = SimFixtures.input(SampleHouseholds.oak, "freeze-power-loss")
        let cmp = try SimFixtures.engine.compare(input, applying: Intervention(actionID: "act.water.store-3day"))
        #expect(cmp.diff.resolvedRequirements.contains("req.water"))
        #expect(cmp.diff.removedEventIDs.contains("evt.freeze-power-loss.res.water-depleted"))
        let applied = InterventionApplier.apply([Intervention(actionID: "act.water.store-3day")], household: SampleHouseholds.oak, home: SimFixtures.home).0
        #expect(applied.supplies.storedWaterGallons.value == 12)
        #expect(applied.supplies.storedWaterGallons.origin == .scenarioAssumption)
    }

    @Test("Every modelable recommendation changes something in its replay")
    func everyTryHasEffect() throws {
        for h in SampleHouseholds.all {
            for s in SimFixtures.scenarioIDs {
                let input = SimFixtures.input(h, s)
                let base = try SimFixtures.engine.run(input)
                for rec in base.recommendations {
                    guard let i = rec.tryIntervention else { continue }
                    let cmp = try SimFixtures.engine.compare(input, applying: i)
                    let d = cmp.diff
                    let changed = !d.addedEventIDs.isEmpty || !d.removedEventIDs.isEmpty || !d.serviceChanges.isEmpty
                        || !d.resolvedRequirements.isEmpty || !d.resourceChanges.isEmpty || cmp.baseline.events != cmp.modified.events
                    #expect(changed, "\(h.id) \(s) \(rec.actionID) had no modelled effect")
                }
            }
        }
    }

    @Test("Expected-outcome fixtures for the flagship freeze cascade")
    func fixtures() throws {
        struct Expected: Codable, Equatable {
            var scenarioID: String
            var householdID: String
            var intervention: String?
            var eventIDs: [String]
            var unmetRequirements: [String]
            var recommendationOrder: [String]
            var resolvedRequirements: [String]?
        }
        let input = SimFixtures.input(SampleHouseholds.oak, "freeze-power-loss")
        let base = try SimFixtures.engine.run(input)
        let cmp = try SimFixtures.engine.compare(input, applying: Intervention(actionID: "act.backup.confirm-medical-backup", parameters: ["equipment": "eq-oxygen"]))
        let cases: [(String, Expected)] = [
            ("freeze-oak-baseline.expected.json",
             Expected(scenarioID: "freeze-power-loss", householdID: "hh-oak", intervention: nil, eventIDs: base.events.map(\.id),
                      unmetRequirements: Array(Set(base.snapshots.flatMap(\.unmetRequirements))).sorted(),
                      recommendationOrder: base.recommendations.map(\.actionID), resolvedRequirements: nil)),
            ("freeze-oak-backup-comparison.expected.json",
             Expected(scenarioID: "freeze-power-loss", householdID: "hh-oak", intervention: "act.backup.confirm-medical-backup",
                      eventIDs: cmp.modified.events.map(\.id),
                      unmetRequirements: Array(Set(cmp.modified.snapshots.flatMap(\.unmetRequirements))).sorted(),
                      recommendationOrder: cmp.modified.recommendations.map(\.actionID), resolvedRequirements: cmp.diff.resolvedRequirements)),
        ]
        for (name, actual) in cases {
            let url = SimFixtures.repoRoot.appendingPathComponent("fixtures/scenarios/\(name)")
            if ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] == "1" {
                try DryRunJSON.encoder().encode(actual).write(to: url)
            }
            let expected = try DryRunJSON.decoder().decode(Expected.self, from: Data(contentsOf: url))
            #expect(expected == actual, "\(name) drifted; regenerate with DRYRUN_WRITE_FIXTURES=1 only after reviewing the change")
        }
    }
}

@Suite("Counterfactual relocation")
struct CounterfactualRelocationTests {
    @Test("Trying an arranged relocation takes the relocation branch in the replay only")
    func relocationBranch() throws {
        let input = SimFixtures.input(SampleHouseholds.oak, "freeze-power-loss")
        let base = try SimFixtures.engine.run(input)
        let rec = try #require(base.recommendations.first { $0.actionID == "act.relocation.arrange" })
        #expect(rec.tryIntervention?.parameters["choice.freeze-power-loss.keep-warm"] == "relocate")
        let cmp = try SimFixtures.engine.compare(input, applying: rec.tryIntervention!)
        #expect(cmp.diff.addedEventIDs.contains("evt.freeze-power-loss.relocation.done"))
        #expect(cmp.diff.removedEventIDs.contains("evt.freeze-power-loss.res.water-depleted"))
        #expect(cmp.diff.resolvedRequirements.contains("req.water"))
        #expect(cmp.baseline.events.first { $0.id == "evt.choice.freeze-power-loss.keep-warm" }?.templateValues["option"] == "layer-up")
        #expect(input.choices.isEmpty)

        let lake = SimFixtures.input(SampleHouseholds.lake, "heat-grid-strain")
        let lakeRec = try #require(try SimFixtures.engine.run(lake).recommendations.first { $0.actionID == "act.relocation.arrange" })
        let lakeCmp = try SimFixtures.engine.compare(lake, applying: lakeRec.tryIntervention!)
        #expect(lakeCmp.diff.addedEventIDs.contains("evt.heat-grid-strain.relocation.done"))
    }
}
