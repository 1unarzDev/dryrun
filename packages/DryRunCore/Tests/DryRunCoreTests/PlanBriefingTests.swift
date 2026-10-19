import Foundation
import Testing
@testable import DryRunCore

@Suite("For your family: briefing inputs and acceptance")
struct PlanBriefingTests {
    @Test("Model inputs carry no names, custom labels, notes, contacts or address")
    func factsAndRedactionDoNotLeak() {
        var h = SampleHouseholds.oak
        h.people[0].alias = "ZELDA-CANARY"
        h.people[0].emergencyInformation = .init(criticalConditions: "NOTE-CANARY")
        h.equipment = [PoweredEquipment(id: "e", purpose: .oxygenConcentrator, label: "LABEL-CANARY", personID: h.people[0].id)]
        h.contacts = [HouseholdContact(id: "c", role: .outOfAreaContact, alias: "CONTACT-CANARY", phone: "817-555-0100")]
        h.privateLocation = PrivateLocation(addressLine: "ADDRESS-CANARY")
        let facts = PlanBriefing.familyFacts(h, regionName: "Tarrant County").joined(separator: "\n")
        for canary in ["ZELDA", "NOTE", "LABEL", "CONTACT", "ADDRESS", "555"] { #expect(!facts.contains(canary)) }
        #expect(facts.contains("oxygen concentrator that needs electricity"))
        #expect(facts.contains("Tarrant County"))
        let redacted = PlanBriefing.redact("Charge LABEL-CANARY for Zelda-canary; tell contact-canary.", household: h)
        #expect(!redacted.lowercased().contains("canary"))
    }

    @Test("Generated sentences may not add numbers, links, or clinical and certainty words")
    func acceptance() {
        let sources = ["Confirm a backup for the oxygen concentrator", "Power loss stops it. Ask the supplier about backup options."]
        #expect(PlanBriefing.accept("Because your mother's oxygen concentrator needs electricity, ask the supplier about a backup.", sources: sources, locale: "en"))
        #expect(!PlanBriefing.accept("A backup gives you 4 hours.", sources: sources, locale: "en"))
        #expect(!PlanBriefing.accept("This guarantees she will survive an outage.", sources: sources, locale: "en"))
        #expect(!PlanBriefing.accept("See https://example.com for details.", sources: sources, locale: "en"))
        #expect(!PlanBriefing.accept("Lower the dose during an outage.", sources: sources, locale: "en"))
        // Observed from the simulator model: "Choosing a safe place … is vital". Safety claims are not the model's to make.
        #expect(!PlanBriefing.accept("Choosing a safe place and a way to get there matters for you.", sources: sources, locale: "en"))
        #expect(PlanBriefing.accept("Choosing a safe place matters for you.", sources: ["Find a safe place"], locale: "en"))
        #expect(!PlanBriefing.accept("Uno. Dos. Tres. Cuatro.", sources: sources, locale: "es"))
        #expect(!PlanBriefing.accept("Anything", sources: sources, locale: "vi"))   // no validator for this language yet
        #expect(!PlanBriefing.accept(String(repeating: "a", count: 300), sources: sources, locale: "en"))
        // A number the step itself states may be repeated.
        #expect(PlanBriefing.accept("Store 3 days of water for everyone.", sources: ["Store 3 days of water"], locale: "en"))
        #expect(PlanBriefing.accept("Pregunte al proveedor por una batería de respaldo.", sources: sources, locale: "es"))
        #expect(!PlanBriefing.accept("Así sobrevivirá el apagón.", sources: sources, locale: "es"))
    }
}
