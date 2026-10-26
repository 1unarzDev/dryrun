import Foundation
import Testing
@testable import DryRunCore

/// Opt-in human-readable dump for reviewing rehearsal text: DRYRUN_DUMP=1 scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump
@Suite("Demo dump (opt-in)")
struct PlanDemoDumpTests {
    @Test func dump() throws {
        guard ProcessInfo.processInfo.environment["DRYRUN_DUMP"] == "1" else { return }
        let e = try PlanIntegrationTests.env()
        let l = e.content.localizer(for: "en")
        for (h, id) in [(SampleHouseholds.oak, "freeze-power-loss"), (SampleHouseholds.oak, "home-fire"), (SampleHouseholds.lake, "heat-grid-strain")] {
            let r = try e.engine.run(try PlanIntegrationTests.input(e, h, id))
            print("\n===== \(h.id) / \(id): \(r.events.count) events, \(r.decisions.count) decisions, \(r.recommendations.count) recs")
            for ev in r.events { print("  +\(ev.simMinute)m [\(ev.severity)] \(l(ev.titleKey, ev.templateValues)) — \(ev.detailKey.map { l($0, ev.templateValues) } ?? "")") }
            for d in r.decisions { print("  DECISION \(l(d.promptKey)): " + d.options.map { "\(l($0.labelKey))\($0.isRecommended ? "*" : "")" }.joined(separator: " | ")) }
            for rec in r.recommendations.prefix(5) { print("  REC t\(rec.tier.rawValue) \(l(rec.titleKey, rec.templateValues)) — \(l(rec.whyKey, rec.templateValues)) try=\(rec.tryIntervention?.actionID ?? "-")") }
            print("  unknowns: \(r.unknowns)")
            for rec in r.recommendations where rec.tryIntervention != nil { let iv = rec.tryIntervention!
                let c = try e.engine.compare(r.input, applying: iv)
                print("  COMPARE \(iv.actionID): services \(c.diff.serviceChanges) resolved \(c.diff.resolvedRequirements) +\(c.diff.addedEventIDs.count)/-\(c.diff.removedEventIDs.count) events")
            }
        }
        let results = try ["home-fire"].map { try e.engine.run(try PlanIntegrationTests.input(e, SampleHouseholds.lake, $0)) }
        let doc = PlanBuilder.build(household: SampleHouseholds.lake, home: SampleHomes.ranch, results: results, localizer: e.content.localizer(for: "vi"),
                                    resources: e.content.resources(forRegion: "48439"), contentVersion: e.content.contentVersion, generatedAt: LeadTestSupport.fixedDate)
        print("\n===== VI plan banner: \(doc.draftTranslationBanner ?? "-") fallback: \(doc.fallbackNote ?? "-")")
        for p in doc.pages { print("## \(p.title)"); for s in p.sections { print("### \(s.heading)"); for ln in s.lines { print("  \(ln.isFallback ? "[EN] " : "")\(ln.text)") } } }
    }
}
