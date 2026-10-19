import Foundation
import DryRunCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "For your family": the on-device model restates the ranker's top preparations in terms of this household.
/// It cannot add, drop or reorder steps; inputs come from `PlanBriefing` (no names or private notes) and every
/// sentence must pass `PlanBriefing.accept`. Without Apple Intelligence, or in a language without a validator,
/// nothing is shown and the authored step text stands on its own.
enum FamilyBriefingService {
    struct StepText: Equatable { let id: String; let title: String; let why: String }
    struct Briefing: Equatable { var overview: String?; var notes: [String: String] }

    static func canWrite(locale: String) -> Bool {
        PlanBriefing.supportsLocale(locale) && IntakeAssistant.modelCanRead(locale: locale)
    }

    static func write(steps: [StepText], household: HouseholdProfile, regionName: String?, locale: String) async -> Briefing? {
        let steps = Array(steps.prefix(PlanBriefing.maxSteps))
        guard !steps.isEmpty, canWrite(locale: locale) else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let redacted = steps.map { StepText(id: $0.id, title: PlanBriefing.redact($0.title, household: household),
                                                why: PlanBriefing.redact($0.why, household: household)) }
            let facts = PlanBriefing.familyFacts(household, regionName: regionName)
            let language = locale == "es" ? "Spanish" : "English"
            let instructions = """
            You help a family understand their emergency-preparedness plan. Write in plain, calm \(language) that a \
            twelve-year-old can follow. Use ONLY the household facts and preparations given. Do not add steps, \
            numbers, durations, medical advice, phone numbers, links or predictions about what will happen. Never \
            say anything is guaranteed or safe. Speak directly to the family as "you" and "your". Refer to people by role \
            (your mother, someone in your home), not by name.
            """
            let prompt = """
            Household facts:
            \(facts.map { "- \($0)" }.joined(separator: "\n"))

            Preparations, most important first:
            \(redacted.enumerated().map { "\($0.offset + 1). \($0.element.title): \($0.element.why)" }.joined(separator: "\n"))
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, generating: GeneratedBriefing.self,
                                                         options: GenerationOptions(samplingMode: .greedy))
                let sources = facts + redacted.flatMap { [$0.title, $0.why] }
                var briefing = Briefing(overview: nil, notes: [:])
                let overview = response.content.overview
                if PlanBriefing.accept(overview, sources: sources, locale: locale) { briefing.overview = overview }
                for note in response.content.notes {
                    let index = note.number - 1
                    guard redacted.indices.contains(index), briefing.notes[redacted[index].id] == nil,
                          PlanBriefing.accept(note.forThisFamily, sources: [redacted[index].title, redacted[index].why] + facts, locale: locale)
                    else { continue }
                    briefing.notes[redacted[index].id] = note.forThisFamily
                }
                return briefing.overview == nil && briefing.notes.isEmpty ? nil : briefing
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A short, plain explanation of a family's top preparations")
struct GeneratedBriefing {
    @Guide(description: "One sentence connecting this household's situation to the preparations, without adding any.")
    var overview: String
    @Guide(description: "One note per preparation, in the order given.", .count(1...3))
    var notes: [GeneratedStepNote]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedStepNote {
    @Guide(description: "The preparation's number from the list.", .range(1...3))
    var number: Int
    @Guide(description: "One sentence: why this preparation matters for this household, using only the facts given.")
    var forThisFamily: String
}
#endif
