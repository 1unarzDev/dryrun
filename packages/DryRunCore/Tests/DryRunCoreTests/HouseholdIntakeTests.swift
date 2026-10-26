import Foundation
import Testing
@testable import DryRunCore

@Suite("Describe your family: intake proposals")
struct HouseholdIntakeTests {
    private func person(_ p: IntakeProposal, _ r: FamilyRelationship) -> IntakeProposal.PersonDraft? {
        p.people.first { $0.relationship == r }
    }

    @Test("English: people, who uses which device, follow-up pronouns, home and pets")
    func english() throws {
        let p = HouseholdIntake.keywordProposal(from: "My mom lives with us. She uses oxygen and a walker. We rent an apartment and have two dogs. Grandpa is deaf.")
        let mom = try #require(person(p, .mother))
        #expect(mom.alias == "Mom")
        #expect(mom.needs == [.limitedMobility])
        #expect(p.equipment.map(\.purpose) == [.oxygenConcentrator])
        #expect(p.equipment.first?.personID == mom.id)
        let grandpa = try #require(person(p, .grandparent))
        #expect(grandpa.needs == [.deafOrHardOfHearing])
        #expect(p.homeType == .apartment); #expect(p.tenancy == .renter)
        #expect(p.pets == [.init(id: p.pets[0].id, kind: .dog, count: 2)])
        #expect(p.source == .keywords)
    }

    @Test("Spanish, with and without accents")
    func spanish() throws {
        let p = HouseholdIntake.keywordProposal(from: "Vivo con mi abuela, ella usa oxigeno y silla de ruedas. Tenemos un perro y alquilamos una casa movil.")
        let abuela = try #require(person(p, .grandparent))
        #expect(abuela.alias == "Abuela")
        #expect(abuela.needs.contains(.usesWheelchair))
        #expect(p.equipment.first?.purpose == .oxygenConcentrator)
        #expect(p.equipment.first?.personID == abuela.id)
        #expect(p.pets.first?.kind == .dog && p.pets.first?.count == 1)
        #expect(p.homeType == .manufacturedHome); #expect(p.tenancy == .renter)
    }

    @Test("Vietnamese keeps tone marks: ông bà is two grandparents, and mẹ is not the English 'me'")
    func vietnamese() throws {
        let p = HouseholdIntake.keywordProposal(from: "Nhà tôi có ông bà và hai con mèo. Chúng tôi thuê căn hộ.")
        #expect(p.people.filter { $0.relationship == .grandparent }.count == 2)
        #expect(p.pets.first?.kind == .cat && p.pets.first?.count == 2)
        #expect(p.homeType == .apartment); #expect(p.tenancy == .renter)
        let english = HouseholdIntake.keywordProposal(from: "Call me if the power goes out.")
        #expect(english.people.count == 1)
    }

    @Test("Negation and look-alike words are not read as facts")
    func negationAndBoundaries() {
        let p = HouseholdIntake.keywordProposal(from: "We have no pets and don't use oxygen. A hurricane scared my parents.")
        #expect(p.pets.isEmpty)
        #expect(p.equipment.isEmpty)
        #expect(!p.people.contains { $0.needs.contains(.limitedMobility) })   // "cane" inside "hurricane"
        #expect(p.people.filter { $0.relationship == .parent }.count == 2)
        #expect(HouseholdIntake.keywordProposal(from: "Sin perro, sin gato.").pets.isEmpty)
        #expect(HouseholdIntake.keywordProposal(from: "No AC, only fans.").cooling == .fansOnly)
    }

    @Test("The speaker's own needs go to the existing 'you' person")
    func firstPerson() throws {
        var h = HouseholdSetupBlank.make()
        let p = HouseholdIntake.keywordProposal(from: "I use a wheelchair and a CPAP.")
        HouseholdIntake.apply(p, to: &h)
        #expect(h.people.count == 1)
        #expect(h.people[0].needs == [.usesWheelchair])
        #expect(h.equipment.map(\.purpose) == [.cpapOrBipap])
        #expect(h.equipment[0].personID == h.people[0].id)
    }

    @Test("Apply never overwrites what the family entered and adds nothing confirmed")
    func applyKeepsExistingFacts() {
        var h = HouseholdSetupBlank.make()
        h.people[0].alias = "Lan"
        h.people.append(Person(id: "p-mom", alias: "Mom", ageBand: .olderAdult))
        h.housing.homeType = .singleFamily
        h.equipment.append(PoweredEquipment(id: "eq-o2", purpose: .oxygenConcentrator, label: "", personID: "p-mom"))
        let p = HouseholdIntake.keywordProposal(from: "My mom uses oxygen and has dementia. We live in an apartment with a cat.")
        HouseholdIntake.apply(p, to: &h)
        #expect(h.people[0].alias == "Lan")
        #expect(h.people.count == 2)                                     // "Mom" matched by name, not duplicated
        #expect(h.people[1].ageBand == .olderAdult)
        #expect(h.people[1].needs == [.cognitiveOrMemory])
        #expect(h.equipment.count == 1)                                  // same device for the same person: not added again
        #expect(h.housing.homeType == .singleFamily)                     // already set by the family
        #expect(h.pets.map(\.kind) == [.cat])
        #expect(h.pets[0].carrierAvailable.status == .unknown)
        #expect(h.equipment[0].documentedBackupRuntimeHours.status == .unknown)
    }

