import Foundation
import Testing
@testable import DryRunCore

@Suite("Medical power-outage card")
struct OutageCardTests {
    static func card(_ h: HouseholdProfile, locale: String = "en", privateNotes: Bool = false) throws -> PlanDocument {
        let l = try PlanBuilderTests.localizer(locale)
        let lib = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        return OutageCardBuilder.build(household: h, homeID: "home-test", homeRevision: 1, localizer: l,
                                       resources: lib.resources(forRegion: h.regionID), contentVersion: "x",
                                       generatedAt: LeadTestSupport.fixedDate,
                                       options: .init(includePrivateNotes: privateNotes))
    }

    /// The Oak household after the preparations the outage card asks for.
    static var preparedOak: HouseholdProfile {
        var h = SampleHouseholds.oak
        h.backupPower[0].setupConfirmed = .confirmed(true)
        h.equipment[0].compatibleBackupIDs = ["bk-station"]
        h.equipment[0].documentedBackupRuntimeHours = .confirmed(6, unit: "h")
        h.contacts.append(HouseholdContact(id: "ct-care", role: .careProvider, alias: "Oxygen supplier (fictional)", phone: "254-555-0199"))
        h.transport.destinations = [RelocationDestination(id: "d1", kind: .friendOrFamilyHome, label: "Aunt's house (fictional)",
                                                          conditionsConfirmed: .confirmed(true))]
        return h
    }

    @Test("One card per essential device; it validates in EN, ES and VI with no unresolved keys or placeholders")
    func validatesInEveryLocale() throws {
        for h in SampleHouseholds.all + [Self.preparedOak] {
            for locale in ["en", "es", "vi"] {
                let doc = try Self.card(h, locale: locale)
                #expect(doc.pages.count == h.equipment.filter(\.isEssential).count)
                let allCards = doc.pages.allSatisfy(\.kind.isOutageCard)
                #expect(allCards)
                #expect(PlanValidator.validate(doc, household: h).isEmpty, "\(h.id) \(locale): \(PlanValidator.validate(doc, household: h))")
            }
        }
    }

    @Test("An unknown runtime is printed as unknown, never estimated, and missing facts are listed as gaps")
    func unknownsStayUnknown() throws {
        let oak = SampleHouseholds.oak
        let page = try Self.card(oak).pages[0]
        let text = page.sections.flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(text.contains("Oxygen concentrator, used by Grandpa"))
        #expect(text.contains("Runtime on backup: unknown"))
        #expect(text.contains("No backup is recorded as working with this device."))
        #expect(!text.contains("Switch Oxygen concentrator"), "no switch-over step without a tested backup")
        #expect(text.contains("911"))
        #expect(Set(OutageCardBuilder.gaps(for: oak.equipment[0], in: oak)) ==
                [.noCompatibleBackup, .runtimeUnknown, .noCareContact, .noConfirmedDestination])
    }

    @Test("Recorded facts appear on the card and close their gaps")
    func preparedHousehold() throws {
        let h = Self.preparedOak
        #expect(OutageCardBuilder.gaps(for: h.equipment[0], in: h).isEmpty)
        let page = try Self.card(h).pages[0]
        let text = page.sections.flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(text.contains("Portable battery station: compatibility and source setup are recorded."))
        #expect(text.contains("6 hours (documented by the household)"))
        #expect(text.contains("Switch Oxygen concentrator to Portable battery station."))
        #expect(text.contains("Oxygen supplier (fictional): 254-555-0199"))
        #expect(text.contains("Aunt's house (fictional) (confirmed with the host)"))
        #expect(!page.sections.contains { $0.id == "gaps" })
    }

    @Test("A destination not confirmed with its host is never printed as a place to go")
    func unconfirmedDestination() throws {
        var h = SampleHouseholds.oak
        h.transport.destinations = [RelocationDestination(id: "d1", kind: .publicWarmingOrCoolingSite, label: "Library warming center")]
        let text = try Self.card(h).pages[0].sections.flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(!text.contains("Library warming center"))
        #expect(text.contains("No place to go is confirmed yet."))
    }

    @Test("Care-plan notes are left out unless the household chooses to include them")
    func privateNotes() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].carePlanNotes = "Private note 4417"
        let without = try Self.card(h)
        #expect(!without.pages[0].sections.flatMap(\.lines).contains { $0.text.contains("Private note 4417") })
        let withNotes = try Self.card(h, privateNotes: true)
        #expect(withNotes.pages[0].sections.flatMap(\.lines).contains { $0.text.contains("Private note 4417") })
        #expect(PlanValidator.validate(withNotes, household: h).isEmpty)
    }

    @Test("A household without essential equipment gets no cards")
    func noEquipment() throws {
        var h = SampleHouseholds.oak
        h.equipment = []
        let doc = try Self.card(h)
        #expect(doc.pages.isEmpty)
    }
}

