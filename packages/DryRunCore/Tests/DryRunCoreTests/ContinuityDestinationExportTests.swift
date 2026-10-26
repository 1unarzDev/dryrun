import Foundation
import Testing
@testable import DryRunCore

@Suite("Continuity destinations in the family card and plan")
struct ContinuityDestinationExportTests {
    private func document(_ household: HouseholdProfile, locale: String) throws -> PlanDocument {
        PlanBuilder.build(household: household, home: nil, results: [], localizer: try PlanBuilderTests.localizer(locale),
                          resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
    }

    @Test("A confirmed continuity destination survives reload and appears in both portable documents without becoming a meetup")
    func confirmedDestination() throws {
        var household = SampleHouseholds.oak
        household.equipment = []
        household.transport.destinations = [RelocationDestination(id: "recorded", kind: .friendOrFamilyHome,
            label: "Example aunt's home", conditionsConfirmed: .confirmed(true))]
        let restored = try JSONDecoder().decode(HouseholdProfile.self, from: JSONEncoder().encode(household))
        for locale in ["en", "es", "vi"] {
            let doc = try document(restored, locale: locale)
            let card = try #require(doc.pages.first { $0.id == "family-card" })
            let essentials = try #require(doc.pages.first { $0.id == "essentials" })
            let cardLine = try #require(card.sections.flatMap(\.lines).first { $0.key == "plan.transport.destination.recorded" })
            let planLine = try #require(essentials.sections.flatMap(\.lines).first { $0.key == "plan.transport.destination.recorded" })
            #expect(cardLine == planLine && cardLine.text.contains("Example aunt's home"))
            #expect(!cardLine.isFallback && cardLine.unfilledPlaceholders.isEmpty)
            #expect(doc.visualSnapshot?.savedPlaces.isEmpty == true)
            #expect(!card.sections.filter { ["outsideMeetingPoint", "backupMeetingPlace"].contains($0.id) }.flatMap(\.lines).contains { $0.text.contains("Example aunt's home") })
            #expect(PlanValidator.validate(doc, household: restored).isEmpty)
        }
    }

    @Test("Unknown, assumed, refused and blank destinations never appear as confirmed places to go")
    func unconfirmedDestinations() throws {
        var household = SampleHouseholds.oak
        household.transport.destinations = [
            .init(id: "unknown", kind: .friendOrFamilyHome, label: "UNKNOWN-CANARY"),
            .init(id: "assumed", kind: .hotel, label: "ASSUMED-CANARY", conditionsConfirmed: .assumed(true)),
            .init(id: "refused", kind: .publicShelter, label: "REFUSED-CANARY", conditionsConfirmed: .confirmed(false)),
            .init(id: "blank", kind: .other, label: " \n ", conditionsConfirmed: .confirmed(true))
        ]
        for locale in ["en", "es", "vi"] {
            let doc = try document(household, locale: locale)
            #expect(PlanValidator.validate(doc, household: household).isEmpty)
            for page in doc.pages {
                let lines = page.sections.flatMap(\.lines)
                #expect(!lines.contains { $0.text.contains("CANARY") })
                #expect(lines.contains { $0.key == "card.goTo.none" && !$0.isFallback })
            }
        }
    }

    @Test("A household's public-site confirmation stays qualified and cannot certify current official activation")
    func publicSites() throws {
        var household = SampleHouseholds.oak
        household.transport.destinations = [
            .init(id: "shelter", kind: .publicShelter, label: "Example public shelter", conditionsConfirmed: .confirmed(true)),
            .init(id: "cooling", kind: .publicWarmingOrCoolingSite, label: "Example cooling site", conditionsConfirmed: .confirmed(true))
        ]
        for locale in ["en", "es", "vi"] {
            let doc = try document(household, locale: locale)
            let localizer = try PlanBuilderTests.localizer(locale)
            for page in doc.pages {
                let lines = page.sections.flatMap(\.lines).filter { $0.key == "plan.transport.destination.public" }
                #expect(lines.count == 2)
                #expect(!page.sections.flatMap(\.lines).contains { $0.key == "plan.transport.destination.recorded" })
                #expect(lines.allSatisfy { !$0.isFallback && $0.unfilledPlaceholders.isEmpty })
                for destination in household.transport.destinations {
                    #expect(lines.contains { $0.text == localizer("plan.transport.destination.public", ["place": destination.label]) })
                }
            }
        }
    }
}
