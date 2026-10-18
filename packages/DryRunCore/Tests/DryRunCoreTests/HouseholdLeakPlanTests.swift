import Foundation
import Testing
@testable import DryRunCore

@Suite("Local leak plan content")
struct HouseholdLeakPlanTests {
    private func document(_ result: RehearsalResult, locale: String) throws -> PlanDocument {
        PlanBuilder.build(household: result.input.household, home: result.input.home, results: [result],
                          localizer: try PlanBuilderTests.localizer(locale), resources: [], contentVersion: "test",
                          generatedAt: LeadTestSupport.fixedDate)
    }

    @Test("Local leak exports use localized leak instructions, affected rooms, source scope and visual labels")
    func leakContent() throws {
        var input = SimFixtures.input(SampleHouseholds.oak, "flash-flood")
        input.spatialOptions = .init(floodAffectedSpaceIDs: ["sp-kitchen"], floodIsHouseholdLeak: true)
        let result = try SimFixtures.engine.run(input)
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            let doc = try document(result, locale: locale)
            let page = try #require(doc.pages.first { $0.id == "scenario-flash-flood" })
            #expect(page.title.contains(localizer("scenario.household-leak.title")))
            let immediate = try #require(page.sections.first { $0.id == "immediate" })
            #expect(immediate.lines.count == 5)
            #expect(immediate.lines.allSatisfy { $0.key.hasPrefix("plan.scenario.household-leak.") && $0.resolvedLocale == locale && !$0.isFallback && $0.unfilledPlaceholders.isEmpty })
            #expect(immediate.lines.allSatisfy { $0.sourceIDs == ["S23"] })
            #expect(immediate.lines.prefix(2).allSatisfy { $0.style == .prohibition })
            #expect(!page.sections.flatMap(\.lines).contains { $0.key.hasPrefix("plan.scenario.flash-flood.immediate.") })
            #expect(!page.sections.contains { $0.id == "transport" })
            let homeLines = try #require(page.sections.first { $0.id == "homeplan" }?.lines)
            #expect(homeLines.contains { $0.key == "plan.scenario.household-leak.affected" && $0.text.contains("Kitchen") })
            #expect(homeLines.contains { $0.key == "plan.scenario.household-leak.noRoute" })
            let visual = try #require(doc.visualSnapshot)
            #expect(visual.scenarioLabels?["flash-flood"] == localizer("scenario.household-leak.title"))
            #expect(visual.exerciseStates?.first?.state == result.snapshots.last?.spatialState)
            #expect(doc.contentReviewBanner == localizer("plan.contentDraftBanner"))
            #expect(PlanValidator.validate(doc, household: input.household).isEmpty)
        }
    }

    @Test("Regional flood exports retain official-direction guidance while no-layout leaks retain their identity")
    func regionalAndMissingLayout() throws {
        let regional = try SimFixtures.run(SampleHouseholds.oak, "flash-flood")
        var noLayoutInput = SimFixtures.input(SampleHouseholds.oak, "flash-flood", variants: ["householdLeak"])
        noLayoutInput.home = nil
        let noLayoutLeak = try SimFixtures.engine.run(noLayoutInput)
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            let regionalDoc = try document(regional, locale: locale)
            let regionalPage = try #require(regionalDoc.pages.first { $0.id == "scenario-flash-flood" })
            #expect(regionalPage.sections.first { $0.id == "immediate" }?.lines.map(\.key) == (1...4).map { "plan.scenario.flash-flood.immediate.\($0)" })
            #expect(regionalDoc.visualSnapshot?.scenarioLabels?["flash-flood"] == localizer("common.scenario.flash-flood"))
            let leakDoc = try document(noLayoutLeak, locale: locale)
            let leakPage = try #require(leakDoc.pages.first { $0.id == "scenario-flash-flood" })
            #expect(leakPage.title.contains(localizer("scenario.household-leak.title")))
            #expect(leakPage.sections.first { $0.id == "homeplan" }?.lines.first?.key == "map.layoutMissing")
            #expect(leakDoc.visualSnapshot?.home == nil && leakDoc.visualSnapshot?.routes.isEmpty == true)
            #expect(PlanValidator.validate(leakDoc, household: noLayoutInput.household).isEmpty)
        }
    }
}
