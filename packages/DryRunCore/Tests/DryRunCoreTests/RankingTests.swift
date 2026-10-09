import Foundation
import Testing
@testable import DryRunCore

@Suite("Ranking")
struct RankingTests {
    private func rec(_ id: String, _ tier: PriorityTier, _ effort: EffortBand, scenarios: Int = 1) -> Recommendation {
        Recommendation(actionID: id, tier: tier, titleKey: "", whyKey: "", matchedFactIDs: [], causeEventIDs: [],
                       scenarioIDs: Array(repeating: "s", count: scenarios).enumerated().map { "s\($0.offset)" }, tryIntervention: nil,
                       modeledEffectKey: nil, effort: effort, sourceIDs: [], verificationStatus: .unknown)
    }

    @Test("Low cost never outranks a critical dependency; ties break by effort, breadth, then ID")
    func lexicographic() {
        let ranked = RecommendationRanker.rank([
            rec("act.z.cheap-general", .general, .noCost, scenarios: 6),
            rec("act.b.critical-expensive", .unmetEssentialRequirement, .high),
            rec("act.a.critical-cheap", .unmetEssentialRequirement, .noCost),
            rec("act.c.unknown", .blockingUnknownFact, .noCost),
            rec("act.d.multi", .multiScenarioPreparation, .low, scenarios: 4),
            rec("act.e.multi-broad", .multiScenarioPreparation, .low, scenarios: 6),
        ])
        #expect(ranked.map(\.actionID) == ["act.a.critical-cheap", "act.b.critical-expensive", "act.c.unknown",
                                          "act.e.multi-broad", "act.d.multi", "act.z.cheap-general"])
        // Order independence.
        #expect(RecommendationRanker.rank(ranked.reversed()) == ranked)
    }

    @Test("Duplicates merge to the most urgent tier")
    func merge() {
        let r = RecommendationRanker.rank([rec("act.x", .scenarioSupplyOrContinuityGap, .low), rec("act.x", .unmetEssentialRequirement, .low)])
        #expect(r.count == 1 && r[0].tier == .unmetEssentialRequirement)
    }

    @Test("Every card explains what, why, causes, effect, unconfirmed facts and sources")
    func cardsComplete() throws {
        for h in SampleHouseholds.all {
            for s in SimFixtures.scenarioIDs {
                let r = try SimFixtures.run(h, s)
                #expect(r.recommendations.count <= 12)
                for c in r.recommendations {
                    #expect(!c.sourceIDs.isEmpty, "\(c.actionID) sources")
                    #expect(c.tier == .multiScenarioPreparation || c.tier == .general || !c.matchedFactIDs.isEmpty || !c.causeEventIDs.isEmpty,
                            "\(c.actionID) needs matched facts or causes")
                    #expect((c.tryIntervention == nil) == (c.modeledEffectKey == nil))
                }
                // Includes at least one no-cost action.
                #expect(r.recommendations.contains { $0.effort == .noCost })
                // Tier order is non-decreasing.
                #expect(zip(r.recommendations, r.recommendations.dropFirst()).allSatisfy { $0.tier <= $1.tier })
            }
        }
    }

    @Test("content/actions/actions.json matches ActionCatalog.builtIn")
    func catalogFileMatches() throws {
        let url = SimFixtures.repoRoot.appendingPathComponent("content/actions/actions.json")
        let data = try DryRunJSON.encoder().encode(ActionCatalog.builtIn)
        if ProcessInfo.processInfo.environment["DRYRUN_WRITE_FIXTURES"] != nil { try data.write(to: url) }
        let onDisk = try DryRunJSON.decoder().decode(ActionCatalog.self, from: Data(contentsOf: url))
        #expect(onDisk == ActionCatalog.builtIn)
    }

    @Test("Every key the engine can emit exists in English")
    func englishKeysExist() throws {
        let root = SimFixtures.repoRoot.appendingPathComponent("content/locales/en")
        var en: [String: String] = [:]
        for f in ["scenarios.json", "actions.json"] {
            en.merge(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent(f)))) { a, _ in a }
        }
        var missing = Set<String>()
        func need(_ k: String?) { if let k, en[k] == nil { missing.insert(k) } }
        for s in SimFixtures.library.scenarios {
            need(s.titleKey); need(s.summaryKey); need(s.startingConditionsKey)
            s.phases.forEach { need($0.titleKey) }; s.variants.forEach { need($0.labelKey) }; s.debrief.pointKeys.forEach(need)
            s.events.forEach { need($0.titleKey); need($0.detailKey) }
            for c in s.choicePoints { need(c.promptKey); c.options.forEach { need($0.labelKey); need($0.feedbackKey) } }
        }
        let variantSets: [String: [[String]]] = [
            "home-fire": [[], ["second-exit-blocked"]], "water-outage": [[], ["do-not-drink"], ["do-not-use", "with-power-loss"]],
            "tornado": [[], ["night", "home-damaged"]], "flash-flood": [[], ["home-flooded"]],
        ]
        for h in SampleHouseholds.all {
            for s in SimFixtures.scenarioIDs {
                for v in variantSets[s] ?? [[]] {
                    let r = try SimFixtures.run(h, s, variants: v)
                    for e in r.events {
                        need(e.titleKey); need(e.detailKey)
                        if let reason = e.templateValues["reason"] { need("reason.\(reason)") }
                        if let ind = e.templateValues["independence"] { need("independence.\(ind)") }
                        if let adv = e.templateValues["advisory"] { need("advisory.\(adv)") }
                    }
                    for c in r.recommendations {
                        need(c.titleKey); need(c.whyKey); need(c.modeledEffectKey); c.feasibilityNotes.forEach(need)
                    }
                }
            }
        }
        for svc in ["power.home", "heat", "cooling", "refrigeration", "wellPump", "water.supply", "water.safety", "wifi", "transport", "alerts", "device"] {
            for st in ServiceState.allCases { need("service.\(svc).\(st.rawValue)") }
        }
        #expect(missing.sorted() == [])
    }
}
