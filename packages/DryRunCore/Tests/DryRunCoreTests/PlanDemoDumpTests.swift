import Foundation
import Testing
@testable import DryRunCore

/// Opt-in human-readable dump for reviewing rehearsal text: DRYRUN_DUMP=1 scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump
@Suite("Demo dump (opt-in)")
struct PlanDemoDumpTests {
    @Test func dump() throws {
        guard ProcessInfo.processInfo.environment["DRYRUN_DUMP"] == "1" else { return }
        let e = try PlanIntegrationTests.env()
        try writeExamples(e)
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
    /// Opt-in artifacts use fictional data only. These snapshots feed the portable reference renderer;
    /// they are not native CoreText/PDFKit output or simulator screenshots.
    private func writeExamples(_ e: PlanIntegrationTests.Env) throws {
        let dir = LeadTestSupport.repoRoot.appendingPathComponent("output/plan-examples")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for locale in ["en", "es", "vi"] {
            var h = SampleHouseholds.oak
            h.homeID = SampleHomes.ranch.id
            h.preferredLocale = locale
            h.privateLocation = PrivateLocation(addressLine: "123 Example Lane, Fictional Town", latitude: 32.2, longitude: -98.2, countryCode: "US")
            h.contacts = [HouseholdContact(id: "example-contact", role: .outOfAreaContact, alias: "Example trusted contact", phone: "+1 202 555 0148", relationship: "Family friend")]
            h.people[0].emergencyInformation = PersonEmergencyInformation(severeAllergies: "FICTIONAL EXAMPLE: severe peanut allergy", responderInstructions: "FICTIONAL EXAMPLE: use the recorded communication board")
            let places = [SavedPlace(id: "example-near", homeID: h.stableHomeID, purpose: .outsideMeetingPoint, label: "Example mailbox", addressText: "Outside 123 Example Lane", findingInstructions: "Fictional landmark beside the driveway", createdAt: LeadTestSupport.fixedDate, updatedAt: LeadTestSupport.fixedDate),
                          SavedPlace(id: "example-backup", homeID: h.stableHomeID, purpose: .backupMeetingPlace, label: "Example relative's home", addressText: "456 Fictional Road, Another Town", findingInstructions: "Call the example contact before going", createdAt: LeadTestSupport.fixedDate, updatedAt: LeadTestSupport.fixedDate)]
            let results = try PlanIntegrationTests.scenarioIDs.map { try e.engine.run(PlanIntegrationTests.input(e, h, $0)) }
            let options = PlanBuilder.Options(familyCardSelection: .init(includeCriticalInformation: true, includeMedication: true, includeResponderInstructions: true))
            let full = PlanBuilder.build(household: h, home: SampleHomes.ranch, savedPlaces: places, results: results,
                localizer: e.content.localizer(for: locale), resources: [], contentVersion: e.content.contentVersion,
                generatedAt: LeadTestSupport.fixedDate, options: options)
            // Reference-only envelope supplements the PlanDocument JSON with its computed plain panel
            // descriptors. Production persistence remains one canonical geometry/routes snapshot.
            var reference = try JSONSerialization.jsonObject(with: DryRunJSON.encoder().encode(full)) as! [String: Any]
            reference["referenceHomePanels"] = try JSONSerialization.jsonObject(with: DryRunJSON.encoder().encode(full.visualSnapshot?.homePanels ?? []))
            reference["referencePanelTitles"] = Dictionary(uniqueKeysWithValues: (full.visualSnapshot?.homePanels ?? []).map { ($0.id, $0.title(in: full.visualSnapshot!)) })
            if let snapshot = full.visualSnapshot, let home = snapshot.home {
                let positions = Dictionary(uniqueKeysWithValues: snapshot.homePanels.compactMap { panel -> (String, Vec2)? in
                    guard let point = HomeScenePresentation.startingRoomPosition(in: home, route: panel.route),
                          HomeScenePresentation.startingRoom(in: home, route: panel.route)?.floorID == panel.floorID else { return nil }
                    return (panel.id, point)
                })
                reference["referenceStartPositions"] = try JSONSerialization.jsonObject(with: DryRunJSON.encoder().encode(positions))
            }
            try JSONSerialization.data(withJSONObject: reference, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("full-\(locale).json"))
            var noLayout = h; noLayout.equipment = []; noLayout.backupPower = []
            var card = PlanBuilder.build(household: noLayout, home: nil, savedPlaces: places, results: [],
                localizer: e.content.localizer(for: locale), resources: [], contentVersion: e.content.contentVersion,
                generatedAt: LeadTestSupport.fixedDate, options: options)
            card.pages = card.pages.filter { $0.id == "family-card" }
            card.visualSnapshot = nil
            try DryRunJSON.encoder().encode(card).write(to: dir.appendingPathComponent("card-\(locale).json"))
            if locale == "vi" {
                noLayout.people[0].emergencyInformation?.responderInstructions = String(repeating: "FICTIONAL LONG NOTE: Please use the recorded communication board; these are user-entered example words. ", count: 120) + "END OF LONG EXAMPLE NOTE"
                for index in 1...8 { noLayout.people.append(Person(id: "example-\(index)", alias: "Example person \(index)", ageBand: .unknown)) }
                var long = PlanBuilder.build(household: noLayout, home: nil, savedPlaces: places, results: [],
                    localizer: e.content.localizer(for: locale), resources: [], contentVersion: e.content.contentVersion,
                    generatedAt: LeadTestSupport.fixedDate, options: options)
                long.pages = long.pages.filter { $0.id == "family-card" }
                long.visualSnapshot = nil
                try DryRunJSON.encoder().encode(long).write(to: dir.appendingPathComponent("card-large-long-vi.json"))
            }
        }
    }

}