@Suite("Next steps")
struct NextStepsTests {
    static func results(_ h: HouseholdProfile) throws -> [RehearsalResult] {
        try SimFixtures.scenarioIDs.map { try SimFixtures.run(h, $0) }
    }

    @Test("Preparations are merged across scenarios, each listed once, ordered by tier")
    func mergedAndOrdered() throws {
        let h = SampleHouseholds.oak
        let results = try Self.results(h)
        let summary = NextSteps.summarize(results, household: h)
        let ids = summary.toDo.map(\.id)
        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count, "each preparation appears once")
        #expect(ids.contains("prep.water"))
        #expect(!ids.contains("act.water.store-3day"), "the same water record is not listed twice")
        #expect(ids.contains("prep.medicalBackup|equipment.eq-oxygen"))
        let tiers = summary.toDo.map(\.recommendation.tier)
        #expect(tiers == tiers.sorted(), "ordered by the ranker's tier")
        for step in summary.toDo where !step.recommendation.actionID.hasPrefix("prep.") {
            let raisedIn = Set(results.filter { $0.recommendations.contains { $0.id == step.id } }.map(\.input.scenarioID))
            #expect(Set(step.scenarioIDs) == raisedIn)
            #expect(step.scenarioIDs.contains(step.sourceScenarioID))
            let best = results.flatMap(\.recommendations).filter { $0.id == step.id }.map(\.tier).min()
            #expect(step.recommendation.tier == best)
        }
        #expect(summary.toDo.contains { $0.id == "prep.medicalBackup|equipment.eq-oxygen" }, "the oxygen backup has its own subject and direct editor")
    }

    @Test("Marking a preparation completed moves it from to-do to completed")
    func completedMoves() throws {
        var h = SampleHouseholds.oak
        let results = try Self.results(h)
        let first = try #require(NextSteps.summarize(results, household: h).toDo.first { !$0.recommendation.actionID.hasPrefix("prep.") && $0.recommendation.subjectID == nil })
        h.completedPreparations.append(CompletedPreparation(actionID: first.id, completedAt: LeadTestSupport.fixedDate))
        let after = NextSteps.summarize(results, household: h)
        #expect(!after.toDo.contains { $0.id == first.id })
        #expect(after.completed.map(\.id) == [first.id])
        #expect(after.completed.first?.completedAt == LeadTestSupport.fixedDate)
    }

    @Test("The summary does not depend on the order results arrive in")
    func orderIndependent() throws {
        let h = SampleHouseholds.lake
        let results = try Self.results(h)
        let a = NextSteps.summarize(results, household: h)
        let b = NextSteps.summarize(results.reversed(), household: h)
        #expect(a.toDo.map(\.id) == b.toDo.map(\.id))
        #expect(a.toDo.map(\.sourceScenarioID) == b.toDo.map(\.sourceScenarioID))
        #expect(a.unknownFacts == b.unknownFacts)
    }
}