    @Test("Sanitizing bounds a model's output: one speaker, no orphan owners, no repeats, sane counts")
    func sanitize() {
        let raw = IntakeProposal(
            people: [.init(id: "a", isSelf: true), .init(id: "b", isSelf: true), .init(id: "c", alias: "  Rosa  ", needs: [.heatSensitive, .heatSensitive])],
            equipment: [.init(id: "e1", purpose: .cpapOrBipap, personID: "c"), .init(id: "e2", purpose: .cpapOrBipap, personID: "c"),
                        .init(id: "e3", purpose: .suction, personID: "ghost")],
            pets: [.init(id: "x", kind: .dog, count: 400), .init(id: "y", kind: .dog, count: 1)],
            floorCount: 40, source: .onDeviceModel)
        let s = raw.sanitized()
        #expect(s.people.map(\.id) == ["a", "c"])
        #expect(s.people[1].alias == "Rosa"); #expect(s.people[1].needs == [.heatSensitive])
        #expect(s.equipment.map(\.id) == ["e1", "e3"]); #expect(s.equipment[1].personID == nil)
        #expect(s.pets.count == 1 && s.pets[0].count == 20)
        #expect(s.floorCount == nil)
    }

    /// Observed on the iOS 27 simulator's on-device model (2026-10-18): for "My mom lives with us and uses oxygen…"
    /// it proposed Mom "uses a wheelchair" and no oxygen concentrator.
    @Test("Grounding drops a need the family never mentioned and restores the device the model missed")
    func groundingCorrectsObservedModelError() throws {
        let text = "My mom lives with us and uses oxygen. We rent an apartment and have a dog."
        let model = IntakeProposal(
            people: [.init(id: "self", isSelf: true), .init(id: "p0", alias: "mom", relationship: .mother, needs: [.usesWheelchair])],
            pets: [.init(id: "pet0", kind: .dog)], homeType: .apartment, tenancy: .renter, source: .onDeviceModel)
        let grounded = HouseholdIntake.ground(model: model, keywords: HouseholdIntake.keywordProposal(from: text))
        let mom = try #require(grounded.people.first { $0.relationship == .mother })
        #expect(mom.needs.isEmpty)
        #expect(grounded.equipment.map(\.purpose) == [.oxygenConcentrator])
        #expect(grounded.equipment.first?.personID == mom.id)
        #expect(grounded.pets.map(\.kind) == [.dog]); #expect(grounded.homeType == .apartment)
        #expect(grounded.source == .onDeviceModel)
    }

    @Test("Grounding keeps model facts the words support and adds the speaker's own keyword needs")
    func groundingKeepsSupportedFacts() {
        let text = "I use a walker. Grandpa has a CPAP."
        let model = IntakeProposal(
            people: [.init(id: "self", isSelf: true), .init(id: "p0", alias: "Grandpa", relationship: .grandparent)],
            equipment: [.init(id: "e0", purpose: .cpapOrBipap, personID: "p0")], source: .onDeviceModel)
        let grounded = HouseholdIntake.ground(model: model, keywords: HouseholdIntake.keywordProposal(from: text))
        #expect(grounded.equipment.map(\.purpose) == [.cpapOrBipap]); #expect(grounded.equipment[0].personID == "p0")
        #expect(grounded.people.first(where: \.isSelf)?.needs == [.limitedMobility])
    }

    @Test("An empty or unrelated description proposes nothing")
    func empty() {
        #expect(HouseholdIntake.keywordProposal(from: "").isEmpty)
        #expect(HouseholdIntake.keywordProposal(from: "Hello, we are getting ready for winter.").isEmpty)
    }
}

/// Mirrors the app's create-form draft: one "you" person and nothing else.
enum HouseholdSetupBlank {
    static func make() -> HouseholdProfile {
        HouseholdProfile(id: "hh-test", displayName: "", regionID: "",
                         people: [Person(id: "p-1", alias: "", ageBand: .unknown, isSelf: true)],
                         housing: Housing(homeType: .other, tenancy: .other, heatingFuel: .unknown, cooling: .unknown, waterSource: .unknown),
                         transport: Transport(), supplies: Supplies())
    }
}
