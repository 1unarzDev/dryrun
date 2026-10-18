import Foundation
import Testing
@testable import DryRunCore

/// Cross-lane integration: bundled content + scenario packs + engine + real EgressPlanner + plan builder.
/// Everything here is pure and offline (no network, no LLM), which is the demo's offline guarantee.
@Suite("End-to-end offline integration")
struct PlanIntegrationTests {
    static let scenarioIDs = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]

    struct Env {
        let content: ContentLibrary
        let library: ScenarioLibrary
        let engine: RehearsalEngine
    }

    static func env() throws -> Env {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let library = try ScenarioLibrary.load(from: LeadTestSupport.contentRoot.appendingPathComponent("scenarios"))
        return Env(content: content, library: library, engine: RehearsalEngine(library: library, planner: EgressPlanner()))
    }

    static func input(_ env: Env, _ h: HouseholdProfile, _ scenarioID: String, home: HomeModel = SampleHomes.ranch) throws -> RehearsalInput {
        let s = try #require(env.library.scenarios.first { $0.id == scenarioID })
        return RehearsalInput(household: h, home: home, scenarioID: scenarioID, scenarioVersion: s.version,
                              contentVersion: env.content.contentVersion, seed: 7)
    }

    @Test("All six scenario packs load with distinct IDs")
    func sixPacks() throws {
        let e = try Self.env()
        #expect(Set(e.library.scenarios.map(\.id)) == Set(Self.scenarioIDs))
        #expect(e.content.issues.filter { $0.path.hasPrefix("locales/") && !$0.path.contains("manifest") }.isEmpty)
    }

    @Test("Every household x scenario runs offline, deterministically, and every emitted key resolves in English")
    func allRunsResolve() throws {
        let e = try Self.env()
        let en = e.content.localizer(for: "en")
        var missing = Set<String>()
        for h in SampleHouseholds.all {
            for id in Self.scenarioIDs {
                let input = try Self.input(e, h, id)
                let r1 = try e.engine.run(input)
                let r2 = try e.engine.run(input)
                #expect(r1 == r2, "\(h.id)/\(id) is not deterministic")
                #expect(!r1.events.isEmpty, "\(h.id)/\(id) produced no events")
                var keys = r1.events.flatMap { [$0.titleKey] + ($0.detailKey.map { [$0] } ?? []) }
                keys += r1.decisions.flatMap { [$0.promptKey] + $0.options.flatMap { [$0.labelKey, $0.feedbackKey] } }
                keys += r1.recommendations.flatMap { [$0.titleKey, $0.whyKey] + ($0.modeledEffectKey.map { [$0] } ?? []) }
                for key in keys where en.text(key).isMissing { missing.insert(key) }
            }
        }
        #expect(missing.isEmpty, "keys missing from content/locales/en: \(missing.sorted())")
    }

    @Test("Each scenario produces a distinct event set for the same household (not just a different title)")
    func distinctScenarios() throws {
        let e = try Self.env()
        var signatures: [String: Set<String>] = [:]
        for id in Self.scenarioIDs {
            let r = try e.engine.run(try Self.input(e, SampleHouseholds.oak, id))
            signatures[id] = Set(r.events.map(\.evidence.ruleID))
        }
        for a in Self.scenarioIDs {
            for b in Self.scenarioIDs where a < b {
                #expect(signatures[a] != signatures[b], "\(a) and \(b) fire identical rules")
            }
        }
    }

    @Test("Fire rehearsal in the verified sample home yields practice routes tied to the home revision")
    func fireRoutes() throws {
        let e = try Self.env()
        let r = try e.engine.run(try Self.input(e, SampleHouseholds.oak, "home-fire"))
        #expect(!r.routes.isEmpty)
        for route in r.routes {
            #expect(route.homeID == SampleHomes.ranch.id && route.homeRevision == SampleHomes.ranch.revision)
            #expect(route.primary != nil || route.noRouteReason != nil, "a route result is either a path or a typed reason")
        }
    }

    @Test("Plans in EN/ES/VI validate: no unresolved keys, visible draft/fallback labels, facts preserved")
    func multilingualPlans() throws {
        let e = try Self.env()
        for h in SampleHouseholds.all {
            let results = try Self.scenarioIDs.map { try e.engine.run(try Self.input(e, h, $0)) }
            for locale in ["en", "es", "vi"] {
                let l = e.content.localizer(for: locale)
                let doc = PlanBuilder.build(household: h, home: SampleHomes.ranch, results: results, localizer: l,
                                            resources: e.content.resources(forRegion: h.regionID),
                                            contentVersion: e.content.contentVersion, generatedAt: LeadTestSupport.fixedDate)
                let issues = PlanValidator.validate(doc, household: h)
                #expect(issues.isEmpty, "\(h.id)/\(locale): \(issues)")
                #expect(doc.pages.count == 8)
                let lines = doc.pages.flatMap(\.sections).flatMap(\.lines)
                if ["US", "CA"].contains(h.privateLocation?.countryCode?.uppercased() ?? "") {
                    #expect(lines.contains { $0.key == "plan.help.911" })
                } else {
                    #expect(lines.contains { $0.key == "plan.help.localUnknown" })
                    #expect(!lines.contains { $0.key == "plan.help.911" })
                }
                if locale != "en" {
                    #expect(doc.draftTranslationBanner != nil, "\(locale) plan must carry the draft-translation banner")
                }
                // Help contacts from the public packs are printed as text with phone numbers.
                if lines.contains(where: { $0.text.contains("211") }) {
                    #expect(lines.contains { $0.text.contains("877-541-7905") })
                }
            }
        }
    }

    @Test("Editing a door's verification changes fire routes and invalidates a saved plan")
    func doorEditInvalidates() throws {
        let e = try Self.env()
        var home = SampleHomes.ranch
        let before = try e.engine.run(try Self.input(e, SampleHouseholds.oak, "home-fire", home: home))
        let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: home, results: [before],
                                    localizer: e.content.localizer(for: "en"), resources: [],
                                    contentVersion: e.content.contentVersion, generatedAt: LeadTestSupport.fixedDate)
        let idx = try #require(home.portals.firstIndex { $0.id == "pt-back" })
        home.portals[idx].verification = .rejected
        home.bumpRevision()
        #expect(doc.isStale(household: SampleHouseholds.oak, home: home, contentVersion: e.content.contentVersion))
        let after = try e.engine.run(try Self.input(e, SampleHouseholds.oak, "home-fire", home: home))
        for route in after.routes {
            #expect(route.homeRevision == home.revision)
            #expect(route.primary?.exitPortalID != "pt-back" && route.alternative?.exitPortalID != "pt-back",
                    "a rejected door must never be used as an exit")
        }
    }
}
