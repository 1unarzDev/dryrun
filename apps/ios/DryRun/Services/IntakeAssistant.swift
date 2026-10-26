import Foundation
import DryRunCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Describe your household in your own words" → a proposal the family reviews before anything is added.
///
/// Runs only on this iPhone: Apple's on-device model when Apple Intelligence is available and supports the
/// family's language, otherwise the keyword reader in DryRunCore. There is no cloud fallback. The typed text is
/// never stored; only the confirmed, structured choices reach the encrypted household record.
enum IntakeAssistant {
    /// Long enough for a paragraph about a large family; short enough to stay well inside the model's context.
    static let maxCharacters = 1200

    static func modelCanRead(locale: String) -> Bool {
        guard ExplanationService.availability() == .available else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.supportsLocale(Locale(identifier: locale)) }
        #endif
        return false
    }

    static func propose(from text: String, locale: String) async -> IntakeProposal {
        let input = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        guard !input.isEmpty else { return IntakeProposal(source: .keywords) }
        let keywords = HouseholdIntake.keywordProposal(from: input)
        #if canImport(FoundationModels)
        // Medical facts from the model are grounded in the family's own words (see HouseholdIntake.ground).
        if #available(iOS 26.0, *), modelCanRead(locale: locale), let proposal = await withModelTimeout({ await modelProposal(input) }) {
            let grounded = HouseholdIntake.ground(model: proposal, keywords: keywords)
            if !grounded.isEmpty { return grounded }
        }
        #endif
        return keywords
    }

    /// A family should never wait on the model: after this many seconds the keyword reader answers instead.
    static let modelTimeoutSeconds: UInt64 = 20

    /// First of the work or the timeout; the slower one is cancelled.
    static func withModelTimeout<T: Sendable>(_ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(nanoseconds: modelTimeoutSeconds * 1_000_000_000); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func modelProposal(_ text: String) async -> IntakeProposal? {
        let instructions = """
        You read a short description that one family member wrote about the people who live in their home, for a \
        household emergency-preparedness app. The description may be in English, Spanish or Vietnamese.
        Record ONLY facts the text states. Never guess an age group, need, device, pet or home detail that is not \
        stated. Do not add advice. The writer is "the speaker"; put the speaker's own needs and devices in the \
        speaker fields and everyone else in otherPeople. A person's name is the word the text uses for them \
        (for example Mom, Abuela, Rosa), never a medical condition.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text, generating: GeneratedHousehold.self,
                                                     options: GenerationOptions(samplingMode: .greedy))
            return response.content.proposal()
        } catch {
            // Guardrail, refusal, unsupported language or context limit: the keyword reader takes over.
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
// Allowed values mirror DryRunCore's enums. Anything else is dropped when converting, never stored as free text.
@available(iOS 26.0, *)
@Generable(description: "Household facts stated in the description. Leave anything not stated empty or unstated.")
struct GeneratedHousehold {
    @Guide(description: "Assistance needs the speaker states about themself. Empty if none are stated.",
           .element(.anyOf(["usesWheelchair", "cannotUseStairs", "limitedMobility", "needsHelperToEvacuate", "deafOrHardOfHearing",
                            "blindOrLowVision", "cognitiveOrMemory", "communicationSupport", "heatSensitive", "coldSensitive"])))
    var speakerNeeds: [String]
    @Guide(description: "Medical devices or temperature-sensitive medicine the speaker uses themself. Empty if none are stated.",
           .element(.anyOf(["oxygenConcentrator", "cpapOrBipap", "powerWheelchair", "refrigeratedMedication", "homeDialysis",
                            "suction", "feedingPump", "communicationDevice"])))
    var speakerEquipment: [String]
    @Guide(description: "Everyone else who lives in the home and is mentioned. Do not invent people.", .maximumCount(11))
    var otherPeople: [GeneratedPerson]
    @Guide(description: "Pets that live in the home. Empty if none are mentioned.", .maximumCount(6))
    var pets: [GeneratedPet]
    @Guide(.anyOf(["unstated", "singleFamily", "apartment", "manufacturedHome", "townhouse", "duplex"]))
    var homeType: String
    @Guide(.anyOf(["unstated", "owner", "renter"]))
    var tenancy: String
    @Guide(.anyOf(["unstated", "electric", "naturalGas", "propane", "wood"]))
    var heatingFuel: String
    @Guide(.anyOf(["unstated", "centralAC", "windowOrPortableAC", "evaporative", "fansOnly"]))
    var cooling: String
    @Guide(.anyOf(["unstated", "municipal", "privateWell"]))
    var waterSource: String
    @Guide(description: "Number of floors or stories in the home if stated, otherwise 0.", .range(0...5))
    var floors: Int
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPerson {
    @Guide(description: "The word or first name the text uses for this person, e.g. Mom, Abuela, Rosa, Ông.")
    var name: String
    @Guide(.anyOf(["mother", "father", "parent", "guardian", "child", "grandparent", "greatGrandparent", "aunt", "uncle",
                   "sibling", "spousePartner", "caregiver", "otherHouseholdMember"]))
    var relationship: String
    @Guide(description: "Only if stated or plain from words like baby, toddler, teenager, elderly.",
           .anyOf(["unknown", "infant", "child", "teen", "adult", "olderAdult"]))
    var ageGroup: String
    @Guide(description: "Assistance needs stated for this person. Empty if none.",
           .element(.anyOf(["usesWheelchair", "cannotUseStairs", "limitedMobility", "needsHelperToEvacuate", "deafOrHardOfHearing",
                            "blindOrLowVision", "cognitiveOrMemory", "communicationSupport", "heatSensitive", "coldSensitive"])))
    var needs: [String]
    @Guide(description: "Medical devices or temperature-sensitive medicine this person uses. Empty if none.",
           .element(.anyOf(["oxygenConcentrator", "cpapOrBipap", "powerWheelchair", "refrigeratedMedication", "homeDialysis",
                            "suction", "feedingPump", "communicationDevice"])))
    var equipment: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPet {
    @Guide(.anyOf(["dog", "cat", "bird", "smallAnimal", "other"]))
    var kind: String
    @Guide(.range(1...20))
    var count: Int
}

@available(iOS 26.0, *)
extension GeneratedHousehold {
    func proposal() -> IntakeProposal {
        var people = [IntakeProposal.PersonDraft(id: "self", needs: speakerNeeds.compactMap(AssistanceNeed.init(rawValue:)), isSelf: true)]
        var equipment = speakerEquipment.compactMap(EquipmentPurpose.init(rawValue:)).enumerated()
            .map { IntakeProposal.EquipmentDraft(id: "eq-s\($0.offset)", purpose: $0.element, personID: "self") }
        for (i, p) in otherPeople.enumerated() {
            let id = "p\(i)"
            // A name is a short word the family used; anything that looks like more than that is dropped.
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = name.count <= 30 && !name.contains(where: \.isNumber) ? name : ""
            people.append(.init(id: id, alias: alias, ageBand: AgeBand(rawValue: p.ageGroup) ?? .unknown,
                                relationship: FamilyRelationship(rawValue: p.relationship),
                                needs: p.needs.compactMap(AssistanceNeed.init(rawValue:))))
            equipment += p.equipment.compactMap(EquipmentPurpose.init(rawValue:)).enumerated()
                .map { IntakeProposal.EquipmentDraft(id: "eq-\(i)-\($0.offset)", purpose: $0.element, personID: id) }
        }
        return IntakeProposal(
            people: people, equipment: equipment,
            pets: pets.enumerated().compactMap { i, p in PetKind(rawValue: p.kind).map { .init(id: "pet\(i)", kind: $0, count: p.count) } },
            homeType: HomeType(rawValue: homeType), tenancy: Tenancy(rawValue: tenancy),
            heatingFuel: HeatingFuel(rawValue: heatingFuel), cooling: CoolingKind(rawValue: cooling),
            waterSource: WaterSourceKind(rawValue: waterSource), floorCount: floors > 0 ? floors : nil,
            source: .onDeviceModel
        ).sanitized()
    }
}
#endif
